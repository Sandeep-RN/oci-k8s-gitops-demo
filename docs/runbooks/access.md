# Runbook: reaching the k3s cluster, the app and the admin UIs

How to get from a laptop to everything that runs on the single-node k3s
cluster, which serves `https://demo.sandeeprn.in` since 2026-11-12 (ADR 0022):
`kubectl`, the public app, ArgoCD, and the monitoring UIs. Commands are for
Git Bash on Windows; they work the same on Linux and macOS.

Nothing here is public except the app. The Kubernetes API (6443) is never open
to the internet: `kubectl` goes through an SSH tunnel to the node (ADR 0010),
and every admin UI is reached with `kubectl port-forward` (ADR 0014).

```text
laptop 127.0.0.1:16443 ──ssh (22)──► node 127.0.0.1:6443 (k3s API)    kubectl, port-forward
laptop ──https─► node's public IP ──► Traefik ──► backend pods          the app (public)
laptop ──port-forward (through the API)──► ArgoCD / Grafana / Prometheus / Alertmanager
```

## Not yet run on k3s in this form

These commands come from the OKE version of this page; only the kubeconfig
changed. Run each once on k3s, check the output matches what this page says,
and remove it from this list:

- `$K get pods -A`, `$K -n link-shortener get pods -o wide`, `$K -n link-shortener logs deploy/backend`, `$K -n link-shortener describe pod <pod>`, `$K -n link-shortener delete pod <pod>`
- `$K -n argocd port-forward svc/argocd-server 8080:443` and the `argocd-initial-admin-secret` password command
- the three monitoring port-forwards (`kps-grafana`, `kps-prometheus`, `kps-alertmanager`) and the `grafana-admin` password command

## Every session, in order

### 1. Reach the cluster

From the `oci-k8s-gitops-demo` repo. The tunnel script reads the node's IP
from Terraform state, which needs a valid OCI session (about an hour); the
tunnel itself is plain SSH and does not.

```bash
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
scripts/k3s-tunnel.sh          # fetches ~/.kube/k3s.kubeconfig, holds the tunnel; Ctrl+C closes
```

In a second terminal:

```bash
K="kubectl --kubeconfig $HOME/.kube/k3s.kubeconfig"     # k3s, NOT the OKE kubeconfig
$K get nodes                     # k3s-node-vnic   Ready
```

Every command names the k3s kubeconfig because kubectl's default context on
the laptop is a different cluster. There is one node. Details (the SSH key,
`--no-tunnel`, the node checks, what to do when SSH fails):
[k3s-access](k3s-access.md).

`~/.kube/k3s.kubeconfig` holds the cluster-admin certificate. Never put it in
a repo, an issue or a chat.

### 2. Use kubectl

```bash
$K get pods -A                                   # everything
$K -n link-shortener get pods -o wide            # backend x2 + postgres-0, all on the one node
$K -n link-shortener logs deploy/backend         # logs from one backend pod
$K -n argocd get applications                    # all should be Synced / Healthy
$K -n link-shortener describe pod <pod>          # events: why a pod is Pending or crashing
```

House rules (ArgoCD owns the cluster):

- **No `kubectl apply`, `edit` or `scale`.** Change the gitops repo instead;
  ArgoCD reverts manual changes (self-heal).
- **No `kubectl rollout restart`** (nor the Restart action in the ArgoCD UI,
  which writes the same annotation). It adds a `restartedAt` annotation that
  Git doesn't have. Whether ArgoCD then shows OutOfSync depends on how it
  diffs that resource; in one drill it did, and self-heal could not clear it
  ([sealed-secrets](sealed-secrets.md), gotcha 2). To restart, delete a pod:
  `$K -n link-shortener delete pod <pod>`; the Deployment replaces it and no
  spec changes.
- `get`, `describe`, `logs` and `port-forward` are fine. Do not `drain` the
  node: it is the only one, so its pods have nowhere to go.

## The app (public)

```bash
URL=https://demo.sandeeprn.in

# Creating a link needs a named token (ADR 0020); paste yours from the
# password manager. The header goes in on stdin (-H @-), so the token is not
# in curl's argv or your shell history.
read -r -s -p 'Link token: ' LINK_TOKEN; echo
printf 'Authorization: Bearer %s\n' "$LINK_TOKEN" |
  curl -s -X POST "$URL/api/links" -H @- -H 'content-type: application/json' \
    -d '{"url":"https://example.com"}'              # -> 201 {"code":"AbC1234", ...}; 401 without a valid token
curl -si "$URL/AbC1234" | head -3             # -> 302 and Location: https://example.com (no token)
curl -s "$URL/readyz"                         # -> {"status":"ready"}
```

Tokens are keys of the `link-tokens` SealedSecret in the gitops repo. Adding
or rotating one is in the [edge runbook](edge.md); read its warning first, as
the sealing script still writes to the OKE overlay. Scripts that create links
read the token from `LINK_TOKEN`, never from a file in a repo.

### Verify the public URL

`scripts/verify-public-url.sh` checks `https://demo.sandeeprn.in` from outside
(DNS, certificate, redirects, token gate, rate limit) with a PASS/FAIL line per
check and a non-zero exit on failure. Flags and checks are in its header. The
HSTS check runs by default, so a missing or changed header fails the run;
`--no-hsts` skips it (the old `--hsts` flag is still accepted and does nothing).
The standard run, as in step 8 of [k3s-bootstrap](k3s-bootstrap.md):

```bash
scripts/verify-public-url.sh --production --code seYOHlz
```

Without a token, `--code` gives it an existing short link to test the redirect
with, and only "Create with a valid token gets 201" fails. With the owner
token:

```bash
read -rsp "link token (your owner token): " OWNER_LINK_TOKEN; echo; echo "length: ${#OWNER_LINK_TOKEN} (0 = nothing was read)"
LINK_TOKEN="$OWNER_LINK_TOKEN" scripts/verify-public-url.sh --production --no-burst
unset OWNER_LINK_TOKEN
# 9 passed, 0 failed, 2 skipped
```

Its burst check makes the site answer 429 to your own address for a few
seconds (the limit is per client on k3s, ADR 0022), so do not run it while a
load test from the same machine needs the site.

## ArgoCD UI

```bash
$K -n argocd port-forward svc/argocd-server 8080:443
```

Open <https://localhost:8080> and accept the browser warning (the certificate is
self-signed). User `admin`; password:

```bash
$K -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

What to look at: the `root-k3s` app and its children, each app's resource tree,
sync status and history (every sync names the Git commit it applied). Clicking
"Sync" is harmless; editing manifests in the UI is not (same rule as
`kubectl apply`).

## Monitoring UIs

Each command holds a port-forward open; run each in its own terminal, or one at
a time.

| UI | Command | Open |
|---|---|---|
| Grafana | `$K -n monitoring port-forward svc/kps-grafana 3000:80` | <http://localhost:3000> |
| Prometheus | `$K -n monitoring port-forward svc/kps-prometheus 9090:9090` | <http://localhost:9090> |
| Alertmanager | `$K -n monitoring port-forward svc/kps-alertmanager 9093:9093` | <http://localhost:9093> |

Grafana login: user `admin`, password:

```bash
$K -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

The password was generated once and stored only as a SealedSecret
(`monitoring/k3s/` in the gitops repo, a copy of the OKE one); this command is
the only way to read it.

First things to try:

- **Prometheus → Status → Targets**: `serviceMonitor/link-shortener/backend`
  should show 2 endpoints UP.
- **Prometheus → Graph**:
  `sum by (route, status) (rate(http_request_duration_seconds_count[5m]))`
  is requests per second by route and status.
- **Grafana → Dashboards**: "Link shortener / Redirect SLO", and the built-in
  Kubernetes dashboards (node and pod CPU/memory).
- **Alertmanager**: active alerts. `Watchdog` always fires on purpose; it
  proves the alert pipeline works.

Alerts and what to do about them: [redirect SLO runbook](slo-redirect-availability.md).
Backups and restores: [Postgres backup runbook](postgres-backup-restore.md).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `kubectl`: "connection refused" on 127.0.0.1:16443 | Tunnel not running | Step 1 |
| Tunnel script: `ssh: connect to host ... timed out`, or it fails at "fetching the kubeconfig" | Your public IP changed and is outside `ssh_allowed_cidr` | Set it in `terraform/k3s/terraform.tfvars` (git-ignored), plan and apply; see [k3s-access](k3s-access.md) |
| Tunnel script fails before SSH, or `terraform output` fails | The OCI session expired (about 1 hour) | `oci session authenticate` again, or set `K3S_NODE_IP` ([k3s-access](k3s-access.md)) |
| `kubectl`: hangs, then i/o timeout | Tunnel stale: the process is alive but the connection is dead | Ctrl+C the tunnel, run it again |
| port-forward: "lost connection to pod" | Idle timeout or the pod restarted | Run the port-forward again |
| Browser: "connection refused" on localhost | The port-forward isn't running | Start it; keep its terminal open |

## Discord webhook for alerts (one-time)

Alertmanager posts alerts to a Discord channel through an *incoming* webhook.
It is created in Discord, not in GitHub (GitHub's webhooks page is for GitHub
calling others).

1. In Discord, create a server (or use one you own) and a channel, for example
   `#alerts`.
2. Channel → **Edit Channel** (gear) → **Integrations** → **Webhooks** →
   **New Webhook** → name it `alertmanager`.
3. **Copy Webhook URL**.

Treat the URL like a password: anyone with it can post to the channel. Don't
paste it into chat, issues, files or commits. It is sealed into a SealedSecret
straight from the clipboard or a hidden prompt, in the change that adds the
Discord receiver.

## Closing down

Ctrl+C the port-forwards and the tunnel.

## History: access to the OKE target

The OKE target served the site until 2026-11-12. It still exists with no
public way in; its teardown is issue #13 (due 2026-11-15). This section goes
away with the teardown.

OKE's Kubernetes API has a private endpoint, reached through OCI Bastion
(ADR 0010, ADR 0015):

```text
laptop ──ssh──► OCI Bastion ──► Kubernetes API (private)     kubectl, port-forward
```

- Log in to OCI first (the same `oci session authenticate` as above).
  `kubectl` on OKE uses the same token: each call fetches a short-lived
  Kubernetes token through the OCI CLI (`oci ce cluster generate-token`), so
  when the session expires every `kubectl` command fails with "exec plugin ...
  failed" or 401 until you log in again.
- `scripts/oke-tunnel.sh` (or `OCI_CLI=~/bin/oci.exe scripts/oke-tunnel.sh`
  if `oci` is not on PATH) creates a Bastion session (about 30-60 s), writes
  `~/.kube/oke-demo.kubeconfig` and holds the tunnel open on 127.0.0.1:6443.
  Ignore the "post-quantum key exchange" warning. **Ctrl+C** closes the tunnel
  and deletes the Bastion session; a forgotten session expires on its own
  after 3 h.
- Use `kubectl --kubeconfig ~/.kube/oke-demo.kubeconfig`. OKE had 2 nodes and
  the root Application `root-oke`.
- A stale tunnel that could not be closed with Ctrl+C leaves a session behind:
  delete it in Console → Bastion.
- If the Bastion refuses the connection, your public IP changed: update
  `bastion_client_cidr` in `terraform/oke/terraform.tfvars`, then
  `terraform apply`.
