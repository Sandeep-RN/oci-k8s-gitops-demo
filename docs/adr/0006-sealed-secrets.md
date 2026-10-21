# 0006. Sealed Secrets for secrets in Git

Status: Accepted (2026-10-21, revised 2026-10-21 after review)

## Context
The gitops repo is public and ArgoCD syncs it, so secrets must be committed in encrypted form or kept out of band.

## Decision
- Use Sealed Secrets. Secrets are encrypted with the cluster's public key and committed as `SealedSecret` manifests; only the cluster can decrypt them. Plain `Secret` manifests are git-ignored.
- The controller adds a new sealing key every 30 days by default and keeps the old ones. Back up **all** sealing keys (selected by the label `sealedsecrets.bitnami.com/sealed-secrets-key`) out of band after each rotation, never into Git.
- Rebuild order: restore the sealing keys into the cluster first, then install the controller (or restart it), then let ArgoCD sync. This is part of the rebuild runbook.

## Consequences
- Secrets live in Git, reviewed like any other change.
- A rebuild without the backed-up keys breaks every committed SealedSecret; they would all need re-sealing.

## At scale
External Secrets Operator with OCI Vault (or another secrets manager): central rotation, audit logs, and no encrypted secrets in Git.
