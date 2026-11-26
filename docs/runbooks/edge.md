# Runbook: the edge (certificate, Cloudflare tokens, link-creation tokens)

ADR 0020, ADR 0022. Covers everything between the internet and the backend
Service for `https://demo.sandeeprn.in`, which the single-node k3s cluster
serves since 2026-11-12: how to debug it, renew its certificate, rotate a
Cloudflare token, and add or revoke a link-creation token. The design is in
[architecture.md](../architecture.md#6-edge).

All changes are pull requests to the gitops repo (ArgoCD syncs about 3 minutes
after a merge). Read-only checks use `kubectl` through the tunnel; do not
`kubectl apply` anything by hand.

## Not yet run on k3s in this form

These commands come from the OKE version of this page, with the k3s
kubeconfig and namespace (the Helm job check comes from the comment in the
gitops repo's `argocd/clusters/k3s/apps/traefik-config.yaml`). Run each once
on k3s, check the output matches what this page says, and remove it from this
list:

- `$K -n external-dns logs deploy/external-dns --tail=50` (step A) and `--tail=20` (token rotation)
- `$K -n kube-system get pods -o wide` and `$K -n kube-system logs <traefik-pod> --tail=50` (step B)
- `$K -n kube-system get pods -l helmcharts.helm.cattle.io/chart=traefik` (step B)
- `$K -n cert-manager logs deploy/cert-manager --tail=100` (certificate)
- `KUBECONFIG=$HOME/.kube/k3s.kubeconfig cmctl renew demo-sandeeprn-in-tls -n link-shortener` (certificate, token rotation)
- `$K -n external-dns delete pod -l app.kubernetes.io/name=external-dns` (token rotation)
- the three layer checks in step 5 of "Add a link-creation token" (ArgoCD revision, Secret keys, files in each backend pod)

## Facts

| | |
|---|---|
| Hostname | `demo.sandeeprn.in`, A record kept by k3s's external-dns (owner id `oci-demo-k3s`; DNS only, not proxied), plus a TXT owner record `edns-...` |
| Entry | No load balancer (ADR 0022). The node's public IP, then k3s's bundled Traefik through ServiceLB: one Traefik pod, namespace `kube-system`, Service `traefik` with `externalTrafficPolicy: Local`, so Traefik sees real client IPs. Configured from `edge/traefik-k3s` in the gitops repo (Application `traefik-config`) |
| Address in DNS | Traefik writes the node's public IP into the Ingress status from the SealedSecret `traefik-public-ip`; external-dns publishes that address |
| Certificate | cert-manager `Certificate` made from the Ingress `backend` (namespace `link-shortener`), Secret `demo-sandeeprn-in-tls`, issuer `letsencrypt-production`; renews itself 30 days before expiry |
| HSTS | `max-age=15552000` (180 days) on this host only. Browsers that saw it refuse plain HTTP **and refuse any bad certificate with no click-through** |
| Cloudflare tokens | Two, one per component: `cert-manager-oke` (cert-manager) and `external-dns oci-demo` (external-dns); each Zone:DNS:Edit + Zone:Zone:Read on `sandeeprn.in` only. The names are from the OKE days: the same two sealed tokens (`platform/cert-manager-issuers` and `platform/external-dns` in the gitops repo) serve k3s now. Values live in the owner's password manager |
| Link tokens | Keys of one SealedSecret, `link-tokens` (namespace `link-shortener`), mounted as one file per token. Current names: `owner`, `k6` |
| Tools | `kubectl` via `scripts/k3s-tunnel.sh` (see [k3s-access](k3s-access.md) and [access](access.md)), `kubeseal`, `openssl`, `gh`; optional `cmctl` |

```bash
# After scripts/k3s-tunnel.sh is running in another terminal:
K="kubectl --kubeconfig $HOME/.kube/k3s.kubeconfig"     # the k3s kubeconfig, not kubectl's default context
```

Every command here names the k3s kubeconfig, so it never depends on kubectl's
current context (which may be unset or point at another cluster).

## Check the whole edge in one go

Run from the demo repo checkout, as in step 8 of
[k3s-bootstrap](k3s-bootstrap.md). Without a token, give the script an
existing short code to test the redirect with (`seYOHlz` is the landing page's
example link); the line "Create with a valid token gets 201" then FAILS with
"LINK_TOKEN is not set", and everything else must pass:

```bash
scripts/verify-public-url.sh --production --code seYOHlz
```

With the owner token (it creates one real link). The token is read with a
hidden prompt and never printed:

```bash
read -rsp "link token (your owner token): " OWNER_LINK_TOKEN; echo; echo "length: ${#OWNER_LINK_TOKEN} (0 = nothing was read)"
LINK_TOKEN="$OWNER_LINK_TOKEN" scripts/verify-public-url.sh --production --no-burst
unset OWNER_LINK_TOKEN
# 9 passed, 0 failed, 2 skipped
```

It checks DNS, the redirect to HTTPS, the trusted certificate chain, HSTS, 401
without a token, a link created with `LINK_TOKEN` and followed, and the rate
limit. The HSTS check is on by default (`--no-hsts` skips it). It prints no addresses. Do not paste the token into a command line (the
script reads the environment). The rate-limit check sends a burst of 600
requests, so your own address gets 429 for a few seconds; do not run it during
a load test.

## Debug: the site does not answer or the certificate is wrong

Go from the outside in and stop at the first broken layer.

| Step | Check | Healthy | If not |
|---|---|---|---|
| 1. DNS | `nslookup demo.sandeeprn.in 1.1.1.1` | One public A record | No record or a private (10.x) address: look at external-dns logs, step A |
| 2. TCP | `curl -sv --connect-timeout 5 https://demo.sandeeprn.in/healthz -o /dev/null` | Connects, TLS handshake completes | Connect timeout: the node's security list or Traefik, step B |
| 3. Certificate | `echo \| openssl s_client -connect demo.sandeeprn.in:443 -servername demo.sandeeprn.in 2>/dev/null \| openssl x509 -noout -issuer -enddate` | Issuer is Let's Encrypt (not "TRAEFIK DEFAULT CERT"), `notAfter` more than 30 days away | Step C |
| 4. Routing | `curl -s -o /dev/null -w '%{http_code}\n' https://demo.sandeeprn.in/healthz` | `200` | `404` from Traefik: the Ingress is missing. `429`: rate limit (below). `502/503`: backend pods, see the [SLO runbook](slo-redirect-availability.md) |

Rate limit: per client on k3s. Traefik sees the real client address
(`externalTrafficPolicy: Local`, ADR 0022), and each address gets 20 requests
a second with a burst of 40, so a busy loop locks out only that address. A
429 is not an outage. Proven: a burst of 600 requests from one client got
282 x 429. Also proven, on 2026-11-21: while a laptop got 1410 x 429 over a
60 second flood, a phone on mobile data still got the normal page on every
reload ([evidence](../evidence/k3s-live-checks-2026-11-21.md); the phone's
result is an observation, Traefik's counters cannot be split by client). (On
OKE the limit was a shared flood guard of 5 requests a second with a burst of
10, because the load balancer hid client addresses, #97.)

**A. external-dns** (record missing, stale or wrong):

```bash
$K -n external-dns logs deploy/external-dns --since=10m | grep -E 'action=' | sed -E 's/ zone=[0-9a-f]+//'
$K -n external-dns logs deploy/external-dns --tail=50
```

The first command shows only `CREATE`/`UPDATE`/`DELETE` lines, with the
Cloudflare zone id removed; nothing printed means no change was needed. The
second shows everything, including Cloudflare errors (`403`/`401` means the
token: see "Rotate a Cloudflare token"). Raw logs contain the zone id and IP
addresses: never paste them anywhere public.

external-dns publishes the address in the Ingress status, which Traefik
writes from the SealedSecret `traefik-public-ip`; private addresses are
filtered on purpose. To check that the Ingress address is the node's public
IP without printing either, use the "Traefik edge checks" in step 4 of
[k3s-bootstrap](k3s-bootstrap.md). Never change `txtOwnerId` or `txtPrefix`:
the existing records would stop being owned and would neither update nor
delete.

**B. The node and Traefik**:

```bash
$K -n kube-system get svc traefik -o jsonpath='{.spec.externalTrafficPolicy}{"\n"}'   # Local
$K -n kube-system get pods -o wide              # find the Traefik pod: Running, no restarts piling up
$K -n kube-system logs <traefik-pod> --tail=50
$K -n kube-system get pods -l helmcharts.helm.cattle.io/chart=traefik   # k3s's Helm job for Traefik
```

Traefik is installed by k3s itself (HelmChart `traefik` in `kube-system`), and
ArgoCD only applies the `HelmChartConfig` from `edge/traefik-k3s`. The
`traefik-config` Application shows Synced and Healthy as soon as that object
is applied, even if k3s's Helm job rejected the values: the Helm job's pod
shows whether it did.

The Traefik Service's own status shows the node's private IP; only the
Ingress status carries the public one. If the connection times out, check the
node's security list: `terraform plan` in `terraform/k3s` must show no changes
(`web_allowed_cidr` may have been narrowed). More causes and fixes are in the
"When something fails" table of [k3s-bootstrap](k3s-bootstrap.md).

**C. Certificate**: see the next section.

## Renew or debug the certificate

cert-manager renews by itself 30 days before expiry. Normally nothing to do.
k3s ordered its own production certificate on 2026-11-12 (valid 90 days). Do
not take the renewal date from any document: read it from the Certificate's
status (`Renewal Time` in `describe`).

```bash
$K get certificate,order -A            # certificate READY True, order valid
$K -n link-shortener describe certificate,certificaterequest,order,challenge
```

Reading the output:

| Sign | Meaning | Action |
|---|---|---|
| `Certificate` `READY=True`, `Renewal Time` in the future | Healthy | None |
| `READY=False`, an `Order` stuck `pending`, a `Challenge` in `pending` | DNS-01 not completing | `$K -n cert-manager logs deploy/cert-manager --tail=100`; the usual cause is the cert-manager Cloudflare token (expired, revoked, wrong scope) |
| Challenge `presented` for a long time | The TXT record `_acme-challenge` was created but Let's Encrypt cannot see it | Check Cloudflare for the TXT record; wait for DNS propagation (a few minutes) |
| `too many certificates already issued` | Let's Encrypt rate limit (5 identical certificates a week) | Wait; the current certificate keeps serving until it expires. Never loop on the production issuer |

**Force a renewal** (for example after a token fix, so you do not wait for the
next retry):

```bash
KUBECONFIG=$HOME/.kube/k3s.kubeconfig cmctl renew demo-sandeeprn-in-tls -n link-shortener
```

`cmctl` does not use `$K`; without `KUBECONFIG` it would act on kubectl's
current context, which is not necessarily this cluster.

`cmctl renew` issues a new certificate and keeps serving the old one until the
new one is ready. **Do not delete the TLS Secret instead.** Traefik would fall
back to its default self-signed certificate until the new one arrives, and
with HSTS every browser that has seen the site would refuse to load it for
that time.

**Experiment safely:** to test issuance changes, use the `letsencrypt-staging`
issuer on a throwaway host, never on `demo.sandeeprn.in`. Staging has far
higher limits but its certificates are not trusted. The gitops CI rejects any
issuer but `letsencrypt-production` on an Ingress, so such a test needs that
rule changed first.

After any change, run the verify script above.

## Certificate expiring soon

Alerts: `CertificateExpiringSoon` (warning under 14 days left, critical under 7),
`CertificateNotReady` (warning) and `CertManagerMetricsMissing` (warning). The
rules are in the gitops repo, `monitoring/k3s/platform-rules.yaml` (issue #140).
They cover every certificate cert-manager manages, today `demo-sandeeprn-in-tls`
(namespace `link-shortener`) and `ask-sandeeprn-in-tls` (namespace
`oncall-assistant`); the alert's `name` and `namespace` labels say which.

What they mean. cert-manager renews a 90-day certificate 30 days before it
expires, so under 14 days left means renewal has been failing for more than two
weeks. It is not an outage yet: the current certificate keeps serving until it
expires. Under 7 days (critical) the browser warning is close, and with HSTS
there is no click-through ([Facts](#facts)). `CertManagerMetricsMissing` means
Prometheus reads no cert-manager metrics, so the other two alerts cannot fire:
treat it as a broken alarm, not as a healthy certificate.

Check first, with the alert's `namespace` and `name`:

```bash
$K get certificate -A
$K -n <namespace> describe certificate <name>      # Ready, Not After, Renewal Time, the last event
$K -n <namespace> get certificaterequest,order,challenge
$K -n cert-manager logs deploy/cert-manager --tail=100
```

Then follow [Renew or debug the certificate](#renew-or-debug-the-certificate)
(the table of signs and the forced renewal). Do not delete the TLS Secret to
force it. For `CertManagerMetricsMissing`: check that the `cert-manager`
Service answers on port 9402 and that the ServiceMonitor for it exists in the
`monitoring` namespace (it comes from `monitoring/k3s` in the gitops repo).

Not yet run on k3s: the alerts were added with demo #140 and have not fired on
the real cluster; the commands above are the ones from "Renew or debug", whose
own status is in "Not yet run on k3s in this form".

## Traefik server errors

Alerts: `TraefikServerErrorsHigh` (warning: more than 5% of HTTPS requests
answered with a 5xx for 10 minutes, with at least 20 requests in that window)
and `TraefikMetricsMissing` (warning: Prometheus cannot scrape Traefik). Rules:
the gitops repo, `monitoring/k3s/platform-rules.yaml`.

What they mean. The first counts every service behind Traefik, so it also sees
errors the apps' own metrics cannot: Traefik answering 502, 503 or 504 itself
(no ready backend, a refused connection). The link shortener's redirect SLO
alerts page for that service's own 5xx, so both can fire for one cause. The
assistant's deliberate 503s (`kind: unavailable`: a timeout, a provider error or
a database that is down) count here too. Blind spot: with fewer than 20 requests
in 10 minutes this alert stays quiet, and a total outage that small is caught by
the probe alerts (`RedirectProbeNoAnswer`), not by this one.

Check first:

```bash
# Which service and which status? Prometheus has no public UI: port-forward it.
$K -n monitoring port-forward svc/kps-prometheus 9090 &      # then http://localhost:9090
#   sum by (exported_service, code) (rate(traefik_service_requests_total{code=~"5.."}[10m]))
$K -n <namespace of that service> get pods
$K -n <namespace of that service> logs deploy/<name> --tail=100
$K -n kube-system logs deploy/traefik --tail=100
```

A 5xx from one service means look at that service (the `exported_service` label
reads `<namespace>-<service>-<port name>@kubernetes`, for example
`oncall-assistant-app-http@kubernetes`). 502 or 503 on every service
at once means look at Traefik itself and the node. If `TraefikMetricsMissing`
fires, the numbers above do not exist: check that the `traefik` pod runs and
that the `traefik-metrics` Service and its ServiceMonitor exist
(`edge/traefik-k3s` in the gitops repo). Stop the port-forward when done.

Not yet run on k3s: as above, the alerts have not fired on the real cluster.

## Rotate a Cloudflare token

Do one component at a time, so a mistake affects one.

1. In Cloudflare (My Profile, API Tokens), create a **new** token with
   Zone:DNS:Edit and Zone:Zone:Read, limited to the `sandeeprn.in` zone. Name
   it for the component and date. Save the value in the password manager. Leave
   the old token active for now.
2. In a gitops repo worktree on a new branch, seal it (hidden prompt, nothing
   in shell history). The script writes to `platform/`, which both clusters
   read, and seals with `argocd/clusters/k3s/sealed-secrets-cert.pem` (one
   set of keys for both clusters, ADR 0022):
   ```bash
   scripts/seal-cloudflare-token.sh cert-manager     # or: external-dns
   ```
3. Open a PR (`Closes Sandeep-RN/oci-k8s-gitops-demo#N` for the task issue),
   wait for `validate`, merge. ArgoCD syncs the new SealedSecret and the
   controller updates the Secret.
4. **external-dns only:** it reads the token as an environment variable, which
   a running pod does not refresh. Restart it by deleting its pod (not
   `rollout restart`; see the house rules in [access](access.md)):
   `$K -n external-dns delete pod -l app.kubernetes.io/name=external-dns`.
   The Deployment starts a new pod with the new token. cert-manager reads
   its Secret on each challenge and needs no restart.
5. Prove the new token works:
   - cert-manager: `KUBECONFIG=$HOME/.kube/k3s.kubeconfig cmctl renew demo-sandeeprn-in-tls -n link-shortener`, then
     watch the `Certificate` become `READY=True`.
   - external-dns: `$K -n external-dns logs deploy/external-dns --tail=20` shows
     no Cloudflare errors after the restart (it re-checks every minute).
6. Only now **delete the old token** in Cloudflare. If something broke, the old
   one is still there to go back to.

## Add a link-creation token

> Followed live on OKE on 2026-10-31. Since gitops PR #66 (issue #171),
> `scripts/seal-link-tokens.sh` writes to `apps/link-shortener/overlays/k3s`
> with the k3s certificate; the procedure has not been run on k3s yet.

For a new tester or job. Tokens are named; the name is stored with each link
(`created_by`) and logged, the value never is.

1. Pick a name (letters, digits, `.`, `_`, `-`; at most 63 characters), e.g.
   `reviewer-alex`.
2. Generate a value and put it straight into the password manager:
   `openssl rand -hex 32` (at least 32 characters; shorter values are ignored
   by the app).
3. In the gitops repo, **branch from the latest `main` first**, then seal:
   ```bash
   git fetch origin && git switch -c token-reviewer-alex origin/main
   scripts/seal-link-tokens.sh reviewer-alex
   ```
   Paste the value at the hidden prompt. The script adds that one key and keeps
   the others (`--merge-into`). It writes into whatever is checked out: run on
   a stale local `main`, it merges into an old copy of the file, and the push
   is rejected (`main` takes PRs only).
4. Review the diff: only `link-tokens-sealedsecret.yaml` changes, and only a
   new key appears under `encryptedData`. Open a PR, wait for `validate`,
   merge.
5. Wait until the change reaches the pods; no restart is needed. It takes
   ArgoCD's poll (up to about 3 minutes), the Secret update, then the
   kubelet's refresh of the mounted files. Measured on 2026-10-31: under 4
   minutes from merge to both pods, for an add and for a revoke. Check each
   layer instead of guessing (prints names only, never values):
   ```bash
   $K -n argocd get app link-shortener -o jsonpath='{.status.sync.revision}{"\n"}'   # = the merge commit
   $K -n link-shortener get secret link-tokens -o go-template='{{range $k,$v := .data}}{{$k}} {{end}}{{"\n"}}'
   for p in $($K -n link-shortener get pods -l app.kubernetes.io/name=backend -o name); do
     $K -n link-shortener exec "${p#pod/}" -- ls //etc/link-shortener/tokens; done
   ```
   The double slash stops Git Bash from rewriting `/etc/...` into a Windows
   path; Linux treats it as a single slash.
6. Prove it in a **new terminal**, reading the value under a prompt that names
   the token, so another token's value cannot sit in the variable by mistake:
   ```bash
   read -r -s -p 'reviewer-alex value: ' TOKEN; echo
   echo ${#TOKEN}     # 64. 0 means empty, and an empty token also gives 401
   printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - \
     -o /dev/null -w '%{http_code}\n' -X POST https://demo.sandeeprn.in/api/links \
     -H 'content-type: application/json' -d '{"url":"https://example.com/runbook-check"}'
   ```
   Expect `201`. (`curl -K -` keeps the token off the command line and out of
   the process list.) **A `201` only says that some valid token was used.**
   Confirm it was this one: the newest link's `created_by` must be the new
   name (query below, with `ORDER BY created_at DESC LIMIT 1`). On 2026-10-31
   a test passed with `201` while the variable held the `owner` value; only
   `created_by` showed it.
7. Give the value to its user over a private channel, never in a ticket or chat
   that is public.

## Revoke a link-creation token

> Followed live on OKE on 2026-10-31. The hand edit in step 1 and
> `scripts/seal-link-tokens.sh` now use the same overlay again,
> `overlays/k3s` (gitops PR #66, issue #171). Not run on k3s yet.

1. On a new branch from the latest `origin/main` (as in step 3 above), open
   `apps/link-shortener/overlays/k3s/link-tokens-sealedsecret.yaml` and delete
   that token's line under `spec.encryptedData`. Do not touch the other lines.
2. Open a PR, wait for `validate`, merge. Check each layer as in step 5 above
   until no pod lists the token.
3. Prove it: the same `curl` as above with the revoked value (check that
   `${#TOKEN}` is not 0) now returns `401`, and no new link carries its
   `created_by`. A remaining token still returns `201`.
4. Delete the value from the password manager.

Links the token already created keep working (redirects are public). Their
`created_by` still names it, which is how you find and, if needed, remove
everything a leaked token made:
`SELECT code, url, created_at FROM links WHERE created_by = 'NAME'` in database
`linkshortener`, run with the superuser through `postgres-0` as in the
[backup runbook](postgres-backup-restore.md).

**If a token leaks:** revoke it first, then look at what it created. Rotating
is the same as revoking and adding under a new name.

## What k3s shares with the retired OKE target: do not touch

The OKE target served the site until 2026-11-12 and was destroyed on 2026-11-15
(issue #13). k3s took over the hostname and uses several things OKE used.
Removing any of them takes the live site down or breaks it later:

- **Keep both Cloudflare tokens** (`cert-manager-oke` and
  `external-dns oci-demo`). k3s uses the same two sealed tokens
  (`platform/cert-manager-issuers` and `platform/external-dns` in the gitops
  repo). Also keep the Discord webhook: k3s's Alertmanager posts to the same
  channel.
- **Do not delete or edit the `demo` A record or its `edns-` TXT record** in
  Cloudflare. They belong to k3s now (owner id `oci-demo-k3s`). OKE's own
  records were already removed by OKE's external-dns after gitops PR
  [#59](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-gitops/pull/59).
- **Leave `PROBE_BASE_URL` as it is.** The external probe's secret already
  points at the hostname, which k3s serves.
- **Keep the Sealed Secrets key backup.** It is the k3s key (ADR 0022).

The teardown checklist was issue
[#13](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/13).
