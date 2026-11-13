# 0013. Reserved public IP for the NLB and Terraform-managed DNS

Status: Accepted (2026-10-21). Superseded by ADR 0020 (external-dns keeps the record; no reserved IP; no Cloudflare record in Terraform) and, on k3s, by ADR 0022 (the node's ephemeral public IP).

## Context
If the NLB is recreated with a new ephemeral IP, the DNS record must change by hand. A rebuild should need no manual DNS step.

## Decision
- Give the NLB a reserved public IP managed by Terraform. Whether a reserved IP is free on Always Free was not confirmed in Oracle's docs; check in the console (and the cost report) before relying on it. If it costs money, fall back to an ephemeral IP with the DNS record updated by Terraform on each apply.
- Manage the `demo.sandeeprn.in` record with the Cloudflare Terraform provider, set to DNS only. The Cloudflare token for Terraform is separate from cert-manager's and is never committed.

## Consequences
- Rebuilds keep the same address, and DNS is code.
- Two Cloudflare tokens to manage, each with a narrow scope.

## At scale
DNS per environment, health-checked failover records.
