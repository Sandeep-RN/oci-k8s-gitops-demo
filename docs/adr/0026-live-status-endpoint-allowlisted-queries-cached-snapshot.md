# 0026. A live status endpoint: allowlisted queries, a cached snapshot, no public admin UIs

Status: Accepted (2026-11-23). Decided by the owner after the design note of the same day; built in demo #230. Keeps ADR 0014 in force.

## Context
The public site (demo.sandeeprn.in) shows text and links. The platform behind it has live data worth showing: the redirect SLO and its error budget (ADR 0008), traffic, node load, which commit is running and whether Argo CD is in sync (ADR 0023). The first idea was to link Grafana, Prometheus and Argo CD from the site.

ADR 0014 decided that no admin UI gets a public Ingress. Nothing in this change weakens that: Grafana's query explorer and Argo CD's login and API are a large attack surface for a demo, and Prometheus has no authentication at all.

Facts read from the live cluster on 2026-11-23:
- Prometheus (`kps-prometheus.monitoring:9090`) has no authentication and every pod can reach it. There is no NetworkPolicy in `link-shortener` or `monitoring`, so the backend can already reach it and no new policy is needed for connectivity.
- The SLO numbers already exist as recording rules (`slo:redirect_error_budget:remaining_ratio7d` and others).
- The running commit is the image tag (`kube_pod_container_info`), the last deploy is `kube_pod_start_time`.
- Argo CD exposes metrics Services, but nothing scrapes them, so Prometheus has no `argocd_*` series.
- The backend has 2 replicas, a 128Mi limit and uses about 52 MiB. The node is at 44% memory.
- The landing page has a CSP of `default-src 'none'; style-src 'unsafe-inline'`: no scripts, no fetch.

## Decision
- **`GET /api/status` in the link-shortener backend** returns one JSON object of rounded aggregates: SLO (target, error budget, 7-day availability and latency), requests per second, node CPU and memory, node network bytes per second (labelled as all traffic), running pod count, running commit, last deploy time, and Argo CD synced and healthy. No labels, IPs or pod names.
- **Every PromQL query is a constant in code.** No request data ever reaches a query. A test asserts the exact set of queries.
- **The request path never calls Prometheus.** A background single-flight refresher runs every 30 s (2 s per query, 5 s per refresh) and writes an in-memory snapshot. The endpoint reads the snapshot.
- **Failure keeps the last good snapshot.** It is marked `stale` after 90 s. The endpoint answers 503 only if no refresh ever succeeded. Values are parsed strictly as numbers and the Prometheus response size is capped.
- **Off unless configured.** The URL comes from `STATUS_PROMETHEUS_URL` in the ConfigMap. Unset means `/api/status` is 404, so local runs and tests are unaffected and the app can merge before the platform turns it on.
- **Not part of readiness or liveness.** ADR 0016 stands: readiness checks only pod-local state, so a Prometheus outage can never remove a backend pod.
- **A ServiceMonitor for Argo CD** (gitops) so that `argocd_app_info` exists. The status page shows its sync and health.
- **The landing page gets one live strip.** It is progressive enhancement: the page works without it. The CSP gains one script hash (computed at startup, as for the oncall page) and `connect-src 'self'`; `default-src` stays `'none'`. The script writes only with `textContent`.
- **No links to admin UIs.** The page links to the gitops repository and to the running commit on GitHub.

Rejected:
- **A public Grafana, Prometheus or Argo CD** (ADR 0014): attack surface, a query explorer, a login to protect.
- **A separate status pod.** Better isolation, but a second Deployment, image and Ingress path, and about 40 MiB, for a feature that is one small module. Revisit if the feature grows.
- **A CronJob that writes a snapshot ConfigMap.** No runtime coupling at all, but the data is only as fresh as the schedule, and it adds a Job and RBAC. Kept as the fallback if the in-app poller proves a problem.
- **Raw node network receive bytes as "traffic".** On 2026-11-23 the rate was 581 KB/s, almost all image pulls from the day's rollouts. The page shows requests per second and node transmit, labelled "node network, all traffic". A per-visitor byte counter would be an app change of its own.
- **A NetworkPolicy in this change.** Limiting the backend to Postgres, DNS and Prometheus is worthwhile hardening but risks breaking probes and scrapes. It is a separate issue.

## Consequences
- Visitors see live numbers; the admin UIs stay behind the tunnel.
- The redirect service gains a small background task and a dependency path to Prometheus. Failures stay inside that task. Each replica polls, about 14 small queries per 30 s in total at 2 replicas.
- The landing page is no longer script-free. The CSP allows exactly one script hash.
- A compromised backend could already query Prometheus, since it has no authentication and no NetworkPolicy; this change does not widen that.
- Cost: nothing outside Always Free. A few MiB per replica; the Argo CD ServiceMonitor adds tens of series.
- Order of rollout: the app merges with the feature off; a gitops change with the ConfigMap value and the ServiceMonitor turns it on.
- Later, not decided here: history charts built from fixed range queries, on the same allowlist pattern. That needs its own decision.

## At scale
- Each replica polls, so queries grow with replicas. At tens of replicas use one collector or a separate status service.
- Prometheus without authentication and without NetworkPolicy is acceptable for a one-node demo, not for a shared cluster.
- Behind a CDN the per-client rate limit needs the real client address header; today the site is DNS only.
