# 0006. Sealed Secrets for secrets in Git

Status: Accepted (2026-10-21)

## Context
The gitops repo is public and ArgoCD syncs it, so secrets must be committed in encrypted form or kept out of band.

## Decision
Use Sealed Secrets. Secrets are encrypted with the cluster's public key and committed as `SealedSecret` manifests; only the cluster can decrypt them. Plain `Secret` manifests are git-ignored.

## Consequences
- Secrets live in Git, reviewed like any other change.
- Losing the controller's private key means re-sealing everything, so back it up out of band.

## At scale
External Secrets Operator with OCI Vault (or another secrets manager): central rotation, audit logs, and no encrypted secrets in Git.
