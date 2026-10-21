# 0003. Terraform state in OCI Object Storage (native oci backend)

Status: Accepted (2026-10-21, revised 2026-10-21 after review)

## Context
Local state can be lost and does not show production habits. The repo is public, so state (which contains OCIDs and IPs) must never be committed. The S3-compatible backend needs Customer Secret Keys (max 2 per user) and its locking on OCI is uncertain.

## Decision
- Use Terraform's native `oci` backend (documented at developer.hashicorp.com/terraform/language/backend/oci). It supports state locking through Object Storage's `If-None-Match` header and uses the same API-key auth as the OCI provider, so no extra keys.
- The bucket is created once by hand (helped by a wizard script) to avoid the chicken-and-egg problem, with **object versioning enabled** so earlier state versions can be restored.
- Bucket name, namespace and region go in a git-ignored `backend.hcl`, passed with `terraform init -backend-config=backend.hcl`. A placeholder `backend.example.hcl` is committed.
- Keep state tiny; Always Free Object Storage is 20 GB.

## Consequences
- State is outside git, locked during runs, versioned, and survives a lost laptop.
- Never paste `terraform plan` output into public issues or PRs; it can contain OCIDs and IPs.

## At scale
Per-environment state, access through IAM policies and short-lived credentials rather than user API keys.
