# 0027. History charts: server-rendered SVG from a cached range-query snapshot

Status: Accepted (2026-11-24). Decided by the owner after the design note of the same day ("defaults OK"); built in demo #235. Extends ADR 0026 (same allowlist, cache and review bar); keeps ADRs 0014 and 0016 in force.

## Context
ADR 0026 put live numbers on the landing page. The owner also wants charts of how they moved over the last day and week, as the most informative public view of the platform that does not expose Grafana or Prometheus (ADR 0014).

Measured on the live cluster on 2026-11-24 (read-only, over the tunnel, through the Kubernetes API proxy, so each time includes kubectl's own overhead):
- Each planned `query_range` reads at most 10,694 samples and answers in under 0.9 s end to end. Answers are 3.5 KB (a 7-day series at 30 min), 10.5 KB (24 h at 5 min) and 24.8 KB (backend image tags over 7 days at 15 min, 16 series, 744 points). All are far below a 128 KiB cap.
- The charted SLO series are recording rules, so a 7-day range over them is cheap; an ad hoc `rate(...[7d])` over a 7-day range would not be.
- Prometheus keeps 8 days (`retention: 8d`), also capped at 8 GiB by size on k3s. The TSDB holds 806 MB for 3.9 days (about 210 MB a day), so time, not size, sets the retention. The oldest sample is only 92.8 hours old, so the 7-day charts are partly empty until about 2026-11-27.
- Prometheus has about 62,000 head series and 600 MiB resident (481 MiB working set on 2026-11-23; two different measures). Reads do not grow it.
- The traffic is about 0.03 requests a second and is mostly the in-cluster probe (ADR 0019), so the SLO lines are flat at 100%. The curves that move are node CPU and memory, pods running, and deploys.
- A page at `/status` cannot collide with a short link: a code is exactly 7 characters and `status` has 6.

## Decision
- **A public page `GET /status`, named "Platform metrics"** (the landing nav says "Metrics"; the URL stays `/status`; "live" is avoided because the page is a 5-minute snapshot; decided 2026-11-24) in the link-shortener backend, with charts of: SLO error budget, availability and latency-good (7 days, 30-minute steps); redirects per second (labelled as including the probe), node CPU and memory, node network transmit and pods running (24 hours, 5-minute steps); and deploy markers (ticks on every chart, from the backend image tag, 7 days, 15-minute steps).
- **Server-rendered SVG, no client JavaScript.** Python turns numbers into `<path>` data and the page is a cached string. Hover text is the native `<title>` element. The CSP stays `default-src 'none'; style-src 'unsafe-inline'`: no script, no hash to maintain, nothing to inject into. It works with scripts off and in `curl`. Only numbers and constants enter the markup; no label or string from Prometheus does. A commit tag is shown only after it matches a 40-hex pattern, as 7 characters.
- **A second constant allowlist, `RANGE_QUERIES`:** tuples of key, PromQL, window and step, all in code. No window, step or query comes from a request. Only recorded series or cheap node and kube-state series are allowed; a test asserts there is no ad hoc range selector over 1 hour.
- **Same client, same hardening as ADR 0026 (demo-app #43):** the watchdog, a total read deadline, no redirects, no proxies, strict numbers, finite only. The response cap for a range answer is 128 KiB, and a point-count cap per series and in total rejects an answer with more points than the window and step allow.
- **Refresh every 300 s** (`STATUS_HISTORY_REFRESH_SECONDS`, 60 to 900), single-flight, one query at a time, skipped while workers from an earlier refresh are alive. About 9 queries every 5 minutes per replica.
- **Off unless `STATUS_HISTORY=on` and `STATUS_PROMETHEUS_URL` are both set.** Off means `/status` is 404 and nothing runs. The gitops change that turns it on puts the variable in the Deployment env, not the ConfigMap (a ConfigMap change does not restart pods).
- **No 5xx for a missing snapshot.** Before the first successful refresh `/status` answers 200 with a "charts are warming up" page (the lesson of the ADR 0026 amendment: a public 5xx feeds the Traefik error alert). A chart whose query failed shows "no data"; a gap in a series is a gap, never a zero. The page prints its data age.
- **The page says what it does not have.** Each chart states its window and step, and a chart with less data than its window says how much it has. While history is shorter than 7 days, the 7-day charts say so.
- **Not in readiness or liveness** (ADR 0016). Two new label-free metrics: `status_history_refresh_failures_total` and `status_history_snapshot_age_seconds`.
- **Cache-Control `public, max-age=60`.** The existing 20 requests a second per-client limit applies.
- **The landing strip links to the charts only when the feature is on:** `/api/status` gains `history: true`, and the strip's script shows the link when it sees it, so the link never points at a 404.
- **No JSON history endpoint in v1.** The page is the only reader; one fewer surface to review.
- **An independent, read-only security review of the merged code comes before the gitops change that turns it on**, as for ADR 0026.

Rejected:
- **Client JavaScript drawing from a JSON endpoint:** a second hashed inline script, a JSON API to review and a bigger client attack surface, to get hover effects that `<title>` already gives.
- **A charting library:** a CDN breaks the CSP, and vendoring adds a dependency to audit.
- **A public Grafana, or Grafana public dashboards:** ADR 0014 and ADR 0026.
- **Pre-rendered images from a CronJob:** needs a headless browser in the cluster for a page we can draw in Python.
- **Ad hoc long-window `rate()` queries for the 7-day charts:** expensive, and the recording rules already hold the answer.

## Consequences
- Visitors see how the platform behaved over the last day and week, drawn from the platform's own Prometheus, with no new component and no admin UI exposed.
- The public site now has a second page whose content comes from Prometheus. Prometheus has no authentication, so the page treats every answer as hostile, as ADR 0026 does.
- Two replicas refresh at different moments, so a reload can show data up to 5 minutes apart. The page prints the data age.
- History is kept in memory per replica. After a restart the page shows "warming up" for a few minutes. The durable history is Prometheus itself.
- The charts will look partly empty until about 2026-11-27 (7 days of data) and flat where the SLO is perfect. The page is honest about both.
- Cost: nothing outside Always Free. About 100 KB of snapshot and an 83 KB page per replica (measured live on 2026-11-24; the hover targets cost most of it; limit 128 Mi, using 55 to 56); no change to Prometheus's memory or disk.
- Order of rollout: the app merges with the feature off; a gitops change with `STATUS_HISTORY=on` turns it on after the review.

## At scale
- Each replica refreshes alone; at tens of replicas use one collector or a separate status service.
- A 5-minute chart snapshot next to a 30-second strip can disagree briefly. Fine for a demo, not for an incident console.
- The history belongs in a time-series store, which here it already is. A status service that keeps its own history would duplicate Prometheus.
