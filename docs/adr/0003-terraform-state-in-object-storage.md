# 0003. Terraform state in OCI Object Storage

Status: Accepted (2026-10-21)

## Context
Local state can be lost and does not show production habits. The repo is public, so state (which contains OCIDs and IPs) must never be committed.

## Decision
Use an OCI Object Storage bucket as the Terraform backend (S3-compatible API). The bucket is created once by hand (helped by a wizard script) to avoid the chicken-and-egg problem. Keep state tiny; Always Free Object Storage is 20 GB.

## Consequences
- State is outside git and survives a lost laptop.
- Backend credentials are a secret and stay out of the repo.
- State locking is limited compared with other backends; this is fine for a solo project.

## At scale
A backend with proper locking and per-environment state, access controlled by IAM roles rather than keys.
