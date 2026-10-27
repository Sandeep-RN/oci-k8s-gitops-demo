# Glossary

Terms used across the three repos. Use these words in issues, specs and ADRs.

- **Demo repo**: `oci-k8s-gitops-demo`. Terraform for OCI, docs, ADRs, runbooks, and the issue tracker for all three repos.
- **App repo**: `oci-k8s-gitops-demo-app`. Application code, Dockerfiles and CI.
- **Gitops repo**: `oci-k8s-gitops-demo-gitops`. Kubernetes manifests and ArgoCD Applications; the source of truth for the cluster.
- **Node**: the single Always Free A1 instance running k3s.
- **OKE target**: the short-lived, multi-node managed Kubernetes cluster on trial credit that runs the same gitops repo through `overlays/oke`; torn down by 2026-11-15 (ADR 0015). Not the node.
- **Always Free**: Oracle's permanently free resource limits (2 OCPU / 12 GB of A1), the final target for the demo.
- **Trial credit**: the 30-day $300 credit, used only for disposable experiments.
- **Sync**: ArgoCD making the cluster match the gitops repo.
- **Tag bump**: the auto-merging PR CI opens in the gitops repo with a new image tag.
- **Synthetic traffic**: the in-cluster k6 load CronJob.
- **Hairpin**: traffic from inside the cluster to the public hostname that loops out to the NLB and back; avoided for probes.
- **Redirect path**: the request that turns a short link into a redirect; the thing the SLO measures.
- **SLI**: a measured indicator of service health. Two here: availability (share of redirects that succeed) and latency (share under 200 ms).
- **SLO**: the reliability target for the redirect path over a rolling 7 days: 99.5% succeed, 95% under 200 ms.
- **Error budget**: the allowed failures implied by the SLO.
- **Burn rate**: how fast the error budget is being used; multi-window alerts fire when it is too high.
- **External probe**: the scheduled GitHub Actions check of the public URL, measuring what a real user sees.
- **Runbook**: the written steps for what to check and do when an alert fires.
- **Core / Stretch**: scope tiers from ADR 0011.
- **Edge**: everything between the internet and the backend Service: DNS, the NLB, Traefik, TLS, the rate limit (ADR 0020).
- **Link-creation token**: a named secret token required to create a short link; redirects need none (ADR 0020).
- **Creation mode**: `token` (now) or `open` (reserved; refuses to start until abuse safeguards exist).
- **Cutover**: the two-step move from the Flexible LB address to `demo.sandeeprn.in` (ADR 0020).
