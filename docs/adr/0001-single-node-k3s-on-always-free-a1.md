# 0001. Single-node k3s on one Always Free A1 instance

Status: Accepted (2026-10-21, revised 2026-10-21 after review)

## Context
Oracle's Always Free tier allows 2 OCPU / 12 GB of Ampere A1 in total. If more than that is held when the $300 trial ends, all A1 instances are disabled and later deleted, not only the excess. A1 capacity is often unavailable ("out of host capacity"), so an instance that is destroyed may not be obtainable again.

## Decision
- Run k3s on one A1 instance sized at the free limit (2 OCPU / 12 GB) from day 1. Keep shape and size in Terraform variables.
- Use the trial credit only for disposable experiments, destroyed before it expires.
- Protect the instance (and the NLB, ADR 0004) with `lifecycle { prevent_destroy = true }`.
- Prove "recreate from clean state" once, deliberately, after the credit-period experiments, by temporarily lifting the protection. Until then, keep the node.

## Consequences
- No node-level high availability. The README says so plainly.
- Run 2 backend replicas so the HPA still does something useful.
- A PodDisruptionBudget cannot be honoured when draining the only node: evicted pods have nowhere to go, so `kubectl drain` blocks. The PDB is kept to show intent; the maintenance runbook documents draining a single node (`--disable-eviction`, accepting the brief outage).

## At scale
Multiple nodes across availability domains, an HA control plane (or managed OKE), anti-affinity rules, and PDBs that actually protect availability during drains.
