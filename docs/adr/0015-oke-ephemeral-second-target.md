# 0015. OKE as a short-lived second deploy target on trial credit

Status: Accepted (2026-10-22)

## Context
The A1 node (ADR 0001) cannot be created yet: the home region reports "Out of host capacity". The $300 trial credit runs out around 2026-11-19 and is meant for disposable experiments. Deploying the same app to Oracle's managed Kubernetes (OKE) would make use of the credit, let GitOps work start before the node exists, and show something the single node cannot: several nodes, pods spread across fault domains, and a PodDisruptionBudget that holds during a drain (ADR 0001, "At scale").

The risk is that OKE becomes a second project that uses up the time and credit meant for the core scope (ADR 0011), or that it touches the Always Free resources.

## Decision
- OKE is a **second target for the same project**, not a separate project. It uses the same app, CI and gitops repo, with its own Kustomize overlay (`overlays/oke` next to `overlays/k3s`).
- **Scope:** Stretch. It is cut before HPA (ADR 0011). It never pushes TLS, backups or SLO alerts on k3s out of core.
- **Cluster type:** a Basic cluster. Its control plane is free; an Enhanced cluster is billed per hour.
- **Node shape:** a small x86 Flex shape (`VM.Standard.E4.Flex` or `E5.Flex`), 2 nodes at 1 OCPU / 8 GB, with shape, size, count and Kubernetes version in Terraform variables. **Never A1:** A1 nodes in OKE count toward the 2 OCPU / 12 GB Always Free limit, and going over it when the trial ends disables every A1 instance, including the node. A1 also has the same capacity shortage.
- **Images:** CI builds multi-arch images (`linux/amd64` and `linux/arm64`) under one tag, so both targets pull the same tag. This changes the arm64-only build in PLAN.md; the tag-bump flow in ADR 0009 stays the same.
- **Terraform:** a separate root (`terraform/oke/`) with its own state key in the same bucket (ADR 0003) and its own VCN. A `terraform destroy` there cannot reach the node or the NLB, which keep `prevent_destroy`.
- **Load balancer:** the app is exposed through the one free Flexible Load Balancer (10 Mbps shape) using Service annotations. The free NLB stays reserved for k3s (ADR 0004).
- **GitOps:** ArgoCD is installed once on OKE as a bootstrap step; after that, changes go through the gitops repo only.
- **Teardown date: 2026-11-15**, four days before the credit ends. It is tracked as a GitHub issue with that due date.

## Cost (estimate, check in the OCI cost estimator before applying)
About $2 a day for two 1 OCPU / 8 GB x86 nodes and their boot volumes, so roughly $50 if it runs until the teardown date. The Basic control plane and the 10 Mbps Flexible LB add nothing. Billed resources to check in Cost Analysis after teardown: node pool instances, their boot volumes, and any block volumes created by PersistentVolumeClaims (`oci-bv`).

## Consequences
- ArgoCD, Kustomize overlays and the app can be built and tested while A1 is blocked.
- The overlays carry real environment differences: StorageClass (`oci-bv` vs `local-path`), load balancer annotations, replica spread and anti-affinity. That is the point of overlays, not extra work.
- Multi-arch builds take longer in CI (arm64 under QEMU emulation on amd64 runners).
- OKE does not run after 2026-11-15. The README shows it through screenshots, a short recording and the merged PRs, and says plainly that it was torn down to stay at $0/month.
- If the node gets A1 capacity first, OKE work moves after the core Phase 2a items and stays optional.

## At scale
OKE (or another managed Kubernetes) would be the production choice: an Enhanced cluster with an SLA, node pools across availability domains, cluster autoscaling, workload identity instead of keys, and one environment per overlay promoted through the gitops repo.
