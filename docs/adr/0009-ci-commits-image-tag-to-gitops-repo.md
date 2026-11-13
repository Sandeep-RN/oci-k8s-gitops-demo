# 0009. CI opens an auto-merging tag-bump PR in the gitops repo

Status: Accepted (2026-10-21, revised 2026-10-21 after review). The scan
policy line and its consequence were added on 2026-11-13; they record what
the app's `ci.yml` has done since the pipeline was built.

## Context
A code change must reach the cluster with no manual step. Options were Argo CD Image Updater or having CI update the gitops repo. The gitops repo's `main` is protected and requires PRs (ADR 0011), so CI cannot push to it directly.

## Decision
GitHub Actions in the app repo builds, tests and scans the image, pushes it to GHCR with an immutable tag (the git SHA), then opens a pull request in the gitops repo that changes the tag, with auto-merge enabled once the gitops repo's checks pass. It authenticates with a fine-grained token limited to that one repo. ArgoCD syncs after the merge.

Scan policy: Trivy fails the build on HIGH or CRITICAL vulnerabilities **that have a fix** (`severity: HIGH,CRITICAL`, `ignore-unfixed: true`), with no ignore file. A failed scan stops the job before the image is pushed, so nothing is deployed. A vulnerability with no fix cannot be removed by rebuilding the image; blocking on it would stop every deploy until upstream ships a fix, so it is reported but does not block.

## Consequences
- Every deployment is a reviewable, merged PR, consistent with the protected `main`.
- One extra secret (the token) to protect and rotate.
- The gitops repo needs at least one fast check (for example manifest validation) for auto-merge to wait on.
- Unfixed HIGH or CRITICAL vulnerabilities can ship. They block nothing until a fix exists; then the next build fails until the image is rebuilt on the fixed version.
- The scan runs on a local amd64 build. The multi-arch image that is pushed (amd64 and arm64; the node runs arm64) is built afterwards and is not scanned itself (roadmap).

## At scale
A GitHub App instead of a personal token, signed images (cosign) verified by an admission policy, and promotion between environments.
