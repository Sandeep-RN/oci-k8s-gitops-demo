# Glossary

Terms used across the three repos. Use these words in issues, specs and ADRs.

- **Demo repo**: `oci-k8s-gitops-demo`. Terraform for OCI, docs, ADRs, runbooks, and the issue tracker for all three repos.
- **App repo**: `oci-k8s-gitops-demo-app`. Application code, Dockerfiles and CI.
- **Gitops repo**: `oci-k8s-gitops-demo-gitops`. Kubernetes manifests and ArgoCD Applications; the source of truth for the cluster.
- **Node**: the single Always Free A1 instance running k3s.
- **OKE target**: the short-lived, multi-node managed Kubernetes cluster on trial credit that runs the same gitops repo through `overlays/oke`; torn down by 2026-11-15 (ADR 0015). It served the site until 2026-11-12; its teardown is issue #13. Not the node.
- **Always Free**: Oracle's permanently free resource limits (2 OCPU / 12 GB of A1), the final target for the demo.
- **Trial credit**: the 30-day $300 credit, used only for disposable experiments.
- **Quota policy**: an OCI rule that refuses any create request that would push usage past a set amount; the only real spending cap here (ADR 0021).
- **Budget**: an OCI spend tracker that emails when actual or forecast spend crosses a threshold, evaluated about every 24 hours. An alarm, not a cap (ADR 0021).
- **Sync**: ArgoCD making the cluster match the gitops repo.
- **Tag bump**: the auto-merging PR CI opens in the gitops repo with a new image tag.
- **Synthetic traffic**: the requests of the in-cluster blackbox probe (ADR 0019).
- **Hairpin**: a pod reaching the service's own public hostname, so the traffic goes out through the cloud's gateway and back in; avoided for probes, and not tested on k3s (ADR 0022).
- **Redirect path**: the request that turns a short link into a redirect; the thing the SLO measures.
- **SLI**: a measured indicator of service health. Two here: availability (share of redirects that succeed) and latency (share under 200 ms).
- **SLO**: the reliability target for the redirect path over a rolling 7 days: 99.5% succeed, 95% under 200 ms.
- **Error budget**: the allowed failures implied by the SLO.
- **Burn rate**: how fast the error budget is being used; multi-window alerts fire when it is too high.
- **External probe**: the scheduled GitHub Actions check of the public URL, measuring what a real user sees.
- **Runbook**: the written steps for an operation: an alert, a restore, access, the bootstrap, the cost guardrails.
- **Core / Stretch**: scope tiers from ADR 0011.
- **Edge**: everything between the internet and the backend Service: DNS, the NLB on OKE or the node's own IP on k3s, Traefik, TLS, the rate limit (ADR 0020, 0022).
- **ServiceLB**: k3s's built-in load balancer for `LoadBalancer` Services. It needs no cloud load balancer and publishes the node's address as the Service's address. On OCI that is the private IP, because the node never sees its public one (ADR 0022).
- **externalTrafficPolicy**: a Service setting. `Cluster` may forward to any node and hides the client's IP; `Local` keeps traffic on the receiving node and keeps the client's IP. k3s's Traefik uses `Local` so the rate limit sees real clients (ADR 0022).
- **Link-creation token**: a named secret token required to create a short link; redirects need none (ADR 0020).
- **Creation mode**: `token` (now) or `open` (reserved; refuses to start until abuse safeguards exist).
- **Cutover**: the two-step move from the Flexible LB address to `demo.sandeeprn.in` (ADR 0020).
- **DNS switch**: the move of `demo.sandeeprn.in` from OKE to k3s on 2026-11-12, done by removing the OKE Ingress in a pull request (ADR 0022).
