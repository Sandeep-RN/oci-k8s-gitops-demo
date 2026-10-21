# 0011. Pull-request workflow and core versus stretch scope

Status: Accepted (2026-10-21)

## Context
Time is limited (about 10-15 hours a week for 4 weeks). The git history and Actions tab are part of the portfolio.

## Decision
- Every change goes through a pull request, with small branches, a protected `main`, and CI required to pass before merging.
- Work is tracked as GitHub Issues in this repo, one milestone per phase.
- **Core:** Terraform infra, k3s, app, CI, ArgoCD, TLS, Postgres with backups, monitoring dashboard, SLO alert, runbook, Trivy scan.
- **Stretch:** NetworkPolicies, Tailscale, a GitHub App for the tag bump, Loki.
- If time runs short, cut in this order: Trivy, backups, TLS.

## Consequences
- The history reads like a real team workflow.
- Scope has a clear cut line.

## At scale
Required reviewers, CODEOWNERS, release branches and change-management gates.
