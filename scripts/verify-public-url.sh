#!/usr/bin/env bash
# Check the public URL from outside, the way a visitor reaches it (demo #89,
# ADR 0020). One function per check, a PASS/FAIL line each, and a non-zero
# exit if anything failed. Run it from the laptop after each cutover step.
#
# Usage:  scripts/verify-public-url.sh --staging|--production [options]
#
#   --staging       accept the Let's Encrypt STAGING certificate (not trusted
#                   by browsers; the TLS chain is not verified)
#   --production    require a trusted production certificate (the chain must
#                   verify with the system trust store)
#   --hsts          also check the HSTS header. Without it that check is SKIPPED
#                   (HSTS is not enabled until demo #90).
#   --cutover       also check that no LoadBalancer Service remains for the app
#                   (needs kubectl and the tunnel from scripts/oke-tunnel.sh)
#   --code CODE     an existing short code to test the redirect with, when no
#                   token is available to create one
#   --no-burst      skip the rate-limit burst (it trips the limit for a few
#                   seconds, so run it last; it is last here)
#   --burst-requests N   size of the burst (default 600, sent in parallel)
#   --host HOST     default: $VERIFY_HOST, else demo.sandeeprn.in
#
# Env:    LINK_TOKEN     a valid link-creation token (ADR 0020). Read from the
#                        environment only; never printed, never put in argv
#                        (it is passed to curl through stdin), never stored.
#         HSTS_MAX_AGE   expected max-age in seconds (default 15552000, 180 days)
#         RESOLVER       public DNS resolver to ask (default 1.1.1.1)
#         KUBECONFIG     for --cutover (default ~/.kube/oke-demo.kubeconfig)
# Needs:  bash, curl (7.66+ for --parallel), openssl, nslookup or dig;
#         kubectl for --cutover.
#
# Checks that create things: the valid-token check creates ONE link to
# https://example.com/... (recorded as created by the token's name). The burst
# sends many cheap GET /healthz requests and expects at least one 429. The
# limit is shared by all clients (demo #97), so do not run this while the
# external probe or a load test depends on the site.
#
# Output masks IPv4 addresses. Exit codes: 0 all checks passed (skips are
# listed), 1 at least one failed, 2 bad usage.
set -uo pipefail

HOST="${VERIFY_HOST:-demo.sandeeprn.in}"
HSTS_MAX_AGE="${HSTS_MAX_AGE:-15552000}"
RESOLVER="${RESOLVER:-1.1.1.1}"
BURST_REQUESTS=600
BURST_PARALLEL=150
MODE="" DO_HSTS=0 DO_CUTOVER=0 DO_BURST=1 CODE=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
usage() { sed -n '2,/^set -uo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --staging|--production) [ -z "$MODE" ] || die "give only one of --staging, --production"; MODE="${1#--}" ;;
    --hsts) DO_HSTS=1 ;;
    --cutover) DO_CUTOVER=1 ;;
    --no-burst) DO_BURST=0 ;;
    --code) [ $# -ge 2 ] || die "--code needs a value"; CODE="$2"; shift ;;
    --host) [ $# -ge 2 ] || die "--host needs a value"; HOST="$2"; shift ;;
    --burst-requests) [ $# -ge 2 ] || die "--burst-requests needs a value"; BURST_REQUESTS="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done
# No default: the certificate expectation must be a deliberate choice.
[ -n "$MODE" ] || die "give --staging or --production (try --help)"
case "$BURST_REQUESTS" in ''|*[!0-9]*) die "--burst-requests must be a number" ;; esac
case "$HOST" in *[!A-Za-z0-9.-]*|'') die "bad host: $HOST" ;; esac
for bin in curl openssl; do command -v "$bin" >/dev/null 2>&1 || die "$bin not found on PATH"; done

# A token that could break out of the curl config line is refused, not escaped.
TOKEN="${LINK_TOKEN:-}"
case "$TOKEN" in *\"*|*\\*|*$'\n'*|*$'\r'*) die "LINK_TOKEN contains characters that are not allowed" ;; esac

TMP=$(mktemp -d) || die "cannot create a temp dir"
trap 'rm -rf "$TMP"' EXIT

# -k only in staging: its chain is untrusted by design, and the certificate is
# judged separately in check_certificate. Production never skips verification.
CURL=(curl -sS --max-time 20)
[ "$MODE" = staging ] && CURL+=(-k)
# Windows' Schannel fails when it cannot reach the revocation server.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) CURL+=(--ssl-no-revoke) ;; esac

mask() { sed -E 's/[0-9]{1,3}(\.[0-9]{1,3}){3}/x.x.x.x/g'; }

PASS=0 FAIL=0 SKIP=0
SKIPPED=()
# Each check function returns 0 or 1 and sets DETAIL (one line, shown masked).
run_check() {
  local name="$1" fn="$2"
  DETAIL=""
  if "$fn"; then
    PASS=$((PASS + 1)); printf 'PASS  %s%s\n' "$name" "${DETAIL:+  ($(printf '%s' "$DETAIL" | mask))}"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL  %s%s\n' "$name" "${DETAIL:+  ($(printf '%s' "$DETAIL" | mask))}"
  fi
}
skip_check() {
  SKIP=$((SKIP + 1)); SKIPPED+=("$1")
  printf 'SKIP  %s  (%s)\n' "$1" "$2"
}

# A request made with the token, which goes through stdin so it never shows in
# the process list. $1 is the token ("" = none); the rest are curl arguments.
curl_with_token() {
  local tok="$1"; shift
  if [ -n "$tok" ]; then
    printf 'header = "Authorization: Bearer %s"\n' "$tok" | "${CURL[@]}" -K - "$@"
  else
    "${CURL[@]}" "$@"
  fi
}

is_private() { grep -qE '^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' <<<"$1"; }

resolve_a() {
  if command -v dig >/dev/null 2>&1; then
    dig +short A "$HOST" "@$RESOLVER" 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  elif command -v nslookup >/dev/null 2>&1; then
    # The first address nslookup prints is the resolver's own: keep only those
    # after the "Name:" line.
    nslookup "$HOST" "$RESOLVER" 2>/dev/null | tr -d '\r' | sed -n '/^Name:/,$p' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}'
  else
    return 2
  fi
}

check_dns() {
  local addrs a n=0
  addrs=$(resolve_a); local rc=$?
  [ "$rc" -ne 2 ] || { DETAIL="neither dig nor nslookup is installed"; return 1; }
  [ -n "$addrs" ] || { DETAIL="$HOST does not resolve"; return 1; }
  for a in $addrs; do
    n=$((n + 1))
    # The NLB reports its private IP too; it must never reach public DNS
    # (found live in demo #88).
    if is_private "$a"; then DETAIL="a private address is published: $a"; return 1; fi
  done
  DETAIL="$n public A record(s)"
}

check_not_proxied() {
  # Cloudflare's proxy would end TLS at Cloudflare, not at our certificate.
  local h
  h=$("${CURL[@]}" -D - -o /dev/null "https://$HOST/healthz") || { DETAIL="HTTPS request failed"; return 1; }
  if grep -qiE '^(cf-ray:|server: *cloudflare)' <<<"$h"; then DETAIL="the response came through Cloudflare's proxy"; return 1; fi
}

check_certificate() {
  local cert issuer
  cert=$(printf '' | openssl s_client -connect "$HOST:443" -servername "$HOST" 2>/dev/null | openssl x509 2>/dev/null)
  [ -n "$cert" ] || { DETAIL="no certificate from $HOST:443"; return 1; }
  issuer=$(openssl x509 -noout -issuer <<<"$cert" | sed 's/^issuer= *//')
  openssl x509 -noout -checkhost "$HOST" <<<"$cert" | grep -q 'does match' || { DETAIL="certificate is not for $HOST"; return 1; }
  # Fail early enough to renew (cert-manager renews at 30 days left).
  openssl x509 -noout -checkend $((14 * 86400)) <<<"$cert" >/dev/null || { DETAIL="expires within 14 days"; return 1; }
  case "$MODE" in
    staging)
      grep -q '(STAGING)' <<<"$issuer" || { DETAIL="issuer is not Let's Encrypt STAGING: $issuer"; return 1; }
      DETAIL="staging issuer" ;;
    production)
      grep -q "Let's Encrypt" <<<"$issuer" || { DETAIL="issuer is not Let's Encrypt: $issuer"; return 1; }
      grep -q '(STAGING)' <<<"$issuer" && { DETAIL="a staging certificate is served"; return 1; }
      # Trusted: curl verifies the chain against the system store (no -k in production).
      "${CURL[@]}" -o /dev/null "https://$HOST/healthz" || { DETAIL="the certificate chain is not trusted"; return 1; }
      DETAIL="trusted production certificate" ;;
  esac
}

check_http_redirect() {
  local out code url
  out=$("${CURL[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "http://$HOST/verify-redirect?x=1") || { DETAIL="HTTP request failed"; return 1; }
  code=${out%% *}; url=${out#* }
  case "$code" in 301|308) ;; *) DETAIL="status $code, want a permanent redirect (301/308)"; return 1 ;; esac
  case "$url" in "https://$HOST/"*) ;; *) DETAIL="redirects to $url, not https://$HOST/"; return 1 ;; esac
  DETAIL="$code to https"
}

check_hsts() {
  local h v
  h=$("${CURL[@]}" -D - -o /dev/null "https://$HOST/healthz") || { DETAIL="HTTPS request failed"; return 1; }
  v=$(tr -d '\r' <<<"$h" | grep -i '^strict-transport-security:' | head -1 | sed 's/^[^:]*: *//')
  [ -n "$v" ] || { DETAIL="no Strict-Transport-Security header"; return 1; }
  grep -qE "(^|;) *max-age=${HSTS_MAX_AGE}( *;|$)" <<<"$v" || { DETAIL="max-age is not ${HSTS_MAX_AGE}: $v"; return 1; }
  # Subdomains and the preload list cannot be withdrawn early (ADR 0020).
  if grep -qiE 'includeSubDomains|preload' <<<"$v"; then DETAIL="must not have includeSubDomains or preload: $v"; return 1; fi
  DETAIL="max-age=${HSTS_MAX_AGE}"
}

# $1 token ("" = none); sets STATUS and writes the body to $TMP/body.
post_link() {
  STATUS=$(curl_with_token "$1" -o "$TMP/body" -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' \
    --data "{\"url\":\"https://example.com/verify-$(date +%s)\"}" \
    "https://$HOST/api/links") || STATUS="000"
}

check_create_no_token() {
  post_link ""
  [ "$STATUS" = 401 ] || { DETAIL="status $STATUS, want 401"; return 1; }
}

check_create_wrong_token() {
  # A made-up value, not a secret.
  post_link "verify-wrong-token-0000000000000000"
  [ "$STATUS" = 401 ] || { DETAIL="status $STATUS, want 401"; return 1; }
}

CREATED_URL=""
check_create_valid_token() {
  [ -n "$TOKEN" ] || { DETAIL="LINK_TOKEN is not set"; return 1; }
  post_link "$TOKEN"
  [ "$STATUS" = 201 ] || { DETAIL="status $STATUS, want 201"; return 1; }
  CODE=$(sed -nE 's/.*"code" *: *"([^"]+)".*/\1/p' "$TMP/body" | head -1)
  CREATED_URL=$(sed -nE 's/.*"url" *: *"([^"]+)".*/\1/p' "$TMP/body" | head -1)
  [ -n "$CODE" ] || { DETAIL="201 but no code in the response"; return 1; }
  DETAIL="created code $CODE"
}

check_redirect_no_token() {
  local out code loc
  [ -n "$CODE" ] || { DETAIL="no short code to test (needs LINK_TOKEN, or --code)"; return 1; }
  # No Authorization header: redirects are public (ADR 0020).
  out=$("${CURL[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "https://$HOST/$CODE") || { DETAIL="request failed"; return 1; }
  code=${out%% *}; loc=${out#* }
  [ "$code" = 302 ] || { DETAIL="status $code, want 302"; return 1; }
  if [ -n "$CREATED_URL" ] && [ "$loc" != "$CREATED_URL" ]; then DETAIL="redirects to the wrong target"; return 1; fi
  DETAIL="302 with no token"
}

check_burst() {
  local cfg="$TMP/burst.cfg" i counts n429 n200
  : >"$cfg"
  for ((i = 1; i <= BURST_REQUESTS; i++)); do
    printf 'url = "https://%s/healthz?verify=%s"\noutput = "/dev/null"\n' "$HOST" "$i" >>"$cfg"
  done
  # One curl process with many parallel transfers: separate curl processes
  # started from a shell are too slow to trip the limit (demo #88).
  counts=$("${CURL[@]}" --parallel --parallel-immediate --parallel-max "$BURST_PARALLEL" \
    -w '%{http_code}\n' -K "$cfg" 2>/dev/null | sort | uniq -c | tr -s ' ' | tr '\n' ';')
  n429=$(grep -oE '[0-9]+ 429' <<<"$counts" | cut -d' ' -f1)
  n200=$(grep -oE '[0-9]+ 200' <<<"$counts" | cut -d' ' -f1)
  n429=${n429:-0}; n200=${n200:-0}
  DETAIL="${BURST_REQUESTS} requests: ${n429} x 429, ${n200} x 200"
  [ "$n429" -gt 0 ] || { DETAIL="no 429 in $DETAIL"; return 1; }
}

check_recovers() {
  # Buckets refill within seconds; a limit that stays on would take the site down.
  local i s
  for i in 1 2 3 4; do
    sleep 5
    s=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "https://$HOST/healthz") || s=000
    [ "$s" = 200 ] && { DETAIL="200 after ~$((i * 5))s"; return 0; }
  done
  DETAIL="still $s 20s after the burst"; return 1
}

check_no_app_loadbalancer() {
  local kc="${KUBECONFIG:-$HOME/.kube/oke-demo.kubeconfig}" types
  command -v kubectl >/dev/null 2>&1 || { DETAIL="kubectl not found"; return 1; }
  types=$(kubectl --kubeconfig "$kc" --request-timeout=60s -n link-shortener get svc \
    -o jsonpath='{range .items[*]}{.spec.type}{"\n"}{end}' 2>&1) || { DETAIL="cannot read Services (is the tunnel up?)"; return 1; }
  if grep -qx LoadBalancer <<<"$types"; then DETAIL="a LoadBalancer Service still exists in link-shortener"; return 1; fi
}

printf 'Verifying https://%s (%s certificate)\n' "$HOST" "$MODE"
run_check "DNS: public A records only"                    check_dns
run_check "DNS: not proxied by Cloudflare"                check_not_proxied
run_check "Certificate valid for the host ($MODE)"        check_certificate
run_check "HTTP redirects permanently to HTTPS"           check_http_redirect
if [ "$DO_HSTS" = 1 ]; then
  run_check "HSTS header, no subdomains or preload"       check_hsts
else
  skip_check "HSTS header, no subdomains or preload" "not enabled yet; pass --hsts"
fi
run_check "Create without a token gets 401"               check_create_no_token
run_check "Create with a wrong token gets 401"            check_create_wrong_token
run_check "Create with a valid token gets 201"            check_create_valid_token
run_check "Redirect works with no token"                  check_redirect_no_token
if [ "$DO_CUTOVER" = 1 ]; then
  run_check "No LoadBalancer Service for the app"         check_no_app_loadbalancer
else
  skip_check "No LoadBalancer Service for the app" "cutover step 2 only; pass --cutover"
fi
# Last: it trips the shared rate limit for a few seconds.
if [ "$DO_BURST" = 1 ]; then
  run_check "A burst gets 429"                            check_burst
  run_check "The site recovers after the burst"           check_recovers
else
  skip_check "A burst gets 429" "--no-burst"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
