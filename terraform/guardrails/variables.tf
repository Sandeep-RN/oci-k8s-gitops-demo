# Cost guardrails (ADR 0021). Defaults are the steady state after the OKE
# teardown (#13): Always Free only. While OKE still runs, raise the E5 and
# block-storage values in the git-ignored terraform.tfvars (see example.tfvars).
#
# Validations are upper bounds on purpose: raising a cap beyond them needs a
# reviewed code change, not just a tfvars edit.

variable "tenancy_ocid" {
  description = "Tenancy OCID. Quota policies and budgets both live at the tenancy root."
  type        = string
}

variable "region" {
  description = "Home region. Always Free resources must live here."
  type        = string
}

variable "oci_profile" {
  description = "OCI CLI config profile holding the session token."
  type        = string
  default     = "oke-demo"
}

# --- Quotas (hard limits) ---------------------------------------------------

variable "a1_ocpus_quota" {
  description = "Ampere A1 OCPUs allowed in the whole tenancy. 2 is the Always Free size (ADR 0001)."
  type        = number
  default     = 2

  validation {
    # Above 2 OCPU / 12 GB, A1 is billed, and at the end of the trial ALL A1
    # instances are disabled if usage is over the free size (ADR 0001).
    condition     = var.a1_ocpus_quota >= 0 && var.a1_ocpus_quota <= 2
    error_message = "a1_ocpus_quota must be 0-2 (Always Free)."
  }
}

variable "a1_memory_gbs_quota" {
  description = "Ampere A1 memory (GB) allowed in the whole tenancy. 12 is the Always Free size."
  type        = number
  default     = 12

  validation {
    condition     = var.a1_memory_gbs_quota >= 0 && var.a1_memory_gbs_quota <= 12
    error_message = "a1_memory_gbs_quota must be 0-12 (Always Free)."
  }
}

variable "e5_ocpus_quota" {
  description = "VM.Standard.E5 OCPUs allowed. 2 while the OKE workers run (2 x 1 OCPU); 0 after the teardown (#13)."
  type        = number
  default     = 0

  validation {
    condition     = var.e5_ocpus_quota >= 0 && var.e5_ocpus_quota <= 2
    error_message = "e5_ocpus_quota must be 0-2: exactly what the OKE pool uses, no room for growth."
  }
}

variable "e5_memory_gbs_quota" {
  description = "VM.Standard.E5 memory (GB) allowed. 16 while the OKE workers run (2 x 8 GB); 0 after the teardown (#13)."
  type        = number
  default     = 0

  validation {
    condition     = var.e5_memory_gbs_quota >= 0 && var.e5_memory_gbs_quota <= 16
    error_message = "e5_memory_gbs_quota must be 0-16: exactly what the OKE pool uses."
  }
}

variable "block_storage_gbs_quota" {
  description = "Boot + block volume GB allowed. 200 is the Always Free total; 250 during the OKE + k3s overlap (OKE 200 GB + the 50 GB k3s boot volume)."
  type        = number
  default     = 200

  validation {
    condition     = var.block_storage_gbs_quota >= 50 && var.block_storage_gbs_quota <= 250
    error_message = "block_storage_gbs_quota must be 50-250 (200 Always Free, +50 only for the OKE overlap)."
  }
}

variable "volume_backups_quota" {
  description = "Boot + block volume backups allowed. 5 is the Always Free number; Postgres backups go to Object Storage, not here."
  type        = number
  default     = 5

  validation {
    condition     = var.volume_backups_quota >= 0 && var.volume_backups_quota <= 5
    error_message = "volume_backups_quota must be 0-5 (Always Free)."
  }
}

# --- Budget (notification only, NOT a cap) ----------------------------------

variable "budget_monthly_amount" {
  description = "Monthly spend tolerance for the whole tenancy, a whole number in the account's rate-card currency (SGD here). About INR 500 (ADR 0021)."
  type        = number

  validation {
    condition     = var.budget_monthly_amount >= 1 && floor(var.budget_monthly_amount) == var.budget_monthly_amount
    error_message = "budget_monthly_amount must be a whole number >= 1 (OCI budgets take whole amounts)."
  }
}

variable "budget_early_warning_amount" {
  description = "Actual spend (same currency) that triggers the early warning. The target is 0/month, so any real spend is worth an email."
  type        = number
  default     = 1

  validation {
    condition     = var.budget_early_warning_amount > 0
    error_message = "budget_early_warning_amount must be greater than 0."
  }
}

variable "budget_alert_recipients" {
  description = "Email address(es) for budget alerts, comma-separated. Real value only in the git-ignored terraform.tfvars."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s,]+@[^@\\s,]+(\\s*,\\s*[^@\\s,]+@[^@\\s,]+)*$", var.budget_alert_recipients))
    error_message = "budget_alert_recipients must be one or more email addresses separated by commas."
  }
}
