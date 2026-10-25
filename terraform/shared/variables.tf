# Copy the first three values from ../oke/terraform.tfvars (written by
# scripts/bootstrap-state.sh) into a git-ignored terraform.tfvars here.
# See example.tfvars.

variable "tenancy_ocid" {
  description = "Tenancy OCID. Dynamic groups live at the tenancy root."
  type        = string
}

variable "compartment_ocid" {
  description = "Project compartment created by scripts/bootstrap-state.sh."
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

variable "backup_bucket_name" {
  description = "Object Storage bucket for nightly pg_dump files (ADR 0007, 0017)."
  type        = string
  default     = "oci-k8s-gitops-demo-pg-backups"
}

variable "backup_retention_days" {
  description = "Days before a dump is deleted by the lifecycle rule. Dumps are KBs to MBs, far below the 20 GB Always Free limit."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 3 && var.backup_retention_days <= 90
    error_message = "backup_retention_days must be between 3 and 90."
  }
}
