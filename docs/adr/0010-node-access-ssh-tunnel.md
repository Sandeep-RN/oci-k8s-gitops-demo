# 0010. Node access over SSH, no public Kubernetes API

Status: Accepted (2026-10-21). Amended by ADR 0022 (on k3s the node's own ports 80 and 443 are public; no load balancer sits in front). The OKE target reached its private API through OCI Bastion instead (`terraform/oke`).

## Context
The repos are public and the node has a public IP. An open SSH or Kubernetes API port invites scanning.

## Decision
SSH with key-only login. The security list allows SSH only from a CIDR held in a Terraform variable. Port 6443 is never exposed; `kubectl` goes through an SSH tunnel. Only the load balancer's web ports are public.

## Consequences
- The allowed CIDR must be updated if the home or office IP changes.
- Tailscale (no public SSH at all) is a possible stretch.

## At scale
A bastion or zero-trust access product, short-lived credentials, and audited sessions.
