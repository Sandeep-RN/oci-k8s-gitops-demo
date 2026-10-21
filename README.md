# oci-k8s-gitops-demo

Infrastructure, architecture decisions and runbooks for a public demo of
Kubernetes, Docker, CI/CD, GitOps and observability, running entirely on
**Oracle Cloud Always Free** (target cost: $0/month).

> **Status:** Phase 1 (infrastructure and cluster) is in progress. The live
> URL (`demo.sandeeprn.in`) is planned, not up yet. This README describes the
> target design; ADRs record what has been decided.

## The three repos

| Repo | Holds |
| --- | --- |
| **oci-k8s-gitops-demo** (this one) | Terraform for OCI, ADRs, glossary, runbooks, and the GitHub Issues tracker for all three repos |
| [oci-k8s-gitops-demo-app](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app) | FastAPI backend, static frontend, Dockerfiles, GitHub Actions CI |
| [oci-k8s-gitops-demo-gitops](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-gitops) | Kustomize manifests and ArgoCD Applications (source of truth for the cluster) |

## Target architecture

```
Internet -> Cloudflare DNS (DNS only)
         -> OCI Network Load Balancer (reserved IP, TLS passthrough)
         -> Traefik on a single-node k3s cluster (Ampere A1 VM, 2 OCPU / 12 GB)
         -> link-shortener app (FastAPI) + PostgreSQL StatefulSet
```

- **Infra:** VCN, public subnet, Internet Gateway, NLB and one A1 VM, all in
  Terraform. State lives in a versioned Object Storage bucket (ADR 0003).
- **Cluster:** Ubuntu 24.04 aarch64, single-node k3s, cloud-init fixes the
  image's firewall rules (ADR 0001, 0002, 0012).
- **Delivery:** GitHub Actions builds, scans (Trivy) and pushes an arm64 image,
  then opens a tag-bump PR in the gitops repo; ArgoCD syncs it (ADR 0009).
- **Edge and secrets:** Traefik Ingress, cert-manager with Cloudflare DNS-01,
  Sealed Secrets (ADR 0004, 0005, 0006).
- **Observability:** kube-prometheus-stack, a 7-day redirect SLO with
  multi-window burn-rate alerts to Discord, and an external probe (ADR 0008).

## Repository layout

```
terraform/       OCI infrastructure (variables for shape/size; no real tfvars)
docs/adr/        Architecture decision records (0001-0014)
docs/runbooks/   Operational runbooks
GLOSSARY.md      Project terms
```

## Working here

- Every change goes through a pull request (ADR 0011).
- A change of approach needs a new ADR in `docs/adr/`.
- Install hooks once: `pip install pre-commit && pre-commit install`. They run
  gitleaks (with custom OCI rules in `.gitleaks.toml`), `terraform fmt` and
  `terraform validate`.
- **This repo is public.** Never commit tfstate, real `*.tfvars`, OCI keys,
  kubeconfig, OCIDs, public IPs, passwords or tokens. Use `example.tfvars`
  with placeholders.

## Cost

The final demo stays inside Always Free. The $300 trial credit is only for
disposable experiments, and any non-free resource must be listed and deleted
before the trial ends (~2026-11-19). See ADR 0001.
