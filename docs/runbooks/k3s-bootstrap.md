# Runbook: bring the demo up on k3s (bootstrap, data, DNS switch, rebuild)

ADR 0022 (the move), ADR 0006 (sealing keys), ADR 0007 (backups), ADR 0020 (edge).
Issues: #8 (this draft), #57 (rebuild proof).

> **Status: DRAFT, not run yet.** The k3s gitops side is merged (cluster root
> and platform apps #56, monitoring #58, app overlay #57; all 2026-11-12), so
> the paths below exist, but nothing has been applied to the node yet. The
> steps that reuse tested procedures link to them. After the first real run,
> replace this banner with the date and what had to change.

Do this in **one session**, in order. Each step ends with a check; do not go
on until it passes. Needed: the node is Ready (`scripts/k3s-verify.sh`, see
[k3s-access](k3s-access.md)), the sealing-key backup from the password manager,
a valid OCI session, and the gitops repo's k3s cluster root merged.

```
Order:  1 tunnel -> 2 sealing keys -> 3 ArgoCD + root -> 4 apps healthy
        -> 5 certificate (curl --resolve) -> 6 data restore
        -> 7 DNS switch -> 8 public check -> (then OKE teardown #13)
```

Shorthand used below:

```bash
K="kubectl --kubeconfig ~/.kube/k3s.kubeconfig"     # k3s, NOT the OKE kubeconfig
```

Every command that changes a cluster names its kubeconfig. Two clusters are
reachable from the same laptop during the overlap: check `$K get nodes` shows
`k3s-node-vnic` before each destructive step.

## 1. Open the tunnel

```bash
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
scripts/k3s-tunnel.sh            # keep it running; use another terminal
$K get nodes                     # k3s-node-vnic   Ready
```

## 2. Restore the sealing keys (BEFORE ArgoCD syncs anything)

Why first: `root.yaml` (step 3) syncs the Sealed Secrets controller together
with every SealedSecret. A controller that starts without the old keys creates
a new one, and every sealed file then fails to decrypt (ADR 0006). The keys
cannot live in Git, so this is the one place they are applied by hand.

The backup file is the one from [sealed-secrets](sealed-secrets.md) ("Back up
the keys"), taken from the OKE cluster. If it is older than the latest key
renewal (every 30 days), take a fresh one from OKE first; OKE is still up.

```bash
$K apply -f sealed-secrets-keys-oke-<date>.yaml            # key Secrets, outside every repo
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key
```

Check: the number of key Secrets equals the number in the backup file
(`grep -c '^- apiVersion: v1' sealed-secrets-keys-*.yaml`). Delete the local
file afterwards.

## 3. Install ArgoCD and the cluster root (the only manual applies)

From a checkout of the gitops repo, on `main`:

```bash
$K apply --server-side -k argocd/install
$K -n argocd rollout status deploy/argocd-server --timeout=300s
$K apply -f argocd/clusters/k3s/root.yaml
```

After this, every change is a PR to the gitops repo (CLAUDE.md rule). No
further `kubectl apply`, except step 2 and the data restore in step 6.

Check: `$K -n argocd get applications` lists the apps from `argocd/clusters/k3s/apps`.

## 4. Apps healthy

```bash
$K -n argocd get applications          # all Synced and Healthy (monitoring may take minutes)
$K get sealedsecrets -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,SYNCED:'.status.conditions[?(@.type=="Synced")].status'
# every row: True
```

- A SealedSecret with `Synced=False` and "no key could decrypt" means step 2
  was skipped or incomplete. Restore the keys, then **delete** the controller pod
  (never `rollout restart`; see the gotchas in [sealed-secrets](sealed-secrets.md)).
- The cluster's public cert must equal the committed one:
  `kubeseal --kubeconfig ~/.kube/k3s.kubeconfig --fetch-cert | diff - argocd/clusters/k3s/sealed-secrets-cert.pem`.
  Because the keys are the OKE keys, the cert is OKE's, and the sealed files are
  copied unchanged (same names and namespaces, `--scope strict`).
- Postgres starts on an empty volume; the backend is not fully ready until
  step 6 (it creates an empty table first, ADR 0016).
- The link-shortener Application needs the monitoring CRDs (ServiceMonitor,
  Probe, PrometheusRule) from the monitoring app. It has no sync wave and
  retries 5 times, about 12 minutes in total. If kube-prometheus-stack is
  slower than that on the 12 GB node, the Application stops retrying: once
  monitoring is Healthy, run `argocd app sync link-shortener` (the ArgoCD UI
  works too). It has no wave on purpose: ordering it behind monitoring would
  take the site down whenever monitoring is unhealthy.

**Traefik edge checks** (ADR 0022; before any DNS change):

```bash
$K -n kube-system get svc traefik -o jsonpath='{.spec.externalTrafficPolicy}{"\n"}'   # Local
$K get ingress -A      # ADDRESS column = the node's PUBLIC IP (from the sealed PUBLIC_IP), not 10.x
```

If the address is the private IP, the `ingressendpoint.ip` argument did not
apply. Do not go on; fall back as ADR 0022 describes (`node-external-ip` and
`Cluster`), which costs per-client rate limiting but works for DNS.

## 5. Certificate, tested before DNS moves

cert-manager issues by DNS-01 (ADR 0005), which needs no A record, so the
certificate can be ready while `demo.sandeeprn.in` still points at OKE.
On k3s the Ingress asks the production issuer straight away: CI requires
`letsencrypt-production` on every Ingress, and DNS-01 is already proven on OKE.
Let's Encrypt allows about 5 identical production certificates per week (check
its current limits), and OKE, this bootstrap and the rebuild proof (#57) each
issue one. So if the first order fails, read the events before anything
retries, and fix the cause; do not delete and recreate the Certificate in a loop:

```bash
$K -n link-shortener describe certificate,certificaterequest,order,challenge
```

```bash
$K get certificate -A                  # READY True
IP=$(terraform -chdir=terraform/k3s output -raw public_ip)
curl -sS --resolve demo.sandeeprn.in:443:$IP -o /dev/null -w '%{http_code}\n' https://demo.sandeeprn.in/healthz
curl -sSv --resolve demo.sandeeprn.in:443:$IP -o /dev/null https://demo.sandeeprn.in/ 2>&1 | grep -iE 'issuer|subject|expire'
curl -sS --resolve demo.sandeeprn.in:80:$IP -o /dev/null -w '%{http_code} %{redirect_url}\n' http://demo.sandeeprn.in/   # 308 to https
```

Check: the issuer is Let's Encrypt production (not "TRAEFIK DEFAULT CERT").
Port 80 answers with the 308 redirect.

## 6. Restore the data

Restores OKE's last nightly backup into k3s Postgres. Do it within 14 days of
that backup (the bucket's lifecycle deletes older objects). The bucket survives
the OKE teardown. Full procedure and the reasons for each flag:
[postgres-backup-restore](postgres-backup-restore.md), case **B (volume lost)**:
the new empty volume plus `pg_restore --clean --if-exists`.

```bash
OCI="oci --auth security_token --profile oke-demo"
NS=$($OCI os ns get --query data --raw-output)
B=oci-k8s-gitops-demo-pg-backups
$OCI os object list -ns "$NS" -bn "$B" --prefix link-shortener/ --query 'data[].{name:name,size:size}' --output table
O=link-shortener/oke/<latest timestamp>.pgc     # the newest OKE backup: see the note below
$OCI os object get -ns "$NS" -bn "$B" --name "$O" --file restore.pgc
$K -n link-shortener wait --for=condition=Ready pod/postgres-0 --timeout=300s
$K -n link-shortener exec -i postgres-0 -- sh -c 'pg_restore --no-owner --role=linkshortener_app --clean --if-exists --exit-on-error -U "$POSTGRES_USER" -d linkshortener' < restore.pgc
rm restore.pgc    # it holds real data
```

Check: the landing page's example short link redirects on k3s, through the
node, with DNS still on OKE:

```bash
curl -sS --resolve demo.sandeeprn.in:443:$IP -o /dev/null -w '%{http_code} %{redirect_url}\n' https://demo.sandeeprn.in/<example-code>   # 302
```

Which object is "the newest OKE backup": OKE objects carry the cluster in
their name from the night of 2026-11-13 (`link-shortener/oke/<timestamp>.pgc`).
Before that night, the newest one is the un-prefixed
`link-shortener/<timestamp>.pgc`. Pick the newest of both kinds.

Links created on OKE after that backup are lost (ADR 0007 accepts up to a
day). For a smaller gap, take a manual backup on OKE just before this step
(see the alert section of the backup runbook), and use that object.

Then run one manual backup on k3s. Check that its log ends with
`uploaded link-shortener/k3s/<timestamp>.pgc` (the job refuses to run if the
overlay sets no cluster) and that the object is listed under
`link-shortener/k3s/`. That also proves the node's instance principal may
write to the bucket (the policy was inferred from code, not tested on k3s).

## 7. DNS switch (the only moment the URL can go dark)

A short gap is acceptable (ADR 0022). The order matters: external-dns on each
cluster owns its record by a TXT owner id and will not overwrite a record it
does not own, so OKE must let go first.

1. In the gitops repo, a PR removes the Ingress from `overlays/oke`. After it
   merges and ArgoCD syncs (prune), OKE's external-dns (`--policy=sync`) deletes
   `demo.sandeeprn.in` and its TXT record. If ArgoCD is no longer healthy on
   OKE, delete the record and its TXT owner record in Cloudflare by hand
   (ADR 0020).
2. Check it is gone: `dig +short demo.sandeeprn.in @1.1.1.1` prints nothing.
3. k3s's external-dns creates its own record from the k3s Ingress status (the
   node's public IP). Watch: `$K -n external-dns logs deploy/external-dns --tail=20`
   shows `CREATE` for `demo.sandeeprn.in`.
4. `dig +short demo.sandeeprn.in @1.1.1.1` equals the node's public IP
   (compare with `$IP`; do not paste it anywhere public).

Resolvers may cache the old answer for the record's TTL.

## 8. Check the public URL

```bash
scripts/verify-public-url.sh --production --hsts
```

All checks pass. Then confirm from the cluster's side: the probe and SLO
alerts on k3s are healthy, and `PROBE_BASE_URL` still points at the hostname
(nothing to change if it does). Only now is OKE safe to tear down (#13):
**keep the sealing-key backup**, it is the k3s key now.

## Rebuild proof (#57): same VM, never destroyed

Proves that the cluster can be rebuilt from Git, the key backup and the data
backup. The VM, its boot volume and its IP stay (`prevent_destroy`; ADR 0001,
0022).

1. Take a fresh sealing-key backup **from k3s** and a manual database backup.
   Store the key backup; check both are readable. Do not skip: step 3 deletes
   them from the node.
2. Remove k3s on the node (this deletes the cluster state, the Postgres volume
   and ArgoCD):

   ```bash
   ssh -i ~/.ssh/k3s-node ubuntu@<node-ip> 'sudo /usr/local/bin/k3s-uninstall.sh'
   ```

3. Reinstall with the same script the first boot used. It is safe to repeat
   and pinned to `k3s_version`:

   ```bash
   ssh -i ~/.ssh/k3s-node ubuntu@<node-ip> 'sudo bash /usr/local/sbin/bootstrap-node.sh'
   scripts/k3s-verify.sh            # 9/9 PASS
   ```

4. Repeat steps 1 to 6 above (tunnel, keys, ArgoCD, apps, certificate, data).
   DNS needs no switch: the record never left, so external-dns keeps it. The
   public check (step 8) applies once the edge is back.
5. `terraform plan` from a clean checkout shows no changes. Record the times
   (uninstall to first healthy app, to restored data) in the PR; they are the
   evidence.

The host key stays the same, since the VM is not replaced, so SSH does not warn.

## When something fails

| Symptom | Cause and fix |
|---|---|
| `Synced=False`, "no key could decrypt" | Step 2 skipped or incomplete. Restore keys, delete the controller pod. |
| Ingress ADDRESS is a 10.x address | The sealed `PUBLIC_IP` is missing or Traefik's argument is wrong. Fix in the gitops repo; do not move DNS. |
| Certificate stuck `False` | `$K describe certificate,order,challenge -A`; Cloudflare token errors show in the cert-manager logs. |
| `curl --resolve` times out on 443 | The security list: `terraform plan` in `terraform/k3s` must show no changes; `web_allowed_cidr` may have been narrowed. |
| Record not created after the OKE record is gone | k3s external-dns owner id or filter; its logs say why. Never change `txtOwnerId` after deployment. |
| Backend returns 503 right after step 6 | Expected for seconds while the restored table is swapped in; it recovers on its own. |
