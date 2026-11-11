#!/usr/bin/env bash
# Offline test for scripts/a1-wait-and-apply.sh (demo #7). No cloud calls:
# terraform, the OCI CLI and sleep are replaced by stubs, and the script runs
# from a throwaway copy of the repo layout with fake tfvars.
#
# Cases:
#   1. capacity error, then any other error -> retries once, then stops (exit 1)
#   2. plan that changes something existing  -> refuses, never applies (exit 1)
#   3. capacity error, then success          -> exit 0, SUCCESS line
#   4. plan says "No changes"                -> exit 0, never applies
#
# Usage:  scripts/tests/a1-wait-and-apply.test.sh
# Exit:   0 all cases passed, 1 otherwise.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$REPO_ROOT/scripts/a1-wait-and-apply.sh"
[ -f "$SUT" ] || { echo "missing $SUT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Throwaway repo layout: the script finds terraform/k3s next to its own folder.
mkdir -p "$WORK/repo/scripts" "$WORK/repo/terraform/k3s/.terraform" "$WORK/bin"
cp "$SUT" "$WORK/repo/scripts/"
cat >"$WORK/repo/terraform/k3s/terraform.tfvars" <<'EOF'
tenancy_ocid    = "ocid1.tenancy.oc1..aaaafake"
node_ocpus      = 2
node_memory_gbs = 12
EOF

# Fake OCI CLI: auth works, one AD, the capacity report says AVAILABLE.
cat >"$WORK/bin/oci" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"iam region list"*) echo "ap-fake-1" ;;
  *"availability-domain list"*) echo "FAKE:AP-FAKE-1-AD-1" ;;
  *"compute-capacity-report create"*) echo "AVAILABLE" ;;
  *"session refresh"*) : ;;
  *) echo "unexpected oci call: $*" >&2; exit 1 ;;
esac
EOF

# Fake terraform. STUB_PLAN is the plan summary; STUB_APPLIES is a
# space-separated list of outcomes, one per apply call:
#   capacity | other | ok
cat >"$WORK/bin/terraform" <<'EOF'
#!/usr/bin/env bash
state="$STUB_STATE"
case " $* " in
  *" plan "*) echo "$STUB_PLAN" ;;
  *" apply "*)
    n=$(( $(cat "$state/applies" 2>/dev/null || echo 0) + 1 ))
    echo "$n" >"$state/applies"
    outcome="$(echo "$STUB_APPLIES" | cut -d' ' -f"$n")"
    case "$outcome" in
      capacity) echo "Error: 500-InternalError, Out of host capacity." ; exit 1 ;;
      other)    echo "Error: 400-QuotaExceeded, standard-a1-core-count exceeded" ; exit 1 ;;
      ok)       echo "Apply complete! Resources: 1 added, 0 changed, 0 destroyed." ;;
      *)        echo "stub: no outcome for apply #$n" ; exit 1 ;;
    esac ;;
  *) echo "unexpected terraform call: $*" >&2; exit 1 ;;
esac
EOF

# sleep is a no-op so the retry loop runs instantly.
printf '#!/usr/bin/env bash\nexit 0\n' >"$WORK/bin/sleep"
chmod +x "$WORK/bin/"*

FAILED=0
run_case() { # run_case <name> <want-exit> <want-applies> <want-text> <plan> <applies>
  local name="$1" want_rc="$2" want_applies="$3" want_text="$4"
  local state="$WORK/state-$name" out rc applies
  mkdir -p "$state"
  out="$(cd "$WORK/repo" && PATH="$WORK/bin:$PATH" OCI_CLI="$WORK/bin/oci" \
    STUB_STATE="$state" STUB_PLAN="$5" STUB_APPLIES="$6" \
    YES=1 INTERVAL=0 BLIND_EVERY=1 MAX_HOURS=1 \
    timeout 60 bash scripts/a1-wait-and-apply.sh 2>&1)"
  rc=$?
  applies="$(cat "$state/applies" 2>/dev/null || echo 0)"
  if [ "$rc" -eq "$want_rc" ] && [ "$applies" -eq "$want_applies" ] \
    && printf '%s\n' "$out" | grep -q -- "$want_text"; then
    printf 'PASS  %s (exit %s, %s applies)\n' "$name" "$rc" "$applies"
  else
    printf 'FAIL  %s: exit %s (want %s), applies %s (want %s), text "%s" %s\n' \
      "$name" "$rc" "$want_rc" "$applies" "$want_applies" "$want_text" \
      "$(printf '%s\n' "$out" | grep -q -- "$want_text" && echo found || echo missing)"
    printf '%s\n' "$out" | sed 's/^/      | /' | tail -12
    FAILED=$((FAILED + 1))
  fi
}

ADD="Plan: 1 to add, 0 to change, 0 to destroy."
run_case stops-on-other-error 1 2 "apply failed for a reason other than capacity" "$ADD" "capacity other"
run_case refuses-non-additive 1 0 "not purely additive" "Plan: 1 to add, 1 to change, 0 to destroy." ""
run_case retries-then-succeeds 0 2 "SUCCESS: node created" "$ADD" "capacity ok"
run_case no-changes-exits 0 0 "nothing to do" "No changes. Your infrastructure matches the configuration." ""

[ "$FAILED" -eq 0 ] && echo "all cases passed" || { echo "$FAILED case(s) failed"; exit 1; }
