# 0004. Network Load Balancer with TLS passthrough to Traefik

Status: Accepted (2026-10-21)

## Context
An instance's own public IP changes if the instance is recreated, which would break DNS. Always Free includes one Network Load Balancer and one Flexible Load Balancer (10 Mbps).

## Decision
Provision a Network Load Balancer with Terraform. It forwards TCP 80/443 straight to Traefik (k3s built-in) on the node. TLS terminates in the cluster using cert-manager. Workloads are exposed with standard Kubernetes `Ingress` objects, not Traefik-specific `IngressRoute`.

## Consequences
- Stable public IP and a production-style edge.
- Manifests stay portable to another ingress controller.
- Fallback if the NLB gives trouble: the free Flexible Load Balancer.

## At scale
Multiple load balancer backends across nodes, WAF/CDN in front, health-checked backends.
