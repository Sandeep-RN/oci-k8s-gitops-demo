#!/usr/bin/env bash
# Open kubectl access to the k3s node's API through an SSH tunnel (ADR 0010).
# The API port (6443) is never open to the internet; only SSH (22) is, and only
# from ssh_allowed_cidr.
#
#   laptop 127.0.0.1:LOCAL_PORT --ssh--> node 127.0.0.1:6443
#
# What it does:
#   1. Reads the node's public IP from Terraform output (terraform/k3s), or from
#      K3S_NODE_IP. Kept in a variable, never printed.
#   2. Copies /etc/rancher/k3s/k3s.yaml from the node over SSH, renames its
#      "default" entries to "k3s", points it at https://127.0.0.1:LOCAL_PORT and
#      writes it to KUBECONFIG_OUT (mode 600, outside the repo). The k3s API
#      certificate already lists 127.0.0.1, so TLS verifies with no override.
#   3. Holds the tunnel open in the foreground. Ctrl+C closes it.
#
# The kubeconfig holds the cluster-admin client certificate. Treat it like a
# password: never copy it into a repo, issue or chat.
#
# LOCAL_PORT defaults to 16443, not 6443, so this tunnel and scripts/oke-tunnel.sh
# (6443) can run at the same time during the move from OKE.
#
# Host key: the first connection trusts the node's key and stores it in your
# known_hosts (trust on first use). A rebuilt node has a new key, and SSH then
# refuses with "REMOTE HOST IDENTIFICATION HAS CHANGED". After a deliberate
# rebuild, remove the old entry: ssh-keygen -R <node-ip>
#
# Usage:  scripts/k3s-tunnel.sh              fetch the kubeconfig, hold the tunnel
#         scripts/k3s-tunnel.sh --no-tunnel  only fetch the kubeconfig
#         then, in another terminal:
#           kubectl --kubeconfig ~/.kube/k3s.kubeconfig get nodes
# Env:    K3S_NODE_IP (default: terraform output; needs a valid OCI session,
#         because the state lives in Object Storage), SSH_KEY (~/.ssh/k3s-node),
#         NODE_USER (ubuntu), LOCAL_PORT (16443),
#         KUBECONFIG_OUT (~/.kube/k3s.kubeconfig)
# Needs:  ssh, kubectl; terraform unless K3S_NODE_IP is set.
# If SSH times out, your public IP probably changed: update ssh_allowed_cidr in
# terraform/k3s/terraform.tfvars, plan and apply.
set -euo pipefail

SSH_KEY="${SSH_KEY:-$HOME/.ssh/k3s-node}"
NODE_USER="${NODE_USER:-ubuntu}"
LOCAL_PORT="${LOCAL_PORT:-16443}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$HOME/.kube/k3s.kubeconfig}"
REMOTE_KUBECONFIG=/etc/rancher/k3s/k3s.yaml
API_PORT=6443

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/k3s"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

HOLD_TUNNEL=1
case "${1:-}" in
  "") ;;
  --no-tunnel) HOLD_TUNNEL=0 ;;
  -h | --help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown argument: $1 (try --help)" ;;
esac

for bin in ssh kubectl; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin not found on PATH"
done
[ -f "$SSH_KEY" ] || die "SSH key not found: $SSH_KEY (set SSH_KEY)"

# --- Node address (sensitive; never printed) --------------------------------------
if [ -n "${K3S_NODE_IP:-}" ]; then
  NODE_IP="$K3S_NODE_IP"
else
  command -v terraform >/dev/null 2>&1 || die "terraform not on PATH (or set K3S_NODE_IP)"
  NODE_IP="$(terraform -chdir="$TF_DIR" output -raw public_ip 2>/dev/null | tr -d '\r')" \
    || die "no Terraform output. Is the OCI session valid (oci session authenticate)? Or set K3S_NODE_IP."
fi
[[ "$NODE_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "node IP does not look like an IPv4 address"

# LogLevel=ERROR hides the "Permanently added '<ip>'" notice, which would put the
# IP on screen (and into pasted terminal output).
SSH_OPTS=(
  -i "$SSH_KEY"
  -o IdentitiesOnly=yes
  -o BatchMode=yes
  -o LogLevel=ERROR
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
)

# --- Kubeconfig ------------------------------------------------------------------
mkdir -p "$(dirname "$KUBECONFIG_OUT")"
# Same directory as the target, so the final mv is atomic and a failed run never
# leaves a half-written kubeconfig behind.
TMP_CFG="$(mktemp "$(dirname "$KUBECONFIG_OUT")/.k3s-kubeconfig.XXXXXX")"
trap 'rm -f "$TMP_CFG"' EXIT
chmod 600 "$TMP_CFG" 2>/dev/null || true

log "fetching the kubeconfig from the node over SSH"
# The path is meant to expand here, on the laptop: it is a fixed path we choose.
# shellcheck disable=SC2029
ssh "${SSH_OPTS[@]}" "${NODE_USER}@${NODE_IP}" "sudo -n cat $REMOTE_KUBECONFIG" >"$TMP_CFG" \
  || die "could not read $REMOTE_KUBECONFIG (SSH blocked, k3s not installed, or no passwordless sudo)"

# k3s names its cluster, user and context "default". Rename them to "k3s" so this
# file can be merged with others without a clash, and point the server at the
# local end of the tunnel.
sed -i -E \
  -e "s#^([[:space:]]*server:[[:space:]]*)https://127\.0\.0\.1:${API_PORT}[[:space:]]*\$#\1https://127.0.0.1:${LOCAL_PORT}#" \
  -e 's#^([[:space:]]*-?[[:space:]]*(name|cluster|user|current-context):[[:space:]]*)default[[:space:]]*$#\1k3s#' \
  "$TMP_CFG"

# Check the edits took: a k3s release that changes the file's layout must fail
# here, not later with a confusing kubectl error.
got_server="$(kubectl --kubeconfig "$TMP_CFG" config view -o jsonpath='{.clusters[?(@.name=="k3s")].cluster.server}')"
got_context="$(kubectl --kubeconfig "$TMP_CFG" config current-context 2>/dev/null || true)"
[ "$got_server" = "https://127.0.0.1:${LOCAL_PORT}" ] \
  || die "kubeconfig rewrite failed (server is '${got_server:-missing}'); the k3s.yaml layout may have changed"
[ "$got_context" = "k3s" ] || die "kubeconfig rewrite failed (context is '${got_context:-missing}')"

mv -f "$TMP_CFG" "$KUBECONFIG_OUT"
chmod 600 "$KUBECONFIG_OUT" 2>/dev/null || true
log "kubeconfig written: $KUBECONFIG_OUT (context k3s, server 127.0.0.1:${LOCAL_PORT})"

[ "$HOLD_TUNNEL" -eq 1 ] || exit 0

# --- Tunnel (foreground) ------------------------------------------------------------
# Fail early with a clear message if the local port is taken (another tunnel?).
if (exec 3<>"/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2>/dev/null; then
  die "127.0.0.1:${LOCAL_PORT} is already in use (another tunnel?). Close it or set LOCAL_PORT."
fi

log "tunnel up on 127.0.0.1:${LOCAL_PORT}. In another terminal:"
log "  kubectl --kubeconfig $KUBECONFIG_OUT get nodes"
log "Ctrl+C to close."
exec ssh "${SSH_OPTS[@]}" \
  -o ServerAliveInterval=30 \
  -o ExitOnForwardFailure=yes \
  -N -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:${API_PORT}" \
  "${NODE_USER}@${NODE_IP}"
