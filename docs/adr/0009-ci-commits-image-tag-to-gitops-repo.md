# 0009. CI opens an auto-merging tag-bump PR in the gitops repo

Status: Accepted (2026-10-21, revised 2026-10-21 after review)

## Context
A code change must reach the cluster with no manual step. Options were Argo CD Image Updater or having CI update the gitops repo. The gitops repo's `main` is protected and requires PRs (ADR 0011), so CI cannot push to it directly.

## Decision
GitHub Actions in the app repo builds, tests and scans the image, pushes it to GHCR with an immutable tag (the git SHA), then opens a pull request in the gitops repo that changes the tag, with auto-merge enabled once the gitops repo's checks pass. It authenticates with a fine-grained token limited to that one repo. ArgoCD syncs after the merge.

## Consequences
- Every deployment is a reviewable, merged PR, consistent with the protected `main`.
- One extra secret (the token) to protect and rotate.
- The gitops repo needs at least one fast check (for example manifest validation) for auto-merge to wait on.

## At scale
A GitHub App instead of a personal token, signed images (cosign) verified by an admission policy, and promotion between environments.
