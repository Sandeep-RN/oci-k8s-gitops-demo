# 0019. An in-cluster synthetic probe feeds the redirect SLO

Status: Accepted (2026-10-27)

## Context
ADR 0008 planned an external probe, a scheduled GitHub Actions job hitting a short link "every few minutes", to cover two gaps in the app's own metrics:

1. **Quiet periods.** The burn-rate alerts need at least 20 redirects in their long window. With no visitors there are no requests, so an outage at night pages nobody.
2. **Requests that never reach the app.** If no backend pod is ready, the connection is refused before the app can count anything.

The probe was built (#55, demo repo `.github/workflows/probe.yml`) and every run passed. But GitHub's free scheduler ran it only about every 4 hours: 10 runs in 36 hours, 2 to 6 hours apart. Moving the cron from every 5 minutes to odd minutes made no visible difference (#78). That is too slow for either gap.

ADR 0008 also rules out in-cluster probes of the public hostname, because of hairpin routing through the load balancer (ADR 0004).

## Decision
- **Run the Prometheus blackbox exporter** in `monitoring` (Helm chart `prometheus-blackbox-exporter`, pinned, its own ArgoCD Application).
- **A `Probe` object requests `GET /Probe00` on the backend Service** (`backend.link-shortener.svc`) every 30 s, on every cluster. `Probe00` has the format of a code but is not stored. The app looks it up in Postgres and answers 404, which the SLI counts as good, so app and database are exercised with no seed data. A 302 is also accepted, in case a real link ever gets that code. Redirects are not followed.
- **The probe's requests are part of the SLI.** They go through the same route and middleware as user requests, so they are counted with them. That is the point: at 120 requests an hour, every SLO window has more than the 20-request floor.
- **Two alerts** (gitops `slo-rules.yaml`, group `redirect-probe`, promtool-tested):
  - `RedirectProbeNoAnswer` (critical, 3 min): no HTTP answer at all (`probe_http_status_code == 0`: refused, reset, or over 4 s). Probes that got a 5xx are left out on purpose. The app counts those, and the burn-rate alerts page for them, so a database outage pages once.
  - `RedirectProbeMissing` (warning, 15 min): the probe is not running, either the exporter is down (`up == 0`) or there is no probe at all (`absent`).
- **The GitHub Actions probe stays** as the slow outside check of the load balancer and internet path ("the whole cluster or LB is down"), at whatever rate GitHub runs it.

Rejected:
- **An outside cron service that starts the GitHub workflow.** It needs a GitHub token with Actions write access stored at a third party.
- **OCI Health Checks** (Oracle's hosted HTTP monitors from several regions). They would cover the LB and internet path every minute, but they are not Always Free, the final target.
- **Probing the public hostname from inside the cluster.** Hairpin routing (ADR 0008). On OKE the LB has only an IP, and public IPs are not committed.
- **Probing `/healthz` instead of a redirect.** It would not touch Postgres, and its requests are not on the SLO route, so the floor problem would remain.

## Consequences
- The SLO alerts work at night: a database outage now fires the fast-burn alert even with no visitors.
- **The SLI is mostly synthetic traffic** while real traffic is low. One probe request in every 30 s, from one place, through the Service. It measures "the redirect path works from inside the cluster", not what users on the internet see. The latency SLI also mostly measures the probe.
- The probe does not cover the cloud load balancer, the node ports, or DNS. Only the GitHub probe does, every few hours.
- If the whole cluster or the monitoring stack is down, the probe goes down with it and nothing pages. The `Watchdog` alert is routed nowhere today; a dead man's switch (an outside service that expects the Watchdog's heartbeat) would close this gap and is noted as a later idea.
- One more small Deployment (10m CPU, 32 Mi requested).

## At scale
- Probe from several outside locations (a hosted synthetic monitoring service, or blackbox exporters in other regions), not only from inside.
- Keep synthetic traffic out of the user-facing SLI (a label on probe requests, filtered in the recording rules) once real traffic is large enough to meet the floor, and give probes their own SLO.
- Probe a scripted user journey (create a link, then follow it) rather than one request.
