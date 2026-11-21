# k3s live checks: second client, memory, volumes (2026-11-21)

Evidence for [#190](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/190)
and [#141](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/141). These
ran on the single-node k3s cluster (ADR 0001, 0022) the morning after the
rebuild proof ([#57](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/57)),
so the cluster was between about 1 and 10 hours old. Everything except the
rate-limit flood was read-only. Addresses are left out.

## 1. A second client during another client's burst (ADR 0022)

The claim: the rate limit is per client (20 requests a second, burst 40), so one
client being throttled does not affect another.

**Method.** One client (a laptop on home Wi-Fi) sent a flood to `/healthz`. A
second client (a phone on mobile data, Wi-Fi off, so a different network)
loaded the same page by hand during the flood. The flood is one `curl` process
with 600 URLs, `--parallel --parallel-immediate --parallel-max 150`, repeated
back to back for 60 seconds, like the burst in `scripts/verify-public-url.sh`.

| Observation | Result |
|---|---|
| Laptop, first round of 600 (21 s) | 333 x 429, 234 x 200, 33 x no answer |
| Laptop, the whole run (first round plus 60 s) | 1410 x 429, 856 x 200, 134 x no answer (`000`) |
| Phone, reloaded every 3 to 5 seconds from the moment the laptop was throttled until the flood ended | The normal page every time (about 12 to 20 reloads, not counted exactly) |
| Laptop 10 s after the flood | 200 |
| Traefik, entrypoint, 10-minute window | 1484 x 429; the backend service received none of them (the middleware rejects first) |
| Traefik 5xx, pod restarts, alerts | None; only `Watchdog` firing; node CPU 9% |

**What this shows:** while one address was rejected with 429 over and over,
another address on another network was still served. That is what a per-client
limit means.

**What it doesn't show:**
- Traefik's counters cannot be split by client, so the phone's result is the
  owner's observation, not a server-side count.
- The 134 requests with no answer are connections that never completed. Traefik
  shows no 5xx and no restart, so the likely cause is the laptop opening 150
  parallel TLS connections, but that was not isolated.
- The phone's and the laptop's public addresses were not compared (that would
  print them); different networks were the control.

**A first attempt was inconclusive and is kept here on purpose.** It sent 60
requests at a time without `--parallel-immediate`: only 240 requests in 60
seconds (about 4 a second, below the limit), no 429 at all, so the phone's
normal pages proved nothing. The second attempt checks that the laptop is
throttled before the phone is used.

## 2. Memory against the estimates (#141)

The estimates are from the monitoring change in the gitops repo (PR #58).
Measured with `kubectl top` and Prometheus on the k3s node (2 OCPU / 12 GB).

| | Estimate | At about 1 h | Peak over about 10 h |
|---|---|---|---|
| Node memory | n/a | 4036Mi, 33% (CPU 10%) | n/a |
| Prometheus | 500 to 700Mi | 331Mi | 390Mi |
| ArgoCD, 7 pods | about 700Mi | about 535Mi | controller 518Mi, repo server 80Mi, server 43Mi |
| Sealed Secrets controller | about 30Mi | 10 to 16Mi | 21Mi |

All are at or under their estimates. Prometheus memory grows as its head data
fills, so 390Mi is a floor, not a steady state: look again after a few weeks.

- **Traefik ServiceMonitor:** the target `traefik-metrics` in `kube-system` is
  up.
- **Volume stats:** `kubelet_volume_stats_*` exists, **but both volumes report
  the same capacity (about 50.9 GB) and the same used bytes (about 11.8 GB)**,
  although they request 5Gi (Postgres) and 10Gi (Prometheus). That is the node's
  filesystem: `local-path` volumes are plain directories, so there is no
  per-volume size to report. A per-volume "disk full" alert would be
  misleading; alert on the node's filesystem instead ([#140](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/140)).
  The series also appears twice (`job="kubelet"` and `job="apiserver"`), so
  filter by job.

## 3. Requests and limits for ArgoCD and Sealed Secrets

Upstream sets none, so all 8 pods were `BestEffort`: invisible to the
scheduler, and the first to be evicted when the node runs short of memory.
Gitops PR #75 (merged 2026-11-21) adds them as Kustomize patches, sized from
the peaks above: requests near the peak, memory limits about twice the peak or
more, no CPU limits.

| Workload | Memory request / limit | CPU request |
|---|---|---|
| argocd-application-controller | 512Mi / 1Gi | 50m |
| argocd-repo-server | 128Mi / 512Mi | 20m |
| argocd-server | 64Mi / 256Mi | 10m |
| redis, dex, applicationset, notifications | 32Mi / 128Mi each | 10m each |
| sealed-secrets-controller | 32Mi / 128Mi | 10m |

Checked after the merge, read-only: all 8 pods replaced and `Burstable`, the
values in the live pod specs equal the table, 0 restarts, 10 of 10 Applications
Synced and Healthy, 8 of 8 SealedSecrets `Synced=True`, 1 sealing key, only
`Watchdog` firing, `/healthz` 200. Requests total about 0.86Gi and limits about
2.4Gi (overcommit on one node, on purpose). A limit that is too tight would show
up as `OOMKilled` restarts of the application controller during a sync.

## 4. Two questions

- **Does deleting a PVC delete the data on `local-path`?** By its settings, yes:
  the `local-path` StorageClass and both volumes have reclaim policy `Delete`,
  so deleting a claim removes the volume and its directory. *Read from the
  cluster; no claim was deleted to test it.* (This is why the app's Namespace is
  marked so ArgoCD never deletes it: roadmap item 2.)
- **Does k3s enforce NetworkPolicies?** *Not proven.* The evidence: k3s embeds a
  NetworkPolicy controller by default, the node's k3s arguments do not disable
  it, and ArgoCD's own 7 NetworkPolicies are applied and its pods work. None of
  that shows a policy blocking traffic. A real test needs a throwaway namespace
  with a deny policy, which is a change to the cluster; it belongs to roadmap
  item 7.

## What was not run

The "Not yet run on k3s" lists in the other runbooks (access, edge,
postgres-backup-restore, slo-redirect-availability, sealed-secrets) are
unchanged: nothing here ran those commands. Only the three snippets in the
k3s-bootstrap banner were run (read-only, against k3s, on 2026-11-21): the
`BACKUP_CLUSTER` jsonpath printed `k3s`, the alerts query listed only
`Watchdog`, and `probe_success` ended in `1`. That runbook's note was removed.
Two details: the jsonpath was run with the k3s kubeconfig (the runbook's
snippet names the source cluster), and the `kubectl` calls ran as written but
the `grep -oE` extraction was done with the same patterns in PowerShell, because
a bash shell was not available that day.
