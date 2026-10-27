# 0008. kube-prometheus-stack and a redirect SLO with burn-rate alerts

Status: Accepted (2026-10-21, revised 2026-10-21 after review). The external probe's role is amended by ADR 0019 (2026-10-27).

## Context
A generic "CPU above 80%" alert says little about user experience. The demo should show reliability thinking, and the node has limited memory and disk.

## Decision
- Deploy kube-prometheus-stack with trimmed resource limits and about 8 days of retention. Loki is out of core scope.
- One SLO on the redirect path, over a **rolling 7 days**: 99.5% of redirects succeed (availability SLI) and 95% finish in under 200 ms (latency SLI). The request-duration histogram must include a 0.2 s bucket.
- Alerting uses **multi-window, multi-burn-rate** rules (a fast window for sudden outages, a slow one for gradual burn) on the availability SLI, delivered to Discord by Alertmanager (webhook stored as a SealedSecret), with a runbook. The latency SLI is shown on the dashboard.
- An **external probe** (a scheduled GitHub Actions job hitting `https://demo.sandeeprn.in` every few minutes) measures what a real user sees. An in-cluster k6 CronJob generates load for the dashboard and HPA.

## Consequences
- Seven days fits the retention a 12 GB node can afford; 30 days would need about four times the storage.
- In-cluster probes of the public hostname are avoided because of hairpin routing (ADR 0004).
- Idle reclamation: Oracle reclaims only if CPU, network and memory are all under 20%. Network is measured against the VM's own bandwidth, so synthetic traffic will never reach it; what actually keeps the node safe is memory, since this stack uses well over 20% of 12 GB. The load still helps CPU.
- The NLB has no 10 Mbps cap (that applies to the Flexible LB), but load tests stay modest anyway on a 2 OCPU node.

## At scale
SLOs per service, centralised logs and traces, on-call paging, error budget policies.
