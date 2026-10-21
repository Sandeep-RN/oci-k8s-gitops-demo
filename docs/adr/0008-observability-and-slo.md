# 0008. kube-prometheus-stack and a redirect SLO with a burn-rate alert

Status: Accepted (2026-10-21)

## Context
A generic "CPU above 80%" alert says little about user experience. The demo should show reliability thinking, and the node has limited memory.

## Decision
Deploy kube-prometheus-stack with trimmed resource limits and about 3 days of retention. Loki is out of core scope. Define one SLO on the redirect path: 99.5% of redirects succeed and 95% finish in under 200 ms, over 30 days. The custom alert is an error-budget burn-rate alert, delivered to Discord by Alertmanager (webhook stored as a SealedSecret), with a runbook. A small k6 CronJob and blackbox-exporter probes generate steady traffic, which also keeps the instance above Oracle's idle-reclamation thresholds.

## Consequences
- The dashboard and SLO have real data.
- Synthetic traffic must stay well under the load balancer's bandwidth limit.

## At scale
Multi-window burn-rate alerts per service, centralised logs and traces, on-call paging.
