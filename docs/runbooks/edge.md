# Runbook: the edge (certificate, Cloudflare tokens, link-creation tokens)

ADR 0020. Covers everything between the internet and the backend Service for
`https://demo.sandeeprn.in`: how to debug it, renew its certificate, rotate a
Cloudflare token, and add or revoke a link-creation token. The design is in
[architecture.md](../architecture.md#6-edge-built-on-oke).

All changes are pull requests to the gitops repo (ArgoCD syncs about 3 minutes
after a merge). Read-only checks use `kubectl` through the tunnel; do not
`kubectl apply` anything by hand.

## Facts

| | |
|---|---|
| Hostname | `demo.sandeeprn.in`, A record kept by external-dns (DNS only, not proxied), plus a TXT owner record `edns-...` |
| Entry | OCI Network Load Balancer (TCP passthrough) to Traefik, 2 replicas, namespace `traefik` |
| Certificate | cert-manager `Certificate` made from the Ingress `backend` (namespace `link-shortener`), Secret `demo-sandeeprn-in-tls`, issuer `letsencrypt-production`; renews itself 30 days before expiry |
| HSTS | `max-age=15552000` (180 days) on this host only. Browsers that saw it refuse plain HTTP **and refuse any bad certificate with no click-through** |
| Cloudflare tokens | Two, one per component: `cert-manager-oke` (cert-manager) and `external-dns oci-demo` (external-dns); each Zone:DNS:Edit + Zone:Zone:Read on `sandeeprn.in` only. Values live in the owner's password manager |
| Link tokens | Keys of one SealedSecret, `link-tokens` (namespace `link-shortener`), mounted as one file per token. Current names: `owner`, `k6` |
| Tools | `kubectl` via `scripts/oke-tunnel.sh` (see [access](access.md)), `kubeseal`, `openssl`, `gh`; optional `cmctl` |

```bash
# After scripts/oke-tunnel.sh is running in another terminal:
K="kubectl --kubeconfig $HOME/.kube/oke-demo.kubeconfig --request-timeout=60s"
```

The tunnel is slow; the timeout avoids false failures.

## Check the whole edge in one go

```bash
LINK_TOKEN=... scripts/verify-public-url.sh --production --hsts --cutover
```

Run it from the demo repo checkout. It checks DNS, the redirect to HTTPS, the
trusted certificate chain, HSTS, 401 without a token, a link created with
`LINK_TOKEN` and followed, the rate limit, and that no LoadBalancer Service is
left for the app. It prints no addresses. Take the token from the password
manager; do not paste it into a command line (the script reads the
environment). The rate-limit check sends a burst of 600 requests, so the site answers 429
for a few seconds; do not run it during a load test.

## Debug: the site does not answer or the certificate is wrong

Go from the outside in and stop at the first broken layer.

| Step | Check | Healthy | If not |
|---|---|---|---|
| 1. DNS | `nslookup demo.sandeeprn.in 1.1.1.1` | One public A record | No record or a private (10.x) address: look at external-dns logs, step A |
| 2. TCP | `curl -sv --connect-timeout 5 https://demo.sandeeprn.in/healthz -o /dev/null` | Connects, TLS handshake completes | Connect timeout: NLB or Traefik, step B |
| 3. Certificate | `echo \| openssl s_client -connect demo.sandeeprn.in:443 -servername demo.sandeeprn.in 2>/dev/null \| openssl x509 -noout -issuer -enddate` | Issuer is Let's Encrypt (not "TRAEFIK DEFAULT CERT"), `notAfter` more than 30 days away | Step C |
| 4. Routing | `curl -s -o /dev/null -w '%{http_code}\n' https://demo.sandeeprn.in/healthz` | `200` | `404` from Traefik: the Ingress is missing. `429`: rate limit (below). `502/503`: backend pods, see the [SLO runbook](slo-redirect-availability.md) |

Rate limit: it is shared by all clients (the NLB hides client addresses,
issue #97), 5 requests a second with a burst of 10. A busy loop on your own
laptop can lock everyone out for a few seconds. It is a 429, not an outage.

**A. external-dns** (record missing, stale or wrong):

```bash
$K -n external-dns logs deploy/external-dns --tail=50
```

Look for `CREATE`/`UPDATE`/`DELETE` lines for `demo.sandeeprn.in`, and for
Cloudflare errors (`403`/`401` means the token: see "Rotate a Cloudflare
token"). It publishes only the NLB's public address; private addresses are
filtered on purpose. Never change `txtOwnerId` or `txtPrefix`: the existing
records would stop being owned and would neither update nor delete.

**B. NLB and Traefik**:

```bash
$K -n traefik get pods,svc -o wide     # 2 pods Running, one per node; Service has an EXTERNAL-IP
$K -n traefik logs -l app.kubernetes.io/name=traefik --tail=50
```

A Service stuck at `<pending>` means the cloud controller could not create the
NLB (look at `$K -n traefik describe svc`). Do not set `is-preserve-source`: with
`externalTrafficPolicy: Cluster` it makes requests fail.

**C. Certificate**: see the next section.

## Renew or debug the certificate

cert-manager renews by itself 30 days before expiry. Normally nothing to do.
The first production certificate was issued 2026-10-31 (valid 90 days);
`Renewal Time` in `describe` shows when the next renewal is due.

```bash
$K -n link-shortener get certificate,certificaterequest,order,challenge
$K -n link-shortener describe certificate demo-sandeeprn-in-tls
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
cmctl renew demo-sandeeprn-in-tls -n link-shortener
```

`cmctl renew` issues a new certificate and keeps serving the old one until the
new one is ready. **Do not delete the TLS Secret instead.** Traefik would fall
back to its default self-signed certificate until the new one arrives, and
with HSTS every browser that has seen the site would refuse to load it for
that time.

**Experiment safely:** to test issuance changes, use the `letsencrypt-staging`
issuer on a throwaway host, never on `demo.sandeeprn.in`. Staging has far
higher limits but its certificates are not trusted.

After any change, run the verify script above.

## Rotate a Cloudflare token

Do one component at a time, so a mistake affects one.

1. In Cloudflare (My Profile, API Tokens), create a **new** token with
   Zone:DNS:Edit and Zone:Zone:Read, limited to the `sandeeprn.in` zone. Name
   it for the component and date. Save the value in the password manager. Leave
   the old token active for now.
2. In a gitops repo worktree on a new branch, seal it (hidden prompt, nothing
   in shell history):
   ```bash
   scripts/seal-cloudflare-token.sh cert-manager     # or: external-dns
   ```
3. Open a PR (`Closes Sandeep-RN/oci-k8s-gitops-demo#N` for the task issue),
   wait for `validate`, merge. ArgoCD syncs the new SealedSecret and the
   controller updates the Secret.
4. **external-dns only:** it reads the token as an environment variable, which
   a running pod does not refresh. Restart it:
   `$K -n external-dns rollout restart deploy/external-dns`. cert-manager reads
   its Secret on each challenge and needs no restart.
5. Prove the new token works:
   - cert-manager: `cmctl renew demo-sandeeprn-in-tls -n link-shortener`, then
     watch the `Certificate` become `READY=True`.
   - external-dns: `$K -n external-dns logs deploy/external-dns --tail=20` shows
     no Cloudflare errors after the restart (it re-checks every minute).
6. Only now **delete the old token** in Cloudflare. If something broke, the old
   one is still there to go back to.

## Add a link-creation token

For a new tester or job. Tokens are named; the name is stored with each link
(`created_by`) and logged, the value never is.

1. Pick a name (letters, digits, `.`, `_`, `-`; at most 63 characters), e.g.
   `reviewer-alex`.
2. Generate a value and put it straight into the password manager:
   `openssl rand -hex 32` (at least 32 characters; shorter values are ignored
   by the app).
3. In a gitops worktree on a new branch:
   ```bash
   scripts/seal-link-tokens.sh reviewer-alex
   ```
   Paste the value at the hidden prompt. The script adds that one key and keeps
   the others (`--merge-into`).
4. Review the diff: only `link-tokens-sealedsecret.yaml` changes, and only a
   new key appears under `encryptedData`. Open a PR, wait for `validate`,
   merge.
5. Wait for ArgoCD (up to about 3 minutes) plus the kubelet's refresh of the
   mounted Secret (about 1 minute). No restart is needed.
6. Prove it, with the value from the password manager:
   ```bash
   printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -K - \
     -o /dev/null -w '%{http_code}\n' -X POST https://demo.sandeeprn.in/api/links \
     -H 'content-type: application/json' -d '{"url":"https://example.com/runbook-check"}'
   ```
   Expect `201`. (`curl -K -` keeps the token off the command line and out of
   the process list.) Then confirm a wrong value gives `401`.
7. Give the value to its user over a private channel, never in a ticket or chat
   that is public.

## Revoke a link-creation token

1. In a gitops worktree on a new branch, open
   `apps/link-shortener/overlays/oke/link-tokens-sealedsecret.yaml` and delete
   that token's line under `spec.encryptedData`. Do not touch the other lines.
2. Open a PR, wait for `validate`, merge. Wait as in step 5 above.
3. Prove it: the same `curl` as above with the revoked value now returns `401`,
   and a remaining token still returns `201`.
4. Delete the value from the password manager.

Links the token already created keep working (redirects are public). Their
`created_by` still names it, which is how you find and, if needed, remove
everything a leaked token made:
`SELECT code, url, created_at FROM links WHERE created_by = 'NAME'` in database
`linkshortener`, run with the superuser through `postgres-0` as in the
[backup runbook](postgres-backup-restore.md).

**If a token leaks:** revoke it first, then look at what it created. Rotating
is the same as revoking and adding under a new name.

## OKE teardown (read before issue #13)

**Delete the Ingress before the cluster.** external-dns then removes
`demo.sandeeprn.in` and its TXT owner record. Easiest: delete the
`link-shortener` Application (or remove `ingress.yaml` from the overlay in a PR)
and confirm in Cloudflare that both records are gone.

If the cluster goes first, the A record points at a released address. Remove
**both** records by hand in Cloudflare: the A record `demo` and the TXT record
whose name starts with `edns-`. Leave the blog's records alone.

Afterwards, revoke the two Cloudflare tokens (unless k3s will take over the
hostname) and disable or repoint the external probe (`PROBE_BASE_URL`).
