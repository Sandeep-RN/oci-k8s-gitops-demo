#!/usr/bin/env bash
# Check the k3s node from the laptop (demo #7, ADR 0001, 0010, 0012). One
# PASS/FAIL/SKIP line per check and a non-zero exit if anything failed. Run it
# after the node is created, after a rebuild (#57), and after any change to
# terraform/k3s.
#
# Usage:  scripts/k3s-verify.sh [--skip-terraform]
#
#   --skip-terraform  skip the two Terraform checks (they need a valid OCI
#                     session, because the state lives in Object Storage)
#
# Checks:
#   terraform-no-drift   `terraform plan` reports no changes
#   prevent-destroy      a plan to destroy the node is refused (plan only;
#                        nothing is applied)
#   ssh-key-only         the node offers SSH public-key login only
#   api-closed           6443 (Kubernetes API) is NOT reachable from here
#   kubelet-closed       10250 (kubelet) is NOT reachable from here
#   bootstrap-done       the first-boot script finished (its log says so)
#   node-ready           the node is Ready, through the SSH tunnel
#   k3s-version          the node runs the pinned k3s_version
#   pod-dns-internet     a throwaway pod resolves cluster DNS and reaches the
#                        internet, and is deleted afterwards
#
# The tunnel checks need scripts/k3s-tunnel.sh running in another terminal.
#
# Env:    K3S_NODE_IP (default: terraform output), SSH_KEY (~/.ssh/k3s-node),
#         NODE_USER (ubuntu), KUBECONFIG (default ~/.kube/k3s.kubeconfig),
#         TEST_IMAGE (docker.io/library/busybox:1.36),
#         TEST_URL (https://example.com)
# Needs:  bash, ssh, kubectl, timeout; terraform unless --skip-terraform and
#         K3S_NODE_IP are both given.
#
# Output masks IPv4 addresses and OCIDs. Exit codes: 0 all checks passed (skips
# are listed), 1 at least one failed, 2 bad usage or missing tools.
set -uo pipefail

SSH_KEY="${SSH_KEY:-$HOME/.ssh/k3s-node}"
NODE_USER="${NODE_USER:-ubuntu}"
KCFG="${KUBECONFIG:-$HOME/.kube/k3s.kubeconfig}"
TEST_IMAGE="${TEST_IMAGE:-docker.io/library/busybox:1.36}"
TEST_URL="${TEST_URL:-https://example.com}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/k3s"

SKIP_TF=0
for arg in "$@"; do
  case "$arg" in
    --skip-terraform) SKIP_TF=1 ;;
    -h | --help) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown argument: %s (try --help)\n' "$arg" >&2; exit 2 ;;
  esac
done

redact() {
  tr -d '\r' | sed -E 's/ocid1\.[a-z0-9_.-]+/<ocid>/g; s/[0-9]{1,3}(\.[0-9]{1,3}){3}/<ip>/g'
}

PASSED=0; FAILED=0; SKIPPED=0
pass() { printf 'PASS  %-18s %s\n' "$1" "$2" | redact; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL  %-18s %s\n' "$1" "$2" | redact; FAILED=$((FAILED + 1)); }
skip() { printf 'SKIP  %-18s %s\n' "$1" "$2" | redact; SKIPPED=$((SKIPPED + 1)); }

need=(ssh kubectl timeout)
[ "$SKIP_TF" -eq 0 ] || [ -z "${K3S_NODE_IP:-}" ] && need+=(terraform)
for bin in "${need[@]}"; do
  command -v "$bin" >/dev/null 2>&1 || { printf '%s not found on PATH\n' "$bin" >&2; exit 2; }
done
[ -f "$SSH_KEY" ] || { printf 'SSH key not found: %s (set SSH_KEY)\n' "$SSH_KEY" >&2; exit 2; }

if [ -n "${K3S_NODE_IP:-}" ]; then
  NODE_IP="$K3S_NODE_IP"
else
  NODE_IP="$(terraform -chdir="$TF_DIR" output -raw public_ip 2>/dev/null | tr -d '\r')" || NODE_IP=""
fi
if ! [[ "$NODE_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
  printf 'no node IP: run oci session authenticate, or set K3S_NODE_IP\n' >&2
  exit 2
fi

SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o LogLevel=ERROR
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
# Callers pass the remote command as fixed strings written in this script.
# shellcheck disable=SC2029
node_ssh() { ssh "${SSH_OPTS[@]}" "${NODE_USER}@${NODE_IP}" "$@"; }
kc() { kubectl --kubeconfig "$KCFG" --request-timeout=20s "$@"; }

# Pinned version: terraform.tfvars wins, else the default in variables.tf.
pinned_k3s_version() {
  local v=""
  [ -f "$TF_DIR/terraform.tfvars" ] \
    && v="$(sed -n -E 's/^[[:space:]]*k3s_version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$TF_DIR/terraform.tfvars" | tr -d '\r' | head -1)"
  [ -n "$v" ] || v="$(sed -n '/variable "k3s_version"/,/^}/p' "$TF_DIR/variables.tf" \
    | sed -n -E 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' | head -1)"
  printf '%s' "$v"
}

# --- Terraform --------------------------------------------------------------------
check_terraform_no_drift() {
  [ "$SKIP_TF" -eq 1 ] && { skip terraform-no-drift "--skip-terraform"; return; }
  local out rc
  out="$(terraform -chdir="$TF_DIR" plan -input=false -no-color -lock-timeout=60s -detailed-exitcode 2>&1)"
  rc=$?
  case "$rc" in
    0) pass terraform-no-drift "plan: no changes" ;;
    2) fail terraform-no-drift "plan: $(printf '%s\n' "$out" | grep -E '^Plan:' | tail -1)" ;;
    *) fail terraform-no-drift "plan errored: $(printf '%s\n' "$out" | grep -m1 -E 'Error' || echo 'see terraform plan')" ;;
  esac
}

check_prevent_destroy() {
  [ "$SKIP_TF" -eq 1 ] && { skip prevent-destroy "--skip-terraform"; return; }
  local out
  # -destroy -target asks Terraform to plan the node's deletion. prevent_destroy
  # must make that plan fail. Nothing is applied either way.
  out="$(terraform -chdir="$TF_DIR" plan -destroy -target=oci_core_instance.node \
    -input=false -no-color -lock-timeout=60s 2>&1)"
  if printf '%s\n' "$out" | grep -q 'Instance cannot be destroyed'; then
    pass prevent-destroy "destroy plan refused by lifecycle.prevent_destroy"
  else
    fail prevent-destroy "destroy plan was NOT refused: $(printf '%s\n' "$out" | grep -E '^Plan:|Error' | head -1)"
  fi
}

# --- From the internet (this laptop) -------------------------------------------------
check_ssh_key_only() {
  local out
  # Offer no key and ask for password methods only. A hardened server lists
  # "publickey" as the only method it accepts.
  out="$(ssh -o BatchMode=yes -o PubkeyAuthentication=no -o IdentitiesOnly=yes \
    -o PreferredAuthentications=password,keyboard-interactive \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
    "${NODE_USER}@${NODE_IP}" true 2>&1)"
  if printf '%s\n' "$out" | grep -q 'Permission denied (publickey)'; then
    pass ssh-key-only "server accepts publickey only"
  else
    fail ssh-key-only "unexpected answer: $(printf '%s\n' "$out" | tail -1)"
  fi
}

port_closed() { # port_closed <name> <port>
  if timeout 6 bash -c "exec 3<>/dev/tcp/${NODE_IP}/$2" 2>/dev/null; then
    fail "$1" "port $2 is reachable from the internet"
  else
    pass "$1" "port $2 not reachable from the internet"
  fi
}

# --- On the node ----------------------------------------------------------------------
check_bootstrap_done() {
  if node_ssh 'sudo -n grep -q "^bootstrap done" /var/log/bootstrap-node.log' 2>/dev/null; then
    pass bootstrap-done "bootstrap-node.log ends with 'bootstrap done'"
  else
    fail bootstrap-done "no 'bootstrap done' in /var/log/bootstrap-node.log (or SSH failed); read the log on the node"
  fi
}

# --- Through the tunnel -------------------------------------------------------------
TUNNEL_OK=0
check_node_ready() {
  if [ ! -f "$KCFG" ]; then
    fail node-ready "no kubeconfig at $KCFG; run scripts/k3s-tunnel.sh"
    return
  fi
  local ready
  if ! ready="$(kc get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>&1)"; then
    fail node-ready "API not reachable through the tunnel; is scripts/k3s-tunnel.sh running? ($(printf '%s' "$ready" | tail -1))"
    return
  fi
  TUNNEL_OK=1
  if [ -n "$ready" ] && ! printf '%s\n' "$ready" | grep -qv '=True$'; then
    pass node-ready "$(printf '%s' "$ready" | tr '\n' ' ')"
  else
    fail node-ready "not all nodes Ready: $(printf '%s' "$ready" | tr '\n' ' ')"
  fi
}

check_k3s_version() {
  [ "$TUNNEL_OK" -eq 1 ] || { skip k3s-version "no tunnel"; return; }
  local want got
  want="$(pinned_k3s_version)"
  got="$(kc get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null)"
  if [ -n "$want" ] && [ "$got" = "$want" ]; then
    pass k3s-version "$got (pinned)"
  else
    fail k3s-version "node runs '${got:-unknown}', pinned is '${want:-unknown}'"
  fi
}

check_pod_dns_internet() {
  [ "$TUNNEL_OK" -eq 1 ] || { skip pod-dns-internet "no tunnel"; return; }
  local pod out
  pod="verify-net-$(date +%s)"
  # Cleanup runs whatever happens, so a failed check leaves no pod behind.
  out="$(kc run "$pod" --image="$TEST_IMAGE" --restart=Never --rm -i --quiet \
    --pod-running-timeout=120s --command -- sh -c \
    "nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 && echo DNS-OK; wget -q -O /dev/null -T 10 '$TEST_URL' && echo NET-OK" 2>&1)"
  kc delete pod "$pod" --ignore-not-found --wait=true >/dev/null 2>&1
  local left
  left="$(kc get pod "$pod" --ignore-not-found -o name 2>/dev/null)"
  if printf '%s' "$out" | grep -q DNS-OK && printf '%s' "$out" | grep -q NET-OK && [ -z "$left" ]; then
    pass pod-dns-internet "cluster DNS and $TEST_URL OK; test pod deleted"
  else
    fail pod-dns-internet "dns=$(printf '%s' "$out" | grep -c DNS-OK) net=$(printf '%s' "$out" | grep -c NET-OK) pod-left='${left}' $(printf '%s' "$out" | grep -v -e DNS-OK -e NET-OK | tail -1)"
  fi
}

# --- Run -----------------------------------------------------------------------------------
check_terraform_no_drift
check_prevent_destroy
check_ssh_key_only
port_closed api-closed 6443
port_closed kubelet-closed 10250
check_bootstrap_done
check_node_ready
check_k3s_version
check_pod_dns_internet

printf '\n%d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
[ "$FAILED" -eq 0 ]
