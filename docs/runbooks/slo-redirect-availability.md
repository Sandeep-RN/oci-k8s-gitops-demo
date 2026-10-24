# Runbook: redirect SLO burn-rate alerts

For `RedirectErrorBudgetBurnFast`, `RedirectErrorBudgetBurnSlow` (critical) and
`RedirectErrorBudgetBurnTicket` (warning). The rules, tests and dashboard live
in the gitops repo: `apps/link-shortener/base/slo-rules.yaml`,
`tests/prometheus/slo-redirect.test.yaml`, `dashboards/slo-redirect.json`.

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

Covered by promtool unit tests in CI. On a live cluster, a Postgres outage
under steady traffic makes the fast alert fire:

1. Send steady traffic: a redirect every 0.5 s for 15 minutes, which is enough
   requests to clear the traffic floor.
2. Delete `postgres-0` three times, each time as soon as it is Running again
   (`kubectl -n link-shortener delete pod postgres-0`). One delete gave about
   25 s of 503s in the #26 test, which is borderline for keeping the 5-minute
   ratio above 7.2% for the 2-minute `for`; three in a row clear it. Don't
   scale the StatefulSet: ArgoCD would undo it (self-heal) and muddy the test.
3. Watch Prometheus → Alerts: `RedirectErrorBudgetBurnFast` goes pending,
   then firing after 2 minutes.

Record the result in the SLO issue (#53).
