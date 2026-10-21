# 0014. Admin UIs reachable only through port-forward

Status: Accepted (2026-10-21)

## Context
ArgoCD, Grafana, Prometheus and Alertmanager have web UIs. Exposing them publicly adds attack surface and login management for a demo.

## Decision
None of the admin UIs get a public Ingress. Access is `kubectl port-forward` over the SSH tunnel (ADR 0010). The README shows the dashboard and ArgoCD with screenshots or a read-only Grafana snapshot.

## Consequences
- Only the app is public.
- Viewers can't click around the dashboards live; screenshots and the demo video cover that.

## At scale
SSO-protected UIs behind an identity-aware proxy.
