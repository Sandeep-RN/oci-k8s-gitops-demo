# 0001. Single-node k3s on one Always Free A1 instance

Status: Accepted (2026-10-21)

## Context
Oracle's Always Free tier allows 2 OCPU / 12 GB of Ampere A1 in total. If more than that is held when the $300 trial ends, all A1 instances are disabled and later deleted.

## Decision
Run k3s on one A1 instance sized at the free limit (2 OCPU / 12 GB) from day 1. Keep shape and size in Terraform variables. Use the trial credit only for disposable experiments, destroyed before it expires.

## Consequences
- "Recreate from clean state on Always Free" is true from the start, not a risky resize at the end.
- No node-level high availability. The README says so plainly.
- Run 2 backend replicas so the HPA and PodDisruptionBudget still do something useful.

## At scale
Multiple nodes across availability domains, an HA control plane (or managed OKE), and anti-affinity rules.
