# 0004. Network Load Balancer with TLS passthrough to Traefik

Status: Accepted (2026-10-21, revised 2026-10-21 after review). Amended by ADR 0020 (TLS and public hostname on OKE).

## Context
An instance's own public IP changes if the instance is recreated, which would break DNS. Always Free includes one Network Load Balancer and one Flexible Load Balancer (the 10 Mbps cap applies to the Flexible LB, not the NLB).

## Decision
- Provision a Network Load Balancer with Terraform, with a reserved public IP (ADR 0013) and `prevent_destroy`.
- It forwards TCP 80/443 to the node's private IP, where Traefik (k3s built-in) listens on 80/443 through k3s ServiceLB.
- TLS terminates in the cluster using cert-manager (ADR 0005).
- Workloads are exposed with standard Kubernetes `Ingress` objects, not Traefik-specific `IngressRoute`.

## Consequences
- Stable public IP and a production-style edge.
- Manifests stay portable to another ingress controller.
- Traffic from inside the cluster to the public hostname loops out to the NLB and back (hairpin), which may fail; health probes that need the user's view run from outside (ADR 0008).
- Fallback if the NLB gives trouble: the free Flexible Load Balancer.

## At scale
Multiple backends across nodes, WAF/CDN in front, health-checked backends.
