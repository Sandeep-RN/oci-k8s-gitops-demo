#!/usr/bin/env bash
# Wait for Ampere A1 capacity in the home region, then create the k3s node
# (terraform/k3s). Run it yourself in a terminal you can leave open.
#
# Why: the home region has ONE availability domain, so "try another AD" is not
# an option, and A1 capacity appears in short windows. Polling beats clicking.
#
# Each loop:
#   1. asks OCI's read-only capacity report whether A1 (OCPU/GB from the tfvars
#      defaults, 2 / 12) is available. It costs nothing and creates nothing.
#   2. if AVAILABLE (or every BLIND_EVERY loops, in case the report is wrong),
#      plans and applies terraform/k3s.
#   3. "out of host capacity" -> wait and try again. Any other error -> stop.
#
# Safety:
#   - Before applying, the plan must contain 0 to change and 0 to destroy. If
#     not, the script stops instead of touching anything existing.
#   - Only terraform/k3s is applied (its own state key), never terraform/oke.
#   - Everything printed has OCIDs and IPv4 addresses masked, so a pasted
#     terminal does not leak them into a public issue.
#
# One-time setup, before the first run:
#   oci session authenticate --profile oke-demo --region <home-region>
#   cp terraform/k3s/example.tfvars terraform/k3s/terraform.tfvars   # fill in
#   terraform -chdir=terraform/k3s init -backend-config=../backend.hcl
#
# Usage:  scripts/a1-wait-and-apply.sh
# Env:    OCI_CLI (oci or $HOME/bin/oci.exe), OCI_PROFILE (oke-demo),
#         OCI_AUTH (security_token), OCI_CONFIG_FILE (~/.oci/config),
#         INTERVAL seconds between checks (120), MAX_HOURS (48),
#         BLIND_EVERY loops between report-independent attempts (15),
#         YES=1 to skip the confirmation prompt.
set -euo pipefail

PROFILE="${OCI_PROFILE:-oke-demo}"
AUTH="${OCI_AUTH:-security_token}"
CONFIG_FILE="${OCI_CONFIG_FILE:-$HOME/.oci/config}"
INTERVAL="${INTERVAL:-120}"
MAX_HOURS="${MAX_HOURS:-48}"
BLIND_EVERY="${BLIND_EVERY:-15}"
SHAPE="VM.Standard.A1.Flex"
REFRESH_EVERY=1500 # seconds; session tokens last about an hour

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/k3s"

if [ -z "${OCI_CLI:-}" ]; then
  if command -v oci >/dev/null 2>&1; then OCI_CLI=oci
  elif [ -x "$HOME/bin/oci.exe" ]; then OCI_CLI="$HOME/bin/oci.exe"
  else OCI_CLI=oci; fi
fi

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Mask OCIDs and IPv4 addresses in anything shown on screen; strip CR (Windows).
redact() {
  tr -d '\r' | sed -E 's/ocid1\.[a-z0-9_.-]+/<ocid>/g; s/[0-9]{1,3}(\.[0-9]{1,3}){3}/<ip>/g'
}

oci_cmd() {
  "$OCI_CLI" --config-file "$CONFIG_FILE" --profile "$PROFILE" --auth "$AUTH" "$@" | tr -d '\r'
}

tfvar() { # tfvar <name>: read a simple string/number value from terraform.tfvars
  sed -n -E "s/^${1}[[:space:]]*=[[:space:]]*\"?([^\"#]*)\"?.*/\1/p" "$TF_DIR/terraform.tfvars" | head -1 | tr -d '\r'
}

# --- Preconditions -------------------------------------------------------------
command -v terraform >/dev/null 2>&1 || die "terraform not on PATH"
command -v "$OCI_CLI" >/dev/null 2>&1 || [ -x "$OCI_CLI" ] || die "OCI CLI not found (set OCI_CLI)"
[ -f "$TF_DIR/terraform.tfvars" ] || die "missing $TF_DIR/terraform.tfvars (copy example.tfvars)"
[ -d "$TF_DIR/.terraform" ] || die "run: terraform -chdir=terraform/k3s init -backend-config=../backend.hcl"

TENANCY="$(tfvar tenancy_ocid)"
OCPUS="$(tfvar node_ocpus)";    OCPUS="${OCPUS:-2}"
MEM_GB="$(tfvar node_memory_gbs)"; MEM_GB="${MEM_GB:-12}"
[ -n "$TENANCY" ] || die "tenancy_ocid not found in terraform.tfvars"

check_auth() { oci_cmd iam region list --query 'data[0].name' --raw-output >/dev/null 2>&1; }
check_auth || die "OCI auth failed. Run: oci session authenticate --profile $PROFILE"

# The capacity report wants the AD name and the ROOT compartment (the tenancy).
AD="$(oci_cmd iam availability-domain list --compartment-id "$TENANCY" \
  --query 'data[0].name' --raw-output)"
[ -n "$AD" ] || die "could not read the availability domain"

# --- Terraform helpers -----------------------------------------------------------
PLAN_FILE="$(mktemp)"
trap 'rm -f "$PLAN_FILE"' EXIT

# Plan, and refuse anything that is not purely additive.
plan_is_safe() {
  local out summary
  out="$(terraform -chdir="$TF_DIR" plan -input=false -no-color -out="$PLAN_FILE" 2>&1)" || {
    printf '%s\n' "$out" | redact | tail -20 >&2
    die "terraform plan failed (see above)"
  }
  summary="$(printf '%s\n' "$out" | grep -E '^Plan:|^No changes' | tail -1)"
  log "plan: ${summary:-no summary}"
  case "$summary" in
    "No changes"*) log "nothing to do: infrastructure already matches"; return 2 ;;
    *" 0 to change, 0 to destroy"*) return 0 ;;
    *) die "plan is not purely additive (${summary:-unknown}); refusing to apply. Run terraform plan yourself." ;;
  esac
}

capacity_status() {
  oci_cmd compute compute-capacity-report create \
    --availability-domain "$AD" \
    --compartment-id "$TENANCY" \
    --shape-availabilities "[{\"instanceShape\":\"$SHAPE\",\"instanceShapeConfig\":{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEM_GB}}]" \
    --query 'data."shape-availabilities"[0]."availability-status"' --raw-output 2>/dev/null || echo "UNKNOWN"
}

# --- Confirm once ----------------------------------------------------------------
log "waiting for $SHAPE ($OCPUS OCPU / $MEM_GB GB), checking every ${INTERVAL}s for up to ${MAX_HOURS}h"
plan_is_safe && rc=0 || rc=$?
[ "$rc" -eq 2 ] && exit 0
if [ "${YES:-0}" != "1" ]; then
  printf 'The plan above will be applied automatically when capacity appears. Continue? [yes/N] '
  read -r answer
  [ "$answer" = "yes" ] || die "aborted"
fi

# --- Loop ----------------------------------------------------------------------------
start=$(date +%s); last_refresh=$start; n=0
while :; do
  now=$(date +%s)
  if [ $(( (now - start) / 3600 )) -ge "$MAX_HOURS" ]; then
    die "gave up after ${MAX_HOURS}h without capacity"
  fi
  if [ $(( now - last_refresh )) -ge "$REFRESH_EVERY" ]; then
    "$OCI_CLI" session refresh --config-file "$CONFIG_FILE" --profile "$PROFILE" >/dev/null 2>&1 || true
    last_refresh=$now
  fi
  check_auth || die "OCI session expired. Run: oci session authenticate --profile $PROFILE (then re-run this script)"

  n=$((n + 1))
  status="$(capacity_status)"
  try_apply=0
  [ "$status" = "AVAILABLE" ] && try_apply=1
  if [ $((n % BLIND_EVERY)) -eq 0 ]; then try_apply=1; fi
  if [ "$try_apply" -eq 1 ]; then
    log "attempt $n: capacity report = $status; trying to apply"
  else
    log "attempt $n: capacity report = $status; waiting"
  fi

  if [ "$try_apply" -eq 1 ]; then
    plan_is_safe && rc=0 || rc=$?
    [ "$rc" -eq 2 ] && exit 0
    if out="$(terraform -chdir="$TF_DIR" apply -input=false -no-color "$PLAN_FILE" 2>&1)"; then
      printf '%s\n' "$out" | redact | tail -8
      log "SUCCESS: node created. Next: terraform -chdir=terraform/k3s output -raw public_ip"
      printf '\a'
      exit 0
    fi
    if printf '%s\n' "$out" | grep -qiE 'out of (host )?capacity|OutOfHostCapacity'; then
      log "no capacity yet; will retry"
    else
      printf '%s\n' "$out" | redact | tail -25 >&2
      die "apply failed for a reason other than capacity (see above)"
    fi
  fi
  # Jitter avoids hammering the API on a fixed beat.
  sleep $(( INTERVAL + RANDOM % 20 ))
done
