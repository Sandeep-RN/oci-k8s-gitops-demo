# Runbook: redirect SLO burn-rate alerts

For `RedirectErrorBudgetBurnFast`, `RedirectErrorBudgetBurnSlow` (critical) and
`RedirectErrorBudgetBurnTicket` (warning), and for the synthetic probe's
`RedirectProbeNoAnswer` (critical) and `RedirectProbeMissing` (warning). The
rules, tests and dashboard live in the gitops repo:
`apps/link-shortener/base/slo-rules.yaml`, `tests/prometheus/*.test.yaml`,
`dashboards/slo-redirect.json`.

## What the alert means

The SLO (ADR 0008): over a rolling 7 days, **99.5% of redirects
(`GET /{code}`) are not 5xx**. That leaves an error budget of 0.5%. The alerts
fire when errors spend that budget too fast:

| Alert | Fires when | Budget spent | Act |
|---|---|---|---|
| Fast | > 7.2% errors over 1 h *and* 5 min | 8.6% of the week's budget in an hour; all of it in under 12 h | Now |
| Slow | > 3% errors over 6 h *and* 30 min | 21% in 6 h; all of it in about a day | Now |
| Ticket | > 1.5% over 1 day and 2 h, or > 0.5% over 3 days and 6 h | the budget will run out within the week | Working hours |

The short window means an alert clears soon after the errors stop. An alert
also needs at least 20 redirects in its long window, so a handful of failed
requests at near-zero traffic doesn't page anyone.

Most of the traffic, while real visitors are few, comes from the in-cluster
probe (ADR 0019): `GET /Probe00` on the backend Service every 30 s, from the
blackbox exporter in `monitoring`. `Probe00` is not a stored code, so a healthy
app answers 404.

A 404 for an unknown code is not an error. Only 5xx counts. In this app that
means 503 (storage unavailable, which is how the app fails fast during a
database outage, #26) or 500 (a bug).

## Triage (5 minutes)

Access: [access runbook](access.md) (OCI login, tunnel, port-forwards).

1. **Grafana → "Link shortener / Redirect SLO".** The by-status panel shows
   whether it is 503s or 500s, and since when.
2. **Which status?**
   - **503**: the app can't reach Postgres. Go to *Database*.
   - **500**: a bug. Go to *Recent deploy*.
3. **Is everything failing or only part?** If the error ratio is about 50%,
   one of the two backend pods is likely bad:

   ```bash
   kubectl -n link-shortener get pods -o wide
   kubectl -n link-shortener logs <pod> --since=15m | tail -50
   ```

## Database (503)

```bash
kubectl -n link-shortener get pod postgres-0 -o wide        # Running? Restarts?
kubectl -n link-shortener describe pod postgres-0 | tail -20 # events: volume attach, OOM, scheduling
kubectl -n link-shortener logs postgres-0 --tail=50
kubectl -n link-shortener get pvc                            # Bound?
```

- **Restarting or rescheduled:** a block-volume reattach to another node takes
  a minute or two. The app answers 503 within about 2 s meanwhile and recovers
  on its own (verified in #26).
- **Pending:** read the events. A volume can only attach to a node in the same
  availability domain (there is one AD here).
- **Running but the app still returns 503:** check the credentials Secret and
  the pool settings (`PG*` env vars in the Deployment, ConfigMap `app-config`).

## Probe alerts

**`RedirectProbeNoAnswer`**: for 3 minutes the probe got no HTTP answer at all
(refused, reset or over 4 s). The app never saw these requests, so the
burn-rate alerts may stay quiet. Usually no backend pod is ready:

```bash
kubectl -n link-shortener get pods -l app.kubernetes.io/name=backend -o wide
kubectl -n link-shortener get endpointslices -l kubernetes.io/service-name=backend
kubectl -n link-shortener describe deploy backend | tail -20   # rollout stuck? image pull?
```

A probe that gets 503s does not fire this alert; the burn-rate alerts handle
that case (go to *Database*).

**`RedirectProbeMissing`**: the probe has not run for 15 minutes, so quiet
periods are unmonitored. Not urgent.

```bash
kubectl -n monitoring get deploy blackbox-exporter
kubectl -n monitoring logs deploy/blackbox-exporter --tail=20
kubectl -n link-shortener get probe redirect
kubectl -n argocd get application blackbox-exporter
```

The Prometheus UI's *Targets* page shows the `redirect-probe` job and its last
error.

## Recent deploy (500)

```bash
kubectl -n argocd get applications                  # what synced, and when
kubectl -n link-shortener get deploy backend -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Compare the time the errors started with the last tag-bump PR in the gitops
repo. To roll back, **revert that bump PR in Git**; ArgoCD rolls the old image
back out. Don't `kubectl set image` or `rollout undo`: ArgoCD would revert it
(self-heal).

## After it's fixed

- The fast and slow alerts clear within about 5 or 30 minutes of the errors
  stopping (their short window).
- Check "Error budget left" on the dashboard. If little is left, hold risky
  changes until it recovers. The budget refills as bad hours age out of the
  7-day window.
- If the cause was new or interesting, write it up (and offer it as a
  `post-idea`).

## Testing the alert on purpose

Covered by promtool unit tests in CI. On a live cluster, it needs **one
sustained outage**. Short blips are not enough, and correctly so: the fast
alert also needs more than 7.2% errors over the last *hour*, and three
15-second outages are only about 2.5% of an hour's requests (tested in #53;
the weekly budget is about 50 minutes of downtime, so blips should not page).

Proven method (#53, 2026-10-25: fast alert firing about 7 minutes after the
outage began, Discord firing and resolved messages):

1. Send steady traffic through the public load balancer: a redirect every
   0.5 s, starting about 2.5 minutes before the outage, which also clears the
   traffic floor.
2. Make Postgres refuse the app's database for 5 minutes. It keeps running,
   so liveness passes and nothing restarts, and nothing ArgoCD manages changes:

   ```bash
   pg() { kubectl -n link-shortener exec postgres-0 -- sh -c "psql -X -At -U \"\$POSTGRES_USER\" -d postgres -c \"$1\""; }
   pg 'ALTER DATABASE linkshortener ALLOW_CONNECTIONS false'
   pg "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE datname = 'linkshortener'"
   # ... 5 minutes ...
   pg 'ALTER DATABASE linkshortener ALLOW_CONNECTIONS true'   # ALWAYS run this
   ```

   Script it with an `EXIT` trap that runs the last line, so an interrupted
   test can never leave the database closed. The app's existing sessions keep
   working until they are terminated, so the outage starts at the
   `pg_terminate_backend` step, not the `ALTER`.
3. Watch Prometheus → Alerts: `RedirectErrorBudgetBurnFast` goes pending once
   both windows pass 7.2%, fires 2 minutes later, and resolves a few minutes
   after recovery. Slow and ticket follow, and are expected.

Don't use these instead:

- **Deleting `postgres-0`:** each delete is only about 15 s of errors.
- **Scaling the StatefulSet:** ArgoCD reverts it (self-heal).
- **`pkill -STOP postgres`:** the kernel ignores a SIGSTOP sent from inside a
  container to its PID 1 (the postmaster), so new connections still work. The
  app loses about 2 requests and recovers, and the background workers stay
  frozen until you run `pkill -CONT postgres`.

Record the result in an issue.
