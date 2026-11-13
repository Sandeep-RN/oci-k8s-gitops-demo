# Runbook: bring the demo up on k3s (bootstrap, data, DNS switch, rebuild)

ADR 0022 (the move), ADR 0006 (sealing keys), ADR 0007 (backups), ADR 0020 (edge).
Issues: #8 (first bootstrap), #57 (rebuild proof).

> **Status: steps 1 to 8 were run end to end on 2026-11-12 and 2026-11-13**
> (steps 1 to 6 on the afternoon of 2026-11-12, the DNS switch and public check
> at about 03:40 IST on 2026-11-13). `https://demo.sandeeprn.in` is served by
> k3s since then. Every command in steps 1 to 8 is written as it was run,
> except these three, which were rewritten from commands that did run and
> have **not been run in this exact form** (run them once and delete this
> note): the `jsonpath` check of `BACKUP_CLUSTER` on the source cluster's
> CronJob (step 6), and the two Prometheus queries through `get --raw`
> (alerts and `probe_success`, step 8). The checks that did run used a
> different spelling of the same queries. **The rebuild section (#57) has not
> been run yet.**
>
> What had to change against the draft:
> - **Step 1:** pull both `main` checkouts first; open the OKE tunnel as well
>   while OKE exists. The OCI session lasts about an hour: log in again before
>   step 6 and before step 7.
> - **Step 2:** the key backup taken with `get secret -o yaml` was 14 KB and the
>   password manager refused it. The key Secret carried a
>   `last-applied-configuration` annotation, which holds the private key a
>   second time. The backup is now a minimal export (about 7 KB).
> - **Step 4:** the certificate is ordered as soon as the app syncs, so it is
>   checked here, not in step 5. New checks: the Ingress address is compared
>   with the node's IP without printing either; k3s's external-dns must change
>   nothing while OKE owns the record. `diff` against the committed cert needs
>   `tr -d '\r'` on Windows. The manual sync was not needed (all apps were
>   healthy 3.5 minutes after `root.yaml`).
> - **Step 5:** Windows `curl -v` does not print the issuer; `openssl s_client`
>   does. Port 80 answers a GET with **301**, not 308 (k3s's Traefik 3.7.13;
>   POST and PUT get 308).
> - **Step 6:** a pre-check on the source cluster's backup name, a row-count
>   check, and the example code written out.
> - **Step 7:** the gitops CI refused an overlay without an Ingress, so the
>   switch PR also changed that rule (gitops PR #59). No `dig` on the laptop:
>   a DNS-over-HTTPS lookup replaces it.
> - **Step 8:** the script needs `--code` or `LINK_TOKEN`; the owner runs the
>   token check.

Do this in **one session**, in order. Each step ends with a check; do not go
on until it passes. Needed: the node is Ready (`scripts/k3s-verify.sh`, see
[k3s-access](k3s-access.md)), access to the password manager, an OCI login,
and the gitops repo's k3s cluster root on `main`.

```
Order:  1 tunnel -> 2 sealing keys -> 3 ArgoCD + root -> 4 apps healthy, edge, certificate
        -> 5 edge test (curl --resolve) -> 6 data restore
        -> 7 DNS switch -> 8 public check -> (then OKE teardown #13)
```

Times on the first run: step 3 to all apps healthy 3.5 minutes; certificate
issued within 3 minutes of the app sync; steps 1 to 6 about 35 minutes in
total, most of it step 2.

Shorthand used below:

```bash
K="kubectl --kubeconfig $HOME/.kube/k3s.kubeconfig"     # k3s, NOT the OKE kubeconfig
# The node's public IP, read into a variable and never printed. Needs a valid
# OCI session and the demo repo's main checkout (terraform/k3s is initialised there).
IP=$(terraform -chdir=terraform/k3s output -raw public_ip | tr -d '\r'); echo "IP read: ${#IP} characters"
```

Every command that changes a cluster names its kubeconfig. kubectl's default
context on the laptop is a different cluster, and during an overlap two demo
clusters are reachable: check `$K get nodes` shows `k3s-node-vnic` before each
change.

Never paste raw `external-dns` logs or `curl -v` output anywhere public: they
contain the Cloudflare zone id and IP addresses. The commands below strip them.

## 1. Open the tunnel

```bash
git -C ../oci-k8s-gitops-demo-gitops pull --ff-only     # step 3 applies from this checkout
git pull --ff-only                                      # this repo: scripts and terraform outputs
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
scripts/k3s-tunnel.sh            # keep it running; use another terminal
$K get nodes                     # k3s-node-vnic   Ready
```

The session token lasts about an hour and `oci session refresh` fails once it
has expired. Log in again before step 6 and before step 7. An expired session
shows as `executable oci failed with exit code 1` from the OKE kubeconfig, and
as an error from `terraform output`. The k3s tunnel is plain SSH and does not
need the session.

Only for the move from OKE (not for a rebuild): OKE is the source of the keys
and the data, so open its tunnel too, in a third terminal, from this repo's
root: `scripts/oke-tunnel.sh`.

## 2. Restore the sealing keys (BEFORE ArgoCD syncs anything)

Why first: `root.yaml` (step 3) syncs the Sealed Secrets controller together
with every SealedSecret. A controller that starts without the old keys creates
a new one, and every sealed file then fails to decrypt (ADR 0006). The keys
cannot live in Git, so this is the one place they are applied by hand.

The restore procedure is kept in one place, [sealed-secrets](sealed-secrets.md)
("Restore"); this step is the record of how it was run on 2026-11-12.

**The owner runs every command that reads or applies the key file**, in a
directory outside every repo. Anyone helping checks only outcomes: the number
of key Secrets, their names, and the public certificate.

Take the backup as described in [sealed-secrets](sealed-secrets.md) ("Back up
the keys": the minimal export). It must be newer than the latest key renewal
(every 30 days). For the move from OKE it was taken fresh from OKE; for a
rebuild it is taken from k3s before the uninstall.

```bash
F=sealed-secrets-keys-<cluster>-<date>-min.yaml          # the file from the password manager, outside every repo
[ "$($K get nodes -o jsonpath='{.items[*].metadata.name}')" = "k3s-node-vnic" ] && echo "cluster: k3s OK" \
  && $K apply --dry-run=server -f "$F" \
  && $K apply -f "$F"
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key
```

The `&&` chain applies nothing unless the node check and the server-side dry
run pass. A pasted block does not stop on a failed line by itself.

Check: the number of key Secrets equals the number in the file
(`grep -c '^kind: Secret' "$F"`), with the same names. Then delete the local
file (`rm -f "$F"`).

`apply` writes the `last-applied-configuration` annotation onto the key Secret
again (a second copy of the key inside the same Secret). That is why the backup
is a minimal export and not `-o yaml`.

On the first run: one key, `sealed-secrets-key9h8gh`, on both clusters. The
restored Secret gets a new creation time, so the date of the next 30-day
renewal on k3s is not certain (30 days after the certificate's start date,
2026-10-24, or after the restore, 2026-11-12). Count the keys again after
2026-11-23; a second key means a new backup.

## 3. Install ArgoCD and the cluster root (the only manual applies)

From the gitops repo's `main` checkout:

```bash
$K get nodes -o name                                  # node/k3s-node-vnic
$K apply --server-side -k argocd/install
$K -n argocd rollout status deploy/argocd-server --timeout=300s
$K apply -f argocd/clusters/k3s/root.yaml
```

After this, every change is a PR to the gitops repo (CLAUDE.md rule). No
further `kubectl apply`. The data restore in step 6 and manual backup Jobs are
the only other writes by hand.

Check: `$K -n argocd get applications` lists `root-k3s` and one Application
per file in `argocd/clusters/k3s/apps`, except `project.yaml` (an AppProject).

## 4. Apps healthy, edge address, certificate

```bash
$K -n argocd get applications          # all Synced and Healthy (3.5 minutes on the first run)
$K get sealedsecrets -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,SYNCED:'.status.conditions[?(@.type=="Synced")].status'
# every row: True
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key --no-headers | wc -l
# the same number as in step 2: the controller made no key of its own
```

- A SealedSecret with `Synced=False` and "no key could decrypt" means step 2
  was skipped or incomplete. Restore the keys, then **delete** the controller pod
  (never `rollout restart`; see the gotchas in [sealed-secrets](sealed-secrets.md)).
- The cluster's public cert must equal the committed one. From the gitops
  checkout (`tr` because a Windows checkout has CRLF line endings, and a plain
  `diff` then reports a difference that is not there):

  ```bash
  kubeseal --kubeconfig ~/.kube/k3s.kubeconfig --fetch-cert | tr -d '\r' \
    | diff - <(tr -d '\r' < argocd/clusters/k3s/sealed-secrets-cert.pem) && echo "cert matches"
  ```

  Because the keys are the OKE keys, the cert is OKE's, and the sealed files are
  copied unchanged (same names and namespaces, `--scope strict`).
- Postgres starts on an empty volume, and the backend creates an empty `links`
  table (ADR 0016). The site works but has no links until step 6.
- The link-shortener Application needs the monitoring CRDs (ServiceMonitor,
  Probe, PrometheusRule) from the monitoring app. It has no sync wave and
  retries 5 times, about 12 minutes in total. On the first run one retry was
  enough. If kube-prometheus-stack is ever slower than the retries, the
  Application stops: once monitoring is Healthy, sync `link-shortener` by hand
  in the ArgoCD UI ([access](access.md); the `argocd` CLI is not installed on
  the laptop). It has no wave on purpose: ordering it behind monitoring would
  take the site down whenever monitoring is unhealthy.

**Traefik edge checks** (ADR 0022; before any DNS change):

```bash
$K -n kube-system get svc traefik -o jsonpath='{.spec.externalTrafficPolicy}{"\n"}'   # Local
A=$($K -n link-shortener get ingress backend -o jsonpath='{.status.loadBalancer.ingress[*].ip}')
[ "$A" = "$IP" ] && echo "Ingress address: PUBLIC" || echo "Ingress address: NOT the public IP, stop"
```

The Traefik Service's own status keeps showing the private IP; only the
Ingress status is overridden. If the Ingress address is not the public IP, the
`ingressendpoint.ip` argument did not apply. Do not go on; fall back as ADR
0022 describes (`node-external-ip` and `Cluster`), which costs per-client rate
limiting but works for DNS.

**Certificate.** cert-manager orders it as soon as the Ingress exists, by
DNS-01 (ADR 0005), which needs no A record. It asks the production issuer
straight away: CI requires `letsencrypt-production` on every Ingress. Let's
Encrypt allows about 5 identical production certificates per week (check its
current limits), and every bootstrap and rebuild issues one. cert-manager
retries a failed order by itself after about an hour, so look now:

```bash
$K get certificate,order -A            # certificate READY True, order valid
```

If it is not ready after a few minutes, read the events and fix the cause
before the retry; do not delete and recreate the Certificate in a loop:

```bash
$K -n link-shortener describe certificate,certificaterequest,order,challenge
```

**While another cluster still owns the DNS record** (the move from OKE only):
k3s's external-dns sees the same hostname. It must not change anything, and
public DNS must still point at the other cluster:

```bash
$K -n external-dns logs deploy/external-dns --since=10m | grep -E 'action=' | sed -E 's/ zone=[0-9a-f]+//'
# prints nothing: no CREATE, UPDATE or DELETE ("All records are already up to date" each minute)
D=$(curl -s -H 'accept: application/dns-json' 'https://1.1.1.1/dns-query?name=demo.sandeeprn.in&type=A' \
  | grep -oE '"data":"[^"]+"' | cut -d'"' -f4)
[ "$D" = "$IP" ] && echo "DNS: the k3s node" || echo "DNS: not the k3s node (${D:+some other address}${D:-no record})"
```

## 5. Edge test before DNS moves

The certificate is already issued (step 4), so the whole path can be tested
under the real hostname while DNS still points elsewhere:

```bash
curl -sS --resolve demo.sandeeprn.in:443:$IP -o /dev/null -w '%{http_code} verify=%{ssl_verify_result}\n' https://demo.sandeeprn.in/healthz
# 200 verify=0   (0 = the chain is trusted)
echo | openssl s_client -connect "$IP:443" -servername demo.sandeeprn.in 2>/dev/null | openssl x509 -noout -issuer -subject -enddate
# issuer: O=Let's Encrypt (a staging certificate says STAGING; Traefik's own says TRAEFIK DEFAULT CERT)
curl -sS --resolve demo.sandeeprn.in:80:$IP -o /dev/null -w '%{http_code} %{redirect_url}\n' http://demo.sandeeprn.in/ \
  | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g'
# 301 https://demo.sandeeprn.in/
```

Check: 200 with a trusted chain, a Let's Encrypt production issuer, and a
permanent redirect on port 80. k3s's bundled Traefik (3.7.13) answers a GET
with 301 and other methods with 308; OKE's older Traefik answered 308 for
both, with the same setting (`permanent: true`). `scripts/verify-public-url.sh`
accepts either.

## 6. Restore the data

Restores the source cluster's newest backup into k3s Postgres. Do it within 14
days of that backup (the bucket's lifecycle deletes older objects). The bucket
survives the OKE teardown. Full procedure and the reasons for each flag:
[postgres-backup-restore](postgres-backup-restore.md), case **B (volume lost)**:
the new empty volume plus `pg_restore --clean --if-exists`.

Log in to OCI again first (step 1) if the session is older than about 45
minutes.

**A fresh backup on the source cluster**, so that no link is lost (ADR 0007
accepts up to a day; this makes it minutes). For the move from OKE
(`KO="kubectl --kubeconfig $HOME/.kube/oke-demo.kubeconfig"`):

```bash
$KO -n link-shortener get cronjob postgres-backup \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[?(@.name=="upload")].env[?(@.name=="BACKUP_CLUSTER")].value}{"\n"}'   # oke
J=postgres-backup-manual-$(date -u +%H%M)
$KO -n link-shortener create job --from=cronjob/postgres-backup "$J"
$KO -n link-shortener wait job/"$J" --for=condition=complete --timeout=400s
$KO -n link-shortener logs job/"$J" -c upload | tail -1     # uploaded link-shortener/oke/<timestamp>.pgc
```

For a rebuild, the source is k3s itself and this backup is taken before the
uninstall (rebuild step 1); the object is under `link-shortener/k3s/`.

**Download and restore:**

```bash
OCI="oci --auth security_token --profile oke-demo"
NS=$($OCI os ns get --query data --raw-output | tr -d '\r')
B=oci-k8s-gitops-demo-pg-backups
$OCI os object list -ns "$NS" -bn "$B" --prefix link-shortener/ --all --query 'data[].{name:name,size:size}' --output table
O=link-shortener/<cluster>/<timestamp>.pgc      # the object the upload log named
$OCI os object get -ns "$NS" -bn "$B" --name "$O" --file restore.pgc    # Git Bash on Windows: give --file a Windows path (cygpath -w)
$K get nodes -o name                            # node/k3s-node-vnic
$K -n link-shortener wait --for=condition=Ready pod/postgres-0 --timeout=300s
$K -n link-shortener exec -i postgres-0 -- sh -c 'pg_restore --no-owner --role=linkshortener_app --clean --if-exists --exit-on-error -U "$POSTGRES_USER" -d linkshortener' < restore.pgc
```

Check the rows before deleting the file. The first command counts the rows in
the dump (it only reads the file, inside the pod); the second counts the table:

```bash
$K -n link-shortener exec -i postgres-0 -- sh -c 'pg_restore --data-only -f -' < restore.pgc \
  | sed -n '/^COPY public.links/,/^\\\.$/p' | grep -vcE '^(COPY |\\\.$)'
$K -n link-shortener exec postgres-0 -- sh -c 'psql -X -At -U "$POSTGRES_USER" -d linkshortener -c "select count(*) from links" -c "select tableowner from pg_tables where tablename=\$\$links\$\$"'
rm restore.pgc    # it holds real data
```

Both counts are equal (34 on the first run) and the owner is
`linkshortener_app`.

Check: the landing page's example short link redirects on k3s. Its code is
`EXAMPLE_LINK_CODE` in the gitops overlay (`seYOHlz`):

```bash
curl -sS --resolve demo.sandeeprn.in:443:$IP -o /dev/null -w '%{http_code} %{redirect_url}\n' https://demo.sandeeprn.in/seYOHlz   # 302
```

Which object is the newest when no manual backup was taken: the change that
put the cluster into object names merged on 2026-11-12. The first OKE object
with the new name (`link-shortener/oke/<timestamp>.pgc`) was a manual backup
at 2026-11-12 07:48 UTC; the first nightly one ran at 2026-11-12 21:30 UTC
(03:00 IST on 2026-11-13). Older objects are the un-prefixed
`link-shortener/<timestamp>.pgc`. Pick the newest of both kinds.

Then run one manual backup on k3s:

```bash
J=postgres-backup-manual-$(date -u +%H%M)
$K -n link-shortener create job --from=cronjob/postgres-backup "$J"
$K -n link-shortener wait job/"$J" --for=condition=complete --timeout=400s
$K -n link-shortener logs job/"$J" -c upload | tail -1      # uploaded link-shortener/k3s/<timestamp>.pgc
$OCI os object list -ns "$NS" -bn "$B" --prefix link-shortener/k3s/ --query 'data[].{name:name,size:size}' --output table
```

Check: the log ends with `uploaded link-shortener/k3s/<timestamp>.pgc` (the
job refuses to run if the overlay sets no cluster) and the object is listed.
On the first run this proved that the node's instance principal may write to
the bucket.

## 7. DNS switch (done 2026-11-13; not part of a rebuild)

Kept as the record of how the hostname moved from OKE to k3s. In a rebuild the
record never leaves k3s, so this step is skipped.

A short gap is acceptable (ADR 0022). The order matters: external-dns on each
cluster owns its record by a TXT owner id and will not overwrite a record it
does not own, so the old cluster must let go first.

1. In the gitops repo, a PR removes the Ingress from the old cluster's overlay
   (gitops PR #59). The gitops CI required an Ingress in every deployed
   overlay; the same PR changed that rule to require **no** Ingress in
   `overlays/oke`, so two clusters can never claim the hostname again.
   **Merging the PR is the switch.** Before merging: both tunnels up, CI green,
   both external-dns logging "All records are already up to date".
2. After the merge, the old cluster's ArgoCD prunes the Ingress and its
   external-dns (`--policy=sync`) deletes the A record and its TXT owner record
   (`edns-a-demo.sandeeprn.in`). If ArgoCD is no longer healthy there, delete
   both records in Cloudflare by hand (ADR 0020).
3. k3s's external-dns creates its own records from the k3s Ingress status.
   Watch (the `sed` removes the zone id):

   ```bash
   $K -n external-dns logs deploy/external-dns --since=10m | grep -E 'action=' | sed -E 's/ zone=[0-9a-f]+//'
   # action=CREATE record=demo.sandeeprn.in ... type=A, and the TXT record
   ```

4. Public DNS equals the node's public IP: the DNS-over-HTTPS lookup from
   step 4 prints `DNS: the k3s node`. (`dig` is not installed on the laptop.)

First run: merged 22:10:14 UTC, OKE deleted its records 22:13:00, k3s created
its own 22:13:25, so the record was absent for 25 seconds. The record's TTL is
300 seconds; resolvers may keep the old answer that long.

## 8. Check the public URL

```bash
scripts/verify-public-url.sh --production --hsts --code seYOHlz
```

Without a token the script cannot create a link, so `--code` gives it an
existing one to test the redirect with, and the line "Create with a valid
token gets 201" FAILS with "LINK_TOKEN is not set". Everything else passes;
the burst gets 429s (per client on k3s, ADR 0022).

The owner then runs the token check (it creates one real link). The token is
read with a hidden prompt and never printed:

```bash
read -rsp "link token (your owner token): " OWNER_LINK_TOKEN; echo; echo "length: ${#OWNER_LINK_TOKEN} (0 = nothing was read)"
LINK_TOKEN="$OWNER_LINK_TOKEN" scripts/verify-public-url.sh --production --hsts --no-burst
unset OWNER_LINK_TOKEN
# 9 passed, 0 failed, 2 skipped
```

This also proves that the `link-tokens` SealedSecret decrypted with the reused
key and that the app may write to the restored table.

Then confirm from the cluster's side that only `Watchdog` fires and the
in-cluster probe succeeds (it targets the backend Service, not the public
hostname, so the switch does not affect it):

```bash
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
$K get --raw "$P/alerts" | grep -oE '"alertname":"[^"]+"' | sort | uniq -c
$K get --raw "$P/query?query=probe_success" | grep -oE '"value":\[[^]]+\]'      # ends in "1"
```

Only now is OKE safe to tear down (#13): **keep the sealing-key backup**, it
is the k3s key now.

## Rebuild proof (#57): same VM, never destroyed

**Not run yet.** Proves that the cluster can be rebuilt from Git, the key
backup and the data backup. The VM, its boot volume and its IP stay
(`prevent_destroy`; ADR 0001, 0022).

1. Take a fresh sealing-key backup **from k3s** (the minimal export in
   [sealed-secrets](sealed-secrets.md)) and a manual database backup (the Job
   at the end of step 6). Store the key backup; check that the backup object is
   listed under `link-shortener/k3s/`. Do not skip: step 2 deletes both from
   the node.
2. Remove k3s on the node (this deletes the cluster state, the Postgres volume
   and ArgoCD):

   ```bash
   ssh -i ~/.ssh/k3s-node -o LogLevel=ERROR ubuntu@$IP 'sudo /usr/local/bin/k3s-uninstall.sh'
   ```

3. Reinstall with the same script the first boot used. It is safe to repeat
   and pinned to `k3s_version`:

   ```bash
   ssh -i ~/.ssh/k3s-node -o LogLevel=ERROR ubuntu@$IP 'sudo bash /usr/local/sbin/bootstrap-node.sh'
   scripts/k3s-verify.sh            # 9/9 PASS
   ```

4. Repeat steps 1 to 6 above (tunnel, keys, ArgoCD, apps and certificate, edge
   test, data). Step 7 is skipped: the record never left, so external-dns keeps
   it. Then step 8. The rebuild orders a new production certificate (the
   weekly limit in step 4 applies).
5. `terraform plan` from a clean checkout shows no changes. Record the times
   (uninstall to first healthy app, to restored data) in the PR; they are the
   evidence.

The host key stays the same, since the VM is not replaced, so SSH does not warn.

## When something fails

| Symptom | Cause and fix |
|---|---|
| `executable oci failed with exit code 1`, or `terraform output` fails | The OCI session expired (about 1 hour). `oci session authenticate` again; the tunnels can stay. |
| The password manager refuses the key backup as too long | It was taken with `-o yaml` and holds the key twice. Use the minimal export ([sealed-secrets](sealed-secrets.md)). |
| `Synced=False`, "no key could decrypt" | Step 2 skipped or incomplete. Restore keys, delete the controller pod. |
| `diff` says the cert differs | Line endings on Windows: compare with `tr -d '\r'` (step 4). |
| Ingress address is a 10.x address | The sealed `PUBLIC_IP` is missing or Traefik's argument is wrong. Fix in the gitops repo; do not move DNS. |
| Certificate stuck `False` | `$K describe certificate,order,challenge -A`; Cloudflare token errors show in the cert-manager logs. Fix the cause before the automatic retry. |
| `curl --resolve` times out on 443 | The security list: `terraform plan` in `terraform/k3s` must show no changes; `web_allowed_cidr` may have been narrowed. |
| A PR that removes an Ingress fails `validate` with "no Ingress" | The gitops CI expects one in every deployed overlay; change the rule in the same PR (step 7). |
| Record not created after the old record is gone | k3s external-dns owner id or filter; its logs say why. Never change `txtOwnerId` after deployment. |
| Backend returns 503 right after step 6 | Expected for seconds while the restored table is swapped in; it recovers on its own. |
