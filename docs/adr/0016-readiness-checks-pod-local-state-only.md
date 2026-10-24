# 0016. Readiness checks pod-local state only, not the shared database

Status: Accepted (2026-10-25)

## Context
`/readyz` returned 503 while Postgres was unreachable, so Kubernetes took the pod out of the Service until the database was back (the fail-fast work in #26 kept this). A live outage test (#53) showed what that does when every replica shares the database:

- Both backends failed readiness together and left the Service at the same moment. With zero endpoints, the load balancer path refused connections in about 0.2 s.
- 8 of the 24 failed requests got no HTTP response at all, instead of the fast 503 the app is built to return.
- Those requests never reached the app, so the request metrics never counted them. The server-side error ratio peaked at 6% while clients saw about 10%, and the fast-burn SLO alert (ADR 0008) stayed silent.
- Pods rejoined only after their next successful probe, a few seconds after Postgres recovered.

Removing a pod from rotation only helps when another pod can serve the request. A dependency that every replica shares offers no such pod.

## Decision
- `/readyz` checks only what is local to the pod. Today that is "this pod's connection pool is open", which also takes the pod out of the Service during shutdown.
- Database reachability is no longer a readiness signal. During a database outage, pods stay in the Service and answer fast 503s (pool timeout about 2 s, unchanged from #26). Every such response is counted by the SLI and drives the burn-rate alerts.
- The schema is created at startup when the database is reachable, otherwise by the first request that reaches it (still under the advisory lock).
- Liveness (`/healthz`) is unchanged: it never checks dependencies.

## Consequences
- Outages are visible to the SLO and alerting exactly as users see them (503s), and recovery is immediate when the database returns, with no probe-period lag.
- A pod is "ready" even when it cannot serve successful responses. Readiness means "send me traffic", not "everything works". Database health is visible through the SLO (symptom) and, for diagnosis, the standard Kubernetes alerts on `postgres-0` (#63 tracks an optional `db_up` gauge).
- Rollouts no longer wait for the database: a new pod becomes ready during a database outage. That is acceptable here, since old and new pods would fail the same way.
- With no traffic there are no 503s and no SLO alert; the external probe (#55) provides the steady traffic.

## At scale
The same rule holds: readiness reflects per-instance state (warm caches, local config loaded, draining). Shared dependencies are handled with timeouts, circuit breakers and graceful degradation. A dependency that only *some* replicas reach (a zone-local cache, a sharded store) can be a readiness signal, because other replicas can take the traffic.
