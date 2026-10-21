# 0011. Pull-request workflow and core versus stretch scope

Status: Accepted (2026-10-21, revised 2026-10-21 after review)

## Context
Time is limited (about 10-15 hours a week for 4 weeks) and the engineer is new to parts of the stack. The git history and Actions tab are part of the portfolio.

## Decision
- Every change goes through a pull request, with small branches, a protected `main`, and CI required to pass before merging. Automated tag bumps follow the same rule (ADR 0009).
- Work is tracked as GitHub Issues in this repo, one milestone per phase.
- **Core:** Terraform infra, k3s, app, CI with Trivy, ArgoCD, TLS, Postgres with tested backups, dashboard, SLO burn-rate alerts, external probe, runbook.
- **Stretch:** NetworkPolicies, Tailscale, a GitHub App for the tag bump, Loki.
- If time runs short, cut in this order: HPA, k6 load test, game-day, blog post. These cost the most time for the least reliability evidence. TLS, backups and Trivy stay in core.

## Consequences
- The history reads like a real team workflow.
- Scope has a clear cut line that protects the strongest evidence.

## At scale
Required reviewers, CODEOWNERS, release branches and change-management gates.
