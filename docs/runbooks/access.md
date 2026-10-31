# Runbook: reaching the OKE cluster, the app and the admin UIs

How to get from a laptop to everything that runs on the short-lived OKE target
(ADR 0015): `kubectl`, the public app, ArgoCD, and the monitoring UIs. Commands
are for Git Bash on Windows; they work the same on Linux and macOS.

Nothing here is public except the app. The Kubernetes API has a private
endpoint (reached through OCI Bastion, ADR 0010), and every admin UI is reached
with `kubectl port-forward` (ADR 0014).

```text
laptop ──ssh──► OCI Bastion ──► Kubernetes API (private)     kubectl, port-forward
laptop ──http─► Flexible Load Balancer ──► backend pods      the app (public)
laptop ──port-forward (through the API)──► ArgoCD / Grafana / Prometheus / Alertmanager
```

## Every session, in order

### 1. Log in to OCI (about every hour)

```bash
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
oci session validate --profile oke-demo --local   # prints "valid until ..."
```

A browser window opens; log in there. The token lasts about an hour.
`oci session refresh --profile oke-demo` extends it, but not indefinitely.
`kubectl` uses the same token, so when it expires every `kubectl` command fails
until you log in again.

### 2. Open the tunnel (keep this terminal open)

From the `oci-k8s-gitops-demo` repo:

```bash
scripts/oke-tunnel.sh
# if `oci` is not on PATH in this terminal:
OCI_CLI=~/bin/oci.exe scripts/oke-tunnel.sh
```

It creates a Bastion session (about 30-60 s), writes
`~/.kube/oke-demo.kubeconfig` and holds the tunnel open. Ignore the
"post-quantum key exchange" warning. **Ctrl+C** closes the tunnel and deletes
the Bastion session.

### 3. Use kubectl (in a second terminal)

Each `kubectl` call takes a few seconds: it first fetches a short-lived
Kubernetes token through the OCI CLI (`oci ce cluster generate-token`).

```bash
export KUBECONFIG=~/.kube/oke-demo.kubeconfig

kubectl get nodes                                   # 2 nodes, Ready
kubectl get pods -A                                 # everything
kubectl -n link-shortener get pods -o wide          # backend x2 + postgres-0, and their nodes
kubectl -n link-shortener logs deploy/backend       # logs from one backend pod
kubectl -n argocd get applications                  # all should be Synced / Healthy
kubectl -n link-shortener describe pod <pod>        # events: why a pod is Pending or crashing
```

House rules (ArgoCD owns the cluster):

- **No `kubectl apply`, `edit` or `scale`.** Change the gitops repo instead;
  ArgoCD reverts manual changes (self-heal).
- **No `kubectl rollout restart`.** It adds an annotation that Git doesn't
  have, so the app shows OutOfSync. To restart, delete a pod:
  `kubectl -n link-shortener delete pod <pod>`; the Deployment replaces it.
- `get`, `describe`, `logs`, `port-forward`, `drain`/`uncordon` are fine.

## The app (public)

```bash
LB=$(kubectl -n link-shortener get svc backend -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "http://$LB"

# Creating a link needs a named token (ADR 0020); paste yours from the
# password manager. The header goes in on stdin (-H @-), so the token is not
# in curl's argv or your shell history.
read -r -s -p 'Link token: ' LINK_TOKEN; echo
printf 'Authorization: Bearer %s\n' "$LINK_TOKEN" |
  curl -s -X POST "http://$LB/api/links" -H @- -H 'content-type: application/json' \
    -d '{"url":"https://example.com"}'              # -> 201 {"code":"AbC1234", ...}; 401 without a valid token
curl -si "http://$LB/AbC1234" | head -3             # -> 302 and Location: https://example.com (no token)
curl -s "http://$LB/readyz"                         # -> {"status":"ready"}
```

Tokens are keys of the `link-tokens` SealedSecret in the gitops repo; add or
rotate one with its `scripts/seal-link-tokens.sh`. Scripts that create links
read the token from `LINK_TOKEN`, never from a file in a repo.

### Verify the public URL

`scripts/verify-public-url.sh` checks `https://demo.sandeeprn.in` from outside
(DNS, certificate, redirects, token gate, rate limit) with a PASS/FAIL line per
check and a non-zero exit on failure. Flags and checks are in its header.

```bash
read -r -s -p 'Link token: ' LINK_TOKEN; export LINK_TOKEN; echo
scripts/verify-public-url.sh --staging                  # now
scripts/verify-public-url.sh --production --hsts        # after demo #90
scripts/verify-public-url.sh --production --hsts --cutover   # after the cutover (needs the tunnel)
```

Its burst check trips the shared rate limit for a few seconds, so do not run it
while a load test or the probe needs the site.

The address only needs the tunnel to *look up*; the app itself is reachable
from anywhere without it. Don't commit the address (public-repo rule).

## ArgoCD UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open <https://localhost:8080> and accept the browser warning (the certificate is
self-signed). User `admin`; password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

What to look at: the `root-oke` app and its children, each app's resource tree,
sync status and history (every sync names the Git commit it applied). Clicking
"Sync" is harmless; editing manifests in the UI is not (same rule as
`kubectl apply`).

## Monitoring UIs (after the monitoring stack is deployed)

Each command holds a port-forward open; run each in its own terminal, or one at
a time.

| UI | Command | Open |
|---|---|---|
| Grafana | `kubectl -n monitoring port-forward svc/kps-grafana 3000:80` | <http://localhost:3000> |
| Prometheus | `kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090` | <http://localhost:9090> |
| Alertmanager | `kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093` | <http://localhost:9093> |

Grafana login: user `admin`, password:

```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

The password was generated once and stored only as a SealedSecret
(`monitoring/oke/` in the gitops repo); this command is the only way to read it.

First things to try:

- **Prometheus → Status → Targets**: `serviceMonitor/link-shortener/backend`
  should show 2 endpoints UP.
- **Prometheus → Graph**:
  `sum by (route, status) (rate(http_request_duration_seconds_count[5m]))`
  is requests per second by route and status.
- **Grafana → Dashboards**: the built-in Kubernetes dashboards (node and pod
  CPU/memory). The SLO dashboard is added with the SLO rules.
- **Alertmanager**: active alerts. `Watchdog` always fires on purpose; it
  proves the alert pipeline works.

Alerts and what to do about them: [redirect SLO runbook](slo-redirect-availability.md).
Backups and restores: [Postgres backup runbook](postgres-backup-restore.md).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `kubectl`: "exec plugin ... failed" or 401 | OCI token expired | Step 1, then retry (the tunnel can stay up) |
| `kubectl`: "connection refused" on 127.0.0.1:6443 | Tunnel not running | Step 2 |
| `kubectl`: hangs, then i/o timeout | Tunnel stale: the process is alive but the connection is dead | Ctrl+C the tunnel, run it again. If Ctrl+C wasn't possible, delete the leftover session in Console → Bastion |
| Tunnel script: Bastion refuses the connection | Your public IP changed | Update `bastion_client_cidr` in `terraform/oke/terraform.tfvars`, `terraform apply` |
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

Ctrl+C the port-forwards and the tunnel. Bastion sessions also expire on their
own (3 h), so a forgotten one costs nothing.
