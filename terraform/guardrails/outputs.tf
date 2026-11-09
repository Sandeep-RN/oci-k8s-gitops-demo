output "quota_statements" {
  description = "The quota policy as applied, in order. Compare with Governance > Quota Policies in the Console."
  value       = oci_limits_quota.cost_guardrails.statements
}

output "budget_monthly_amount" {
  description = "Monthly tolerance in the account's currency. Alerts only; not a cap."
  value       = oci_budget_budget.tenancy_monthly.amount
}
