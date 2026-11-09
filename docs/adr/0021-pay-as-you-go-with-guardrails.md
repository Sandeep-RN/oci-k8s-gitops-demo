# 0021. Pay As You Go, with quota policies as the cap and a budget as the alarm

Status: Accepted (2026-11-10). Supersedes the line "Upgrading to Pay As You Go is ruled out (cost)" in ADR 0020's context. Decided by the owner on 2026-11-03.

## Context
The k3s node (ADR 0001) still does not exist. Since 2026-10-22 the home region, which has a single availability domain, has had no A1 capacity at any size, and no E2.1.Micro capacity either. Polling has not helped. Upgrading the tenancy to Pay As You Go (PAYG) is the one lever left. It is not guaranteed to bring capacity, but nothing else is in our control.

The risk is money. Three facts shaped the decision:

- **OCI has no spending cap.** A budget is, in Oracle's words, a "soft limit": it sends an email and never stops anything. Budget alerts are evaluated only "every 24 hours", so an alert can arrive a day after the spend started.
- **Service limits are already far above Always Free.** Checked on 2026-11-10 with `oci limits value list`, the trial tenancy allows 41 A1 cores and 277 GB of A1 memory in the AD (16 / 96 regionally), and 13 E5 cores. The "2 OCPU / 12 GB" has only ever been enforced by a validation in `terraform/k3s`, which protects nothing created in the Console, by another root, or by OKE. Without a guardrail, a mistake is billed during the trial (against the credit) and after the upgrade (against the card).
- **A quota policy is enforced by OCI itself.** A create request that would push usage over a quota is refused. It is the closest thing to a cap that OCI offers.

The owner accepts about SGD 3/day for a day or two of OKE and k3s overlap, and up to about INR 500/month (SGD 7 in the account's currency) on an ongoing basis. The target stays $0/month on Always Free. The margin is for mistakes and short overlaps, not for planned spend.

## Decision
- **Upgrade to PAYG**, but only after the OKE evidence capture (#112, done 2026-11-09), and only **after** the guardrails below are applied and proven to block.
- **One quota policy at the tenancy root** (`oci_limits_quota`). It is an allow list: zero a whole family, then allow only what we use. Within one policy, a later statement overrides an earlier one, so the order is fixed and everything sits in a single policy. Across policies, the most restrictive one wins, so a separate allow-list policy would lose to the zero.
  - Compute: zero all cores and all memory (every x86, GPU and bare-metal shape, dedicated hosts, capacity reservations, E2.1.Micro), then allow A1 up to 2 OCPU / 12 GB. A1 has both an AD-scoped and a regional count, and both are set. The regional pair is the true tenancy-wide total if the region ever gains more ADs.
  - E5 (the OKE workers, ADR 0015): exactly the current 2 OCPU / 16 GB until the teardown (#13), then 0.
  - Block storage: 250 GB of boot and block volumes during the overlap (OKE uses 200 GB today, plus the 50 GB k3s boot volume), then 200 GB, the Always Free total. Volume backups: 5 (Always Free). Cross-region replicas: 0. Quota by quota, never a family zero: that would also zero `volume-count` and block every new volume.
  - Classic load balancers: zero. None exist, and the k3s edge needs none (ServiceLB on the node IP).
- **One monthly budget on the root compartment**, which tracks every compartment in the tenancy, with three alert rules to the owner's email:
  - early warning: actual spend above SGD 1 (any real spend once OKE is gone);
  - actual spend at 100% of the tolerance;
  - forecast spend at 100% of the tolerance (a steady leak, seen before the month's total gets there).
- **A new Terraform root, `terraform/guardrails`**, with its own state key, rather than adding to `terraform/shared`. The guardrails change on their own schedule (tightened after #13, possibly loosened for an experiment), and those applies should never plan against the backup bucket (`prevent_destroy`) or the nodes' IAM. They also shouldn't share state with the resources they protect. Quotas and budgets are free resources.
- Amounts, recipients and the overlap values are variables. The real values live only in the git-ignored `terraform.tfvars`. The defaults are the post-teardown, Always Free steady state, so tightening after #13 means deleting three tfvars lines and applying. Validations put upper bounds on every quota, so raising a cap past Always Free needs a reviewed code change, not just a tfvars edit.
- Quota names come from the live tenancy (`oci limits definition list`, `are-quotas-supported = true`), not from the docs. Oracle's quota-name page lists `standard-e5-core-ad-count`. The real name is `standard-e5-core-count`.

Order: apply the guardrails, prove a quota blocks (a launch the quota must refuse), upgrade to PAYG in the Console, check Cost Analysis the next day, tighten after #13. The steps are in `docs/runbooks/cost-guardrails.md`.

## Consequences
- What is **capped**: compute of every shape, A1 above the free size, E5 above the OKE pool, volume storage, volume backups, replicas, classic load balancers.
- What is **only watched** (no documented quota, or a quota would be meaningless): Network Load Balancers, OKE clusters, Object Storage, outbound data transfer, and every other service. For these, the budget is the only signal, and it can be up to a day late.
- The budget alerts will fire within a day of the first apply. OKE has already spent well over SGD 7 this November. That first email is the test that delivery works. It also shows whether budgets count usage that is paid by trial credit, which Oracle does not document. Oracle also doesn't say whether an alert rule fires once per period or repeatedly, so watch that in December.
- Quotas also block legitimate work. A node-pool resize, a second k3s node or a bigger boot volume will now fail with a quota error until the variable is raised. That friction is intended. The fix is a PR to the variable, never a Console edit (that would be drift).
- E2.1.Micro is zeroed even though it is Always Free. It is too small for this stack, and a zero is simpler to reason about than an exception.
- Oracle does not document what a quota does to resources that already exist above it. The values here never sit below current usage: E5 and storage are set to what OKE uses today, and lowered only after the teardown.
- The budget made earlier in the Console ("Budget-Alert-2-Doller", amount 50) is left alone. It is not in Terraform. The owner can delete it once this budget's first alert has arrived.
- No non-free resource is created by this ADR.

## At scale
In an organisation, the same split: quotas per compartment or team as hard caps, budgets per cost centre (tag-based targets) as alarms. Add an automated response to a budget event (for example, stopping instances tagged as disposable), an approval workflow for limit and quota increases, and cost reports reviewed on a schedule rather than only when an email arrives.
