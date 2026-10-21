# Glossary

Terms used across the three repos. Use these words in issues, specs and ADRs.

- **Demo repo**: `oci-k8s-gitops-demo`. Terraform for OCI, docs, ADRs, runbooks, and the issue tracker for all three repos.
- **App repo**: `oci-k8s-gitops-demo-app`. Application code, Dockerfiles and CI.
- **Gitops repo**: `oci-k8s-gitops-demo-gitops`. Kubernetes manifests and ArgoCD Applications; the source of truth for the cluster.
- **Node**: the single Always Free A1 instance running k3s.
- **Always Free**: Oracle's permanently free resource limits (2 OCPU / 12 GB of A1), the final target for the demo.
- **Trial credit**: the 30-day $300 credit, used only for disposable experiments.
- **Sync**: ArgoCD making the cluster match the gitops repo.
- **Tag bump**: the commit CI makes to the gitops repo with a new image tag.
- **Redirect path**: the request that turns a short link into a redirect; the thing the SLO measures.
- **SLO**: the reliability target for the redirect path (99.5% succeed, 95% under 200 ms, over 30 days).
- **Error budget**: the allowed failures implied by the SLO.
- **Burn rate**: how fast the error budget is being used; the custom alert fires when it is too high.
- **Runbook**: the written steps for what to check and do when an alert fires.
- **Synthetic traffic**: scheduled k6 and blackbox probes that generate steady load and SLO data.
- **Core / Stretch**: scope tiers from ADR 0011.
