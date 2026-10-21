# 0012. Node firewall handled in cloud-init

Status: Accepted (2026-10-21)

## Context
Oracle's Ubuntu images ship iptables rules with REJECT entries in the INPUT and FORWARD chains. They block ports 80/443 from the NLB and break k3s pod networking. This is the most likely day-1 blocker.

## Decision
cloud-init adjusts the host firewall before installing k3s: remove or bypass the REJECT rules so the OCI security list (managed by Terraform) is the single source of truth for inbound traffic, and persist the change across reboots. The security list allows only SSH from the allowed CIDR (ADR 0010) and 80/443 from the NLB.

## Consequences
- Inbound control lives in one place (Terraform), visible in code review.
- Verification after every rebuild: pods can reach each other and the internet, and 80/443 answer through the NLB.

## At scale
Host firewall managed by configuration management or a hardened image, plus Kubernetes NetworkPolicies.
