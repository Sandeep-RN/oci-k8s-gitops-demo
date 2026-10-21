# 0009. CI commits the image tag to the gitops repo

Status: Accepted (2026-10-21)

## Context
A code change must reach the cluster with no manual step. Options were Argo CD Image Updater or having CI update the gitops repo.

## Decision
GitHub Actions in the app repo builds, tests and scans the image, pushes it to GHCR with an immutable tag (the git SHA), then commits the new tag to the gitops repo using a fine-grained token limited to that one repo. ArgoCD notices the commit and syncs.

## Consequences
- Every deployment is a reviewable git commit.
- One extra secret (the token) to protect and rotate.

## At scale
A GitHub App instead of a personal token, signed images (cosign) verified by an admission policy, and promotion between environments.
