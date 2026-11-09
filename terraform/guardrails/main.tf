# Cost guardrails (ADR 0021). Quotas and budgets are free resources.
#
#   quota policy = the cap: a create request that would exceed it is refused
#   budget       = the smoke alarm: an email, evaluated about once every 24 h;
#                  it never stops anything
#
# Quota names were checked against the live tenancy on 2026-11-10 with
# `oci limits definition list` (are-quotas-supported = true). The docs page
# listing quota names gave `standard-e5-core-ad-count`, which does not exist;
# the live name is `standard-e5-core-count`. Re-check there, not in the docs,
# before adding a name.

locals {
  # Statement ORDER matters: within one policy a later statement overrides an
  # earlier one for the same quota. So the family-wide `zero` comes first and
  # the allow-list `set` lines after it. Keep everything in ONE policy: across
  # policies the most restrictive wins, which would make the zero win.
  quota_statements = [
    # Compute: deny every shape (x86, GPU, bare metal, dedicated hosts,
    # capacity reservations, E2.1.Micro), then allow only what we use.
    "zero compute-core quotas in tenancy",
    "zero compute-memory quotas in tenancy",

    # A1 has an AD-scoped AND a regional count. The family zero above set the
    # regional one to 0 too, which would block the k3s node; both must be set.
    # The regional pair is the true tenancy-wide total in a multi-AD region.
    "set compute-core quota standard-a1-core-count to ${var.a1_ocpus_quota} in tenancy",
    "set compute-core quota standard-a1-core-regional-count to ${var.a1_ocpus_quota} in tenancy",
    "set compute-memory quota standard-a1-memory-count to ${var.a1_memory_gbs_quota} in tenancy",
    "set compute-memory quota standard-a1-memory-regional-count to ${var.a1_memory_gbs_quota} in tenancy",

    # OKE workers (ADR 0015) until the teardown (#13); 0 afterwards.
    "set compute-core quota standard-e5-core-count to ${var.e5_ocpus_quota} in tenancy",
    "set compute-memory quota standard-e5-memory-count to ${var.e5_memory_gbs_quota} in tenancy",

    # Block storage: set quota by quota. A family-wide zero would also zero
    # `volume-count` and block every new volume, the k3s boot volume included.
    "set block-storage quota total-storage-gb to ${var.block_storage_gbs_quota} in tenancy",
    "set block-storage quota backup-count to ${var.volume_backups_quota} in tenancy",
    "set block-storage quota total-replica-storage-gb to 0 in tenancy",

    # Classic load balancers: none exist (2026-11-10) and the k3s edge uses
    # none (ServiceLB on the node IP). The free Network Load Balancer is a
    # different service and has no quota; the budget covers it.
    "zero load-balancer quotas in tenancy",
  ]
}

resource "oci_limits_quota" "cost_guardrails" {
  compartment_id = var.tenancy_ocid
  name           = "oci-k8s-gitops-demo-cost-guardrails"
  description    = "Hard caps that keep the tenancy on Always Free after the Pay As You Go upgrade (ADR 0021). Managed by Terraform (terraform/guardrails)."
  statements     = local.quota_statements

  freeform_tags = { project = "oci-k8s-gitops-demo", purpose = "cost-guardrails" }
}

# One budget on the root compartment tracks every compartment in the tenancy,
# so a mistake outside the project compartment is still seen. Budgets can
# only be created in the root compartment.
resource "oci_budget_budget" "tenancy_monthly" {
  compartment_id         = var.tenancy_ocid
  display_name           = "oci-k8s-gitops-demo-tenancy-monthly"
  description            = "Whole-tenancy monthly spend tolerance (ADR 0021). Alerts only: a budget never stops spending."
  amount                 = var.budget_monthly_amount
  reset_period           = "MONTHLY"
  processing_period_type = "MONTH"
  target_type            = "COMPARTMENT"
  targets                = [var.tenancy_ocid]

  freeform_tags = { project = "oci-k8s-gitops-demo", purpose = "cost-guardrails" }

  lifecycle {
    precondition {
      condition     = var.budget_early_warning_amount < var.budget_monthly_amount
      error_message = "budget_early_warning_amount must be below budget_monthly_amount, or the early warning is not early."
    }
  }
}

# The target is 0/month, so any actual spend is unexpected once OKE is gone.
resource "oci_budget_alert_rule" "early_warning" {
  budget_id      = oci_budget_budget.tenancy_monthly.id
  display_name   = "early-warning-actual"
  description    = "Any real spend this month (target is Always Free, 0/month)."
  type           = "ACTUAL"
  threshold_type = "ABSOLUTE"
  threshold      = var.budget_early_warning_amount
  recipients     = var.budget_alert_recipients
  message        = "oci-k8s-gitops-demo: actual spend this month passed the early-warning amount. Expected only during the OKE overlap. Check Cost Analysis by service. Runbook: docs/runbooks/cost-guardrails.md"
}

resource "oci_budget_alert_rule" "tolerance_actual" {
  budget_id      = oci_budget_budget.tenancy_monthly.id
  display_name   = "tolerance-actual"
  description    = "Actual spend reached the monthly tolerance."
  type           = "ACTUAL"
  threshold_type = "PERCENTAGE"
  threshold      = 100
  recipients     = var.budget_alert_recipients
  message        = "oci-k8s-gitops-demo: actual spend reached the monthly tolerance (ADR 0021). Find the resource in Cost Analysis and delete it, or tighten a quota. Runbook: docs/runbooks/cost-guardrails.md"
}

# Forecast catches a steady leak before the month's actual total gets there.
resource "oci_budget_alert_rule" "tolerance_forecast" {
  budget_id      = oci_budget_budget.tenancy_monthly.id
  display_name   = "tolerance-forecast"
  description    = "Forecast spend for the month is over the tolerance."
  type           = "FORECAST"
  threshold_type = "PERCENTAGE"
  threshold      = 100
  recipients     = var.budget_alert_recipients
  message        = "oci-k8s-gitops-demo: forecast spend for this month is over the tolerance (ADR 0021). Something is billing every day. Runbook: docs/runbooks/cost-guardrails.md"
}
