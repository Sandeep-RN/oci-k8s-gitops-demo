#!/usr/bin/env bash
# Open kubectl access to the OKE target's PRIVATE API endpoint (ADR 0010, 0015)
# through an OCI Bastion port-forwarding session.
#
#   laptop:LOCAL_PORT --ssh--> Bastion --> API private IP:6443
#
# What it does:
#   1. Reads bastion/cluster/endpoint from Terraform outputs (terraform/oke).
#   2. Creates a throwaway SSH key and a port-forwarding session (TTL <= 3 h).
#   3. Writes a kubeconfig (outside the repo) pointing at https://127.0.0.1:LOCAL_PORT,
#      with tls-server-name set to the API's private IP so TLS still verifies.
#   4. Holds the tunnel open in the foreground. Ctrl+C deletes the session and key.
#      A hard kill (SIGKILL, closed terminal) cannot run the cleanup; the session
#      then expires on its own at the TTL. Sessions are free either way.
#
# OpenSSH 10 may warn "connection is not using a post-quantum key exchange"
# for the Bastion host. It is informational; the tunnel works.
#
# Usage:  scripts/oke-tunnel.sh
#         then, in another terminal:  kubectl --kubeconfig ~/.kube/oke-demo.kubeconfig get nodes
# Env:    OCI_CLI (default: oci), OCI_PROFILE (oke-demo), OCI_AUTH (security_token),
#         OCI_CONFIG_FILE (~/.oci/config), LOCAL_PORT (6443),
#         SESSION_TTL (10800), KUBECONFIG_OUT (~/.kube/oke-demo.kubeconfig)
# Needs:  terraform, ssh, ssh-keygen, kubectl, OCI CLI; a valid session token.
# If the Bastion rejects you, your public IP probably changed: update
# bastion_client_cidr in terraform/oke/terraform.tfvars and apply.
set -euo pipefail

OCI_CLI="${OCI_CLI:-oci}"
PROFILE="${OCI_PROFILE:-oke-demo}"
AUTH="${OCI_AUTH:-security_token}"
CONFIG_FILE="${OCI_CONFIG_FILE:-$HOME/.oci/config}"
LOCAL_PORT="${LOCAL_PORT:-6443}"
SESSION_TTL="${SESSION_TTL:-10800}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$HOME/.kube/oke-demo.kubeconfig}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/oke"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

oci_cmd() {
  "$OCI_CLI" --config-file "$CONFIG_FILE" --profile "$PROFILE" --auth "$AUTH" "$@"
}

for bin in terraform ssh ssh-keygen kubectl; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin not found on PATH"
done
command -v "$OCI_CLI" >/dev/null 2>&1 || [ -x "$OCI_CLI" ] || die "OCI CLI not found: $OCI_CLI"

oci_cmd iam region list --query 'data[0].name' --raw-output >/dev/null 2>&1 \
  || die "OCI auth failed. Run: oci session refresh --profile $PROFILE (or session authenticate)"

# --- Terraform outputs (sensitive; kept in variables, never printed) ----------
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
BASTION_ID="$(tf_out bastion_id)"     || die "no Terraform outputs; is the OKE stack applied?"
CLUSTER_ID="$(tf_out cluster_id)"
API_ENDPOINT="$(tf_out api_private_endpoint)" # host:port
API_IP="${API_ENDPOINT%:*}"
API_PORT="${API_ENDPOINT##*:}"
REGION="$(sed -n 's/^region *= *"\(.*\)"/\1/p' "$TF_DIR/terraform.tfvars")"
[ -n "$REGION" ] || die "region not found in $TF_DIR/terraform.tfvars"

# --- Throwaway key and cleanup -------------------------------------------------
WORK_DIR="$(mktemp -d)"
SESSION_ID=""
cleanup() {
  local rc=$?
  if [ -n "$SESSION_ID" ]; then
    log "deleting bastion session"
    oci_cmd bastion session delete --session-id "$SESSION_ID" --force >/dev/null 2>&1 \
      || printf 'WARN: could not delete session; it expires on its own after the TTL\n' >&2
  fi
  rm -rf "$WORK_DIR"
  exit "$rc"
}
trap cleanup EXIT INT TERM

ssh-keygen -q -t ed25519 -N "" -C "oke-tunnel" -f "$WORK_DIR/key"

# --- Port-forwarding session ---------------------------------------------------
log "creating bastion port-forwarding session (TTL ${SESSION_TTL}s)"
SESSION_ID="$(oci_cmd bastion session create-port-forwarding \
  --bastion-id "$BASTION_ID" \
  --display-name "oke-tunnel-$(date +%Y%m%d-%H%M%S)" \
  --ssh-public-key-file "$WORK_DIR/key.pub" \
  --key-type PUB \
  --target-private-ip "$API_IP" \
  --target-port "$API_PORT" \
  --session-ttl "$SESSION_TTL" \
  --query 'data.id' --raw-output)"
[ -n "$SESSION_ID" ] || die "session create returned no id"

# The create call returns while the session is CREATING; poll until ACTIVE.
for _ in $(seq 1 30); do
  state="$(oci_cmd bastion session get --session-id "$SESSION_ID" \
    --query 'data."lifecycle-state"' --raw-output)"
  [ "$state" = "ACTIVE" ] && break
  [ "$state" = "FAILED" ] && die "bastion session FAILED (client IP not in bastion_client_cidr?)"
  sleep 5
done
[ "$state" = "ACTIVE" ] || die "bastion session not ACTIVE after 150s (state: $state)"
log "session active"

# --- Kubeconfig ----------------------------------------------------------------
# --with-auth-context bakes the profile and session-token auth into the exec
# credential plugin, so kubectl uses the same login as this script.
mkdir -p "$(dirname "$KUBECONFIG_OUT")"
oci_cmd ce cluster create-kubeconfig \
  --cluster-id "$CLUSTER_ID" \
  --region "$REGION" \
  --kube-endpoint PRIVATE_ENDPOINT \
  --token-version 2.0.0 \
  --with-auth-context \
  --file "$KUBECONFIG_OUT" \
  --overwrite >/dev/null

# Point the cluster entry at the local tunnel. TLS is verified against the
# certificate's real name (the private IP), not 127.0.0.1.
CLUSTER_NAME="$(kubectl --kubeconfig "$KUBECONFIG_OUT" config view \
  -o jsonpath='{.clusters[0].name}')"
kubectl --kubeconfig "$KUBECONFIG_OUT" config set-cluster "$CLUSTER_NAME" \
  --server "https://127.0.0.1:${LOCAL_PORT}" \
  --tls-server-name "$API_IP" >/dev/null
chmod 600 "$KUBECONFIG_OUT" 2>/dev/null || true
log "kubeconfig written: $KUBECONFIG_OUT"

# --- Tunnel (foreground) ---------------------------------------------------------
# Bastion host keys are not published in advance, so accept the first key but
# keep it in a throwaway known_hosts instead of the user's real one.
log "tunnel up on 127.0.0.1:${LOCAL_PORT}. In another terminal:"
log "  kubectl --kubeconfig $KUBECONFIG_OUT get nodes"
log "Ctrl+C to close (the session is deleted on exit)."
ssh -i "$WORK_DIR/key" \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$WORK_DIR/known_hosts" \
  -o ServerAliveInterval=30 \
  -o ExitOnForwardFailure=yes \
  -N -L "127.0.0.1:${LOCAL_PORT}:${API_IP}:${API_PORT}" \
  -p 22 "${SESSION_ID}@host.bastion.${REGION}.oci.oraclecloud.com"
