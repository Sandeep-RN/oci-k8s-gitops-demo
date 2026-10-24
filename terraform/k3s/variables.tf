# The first four come from terraform.tfvars (git-ignored); see example.tfvars.
# tenancy_ocid, compartment_ocid and region are the same values as in
# ../oke/terraform.tfvars (written by scripts/bootstrap-state.sh).

variable "tenancy_ocid" {
  description = "Tenancy OCID (used to look up the availability domain)."
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

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to reach SSH (your public IP as /32). Update it if your IP changes (ADR 0010)."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0)) && var.ssh_allowed_cidr != "0.0.0.0/0"
    error_message = "ssh_allowed_cidr must be a valid CIDR and not 0.0.0.0/0 (ADR 0010)."
  }
}

variable "ssh_public_key" {
  description = "Public half of the key used to log in as the default ubuntu user. The private key never goes in the repo."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key line (ssh-ed25519 ...)."
  }
}

variable "shape" {
  description = "Instance shape. Always Free A1 only (ADR 0001)."
  type        = string
  default     = "VM.Standard.A1.Flex"

  validation {
    condition     = var.shape == "VM.Standard.A1.Flex"
    error_message = "This root only creates the Always Free A1 node (ADR 0001)."
  }
}

# Guardrail (ADR 0001): the Always Free allowance is 2 OCPU / 12 GB of A1 in
# total. Holding more when the trial ends disables and later deletes ALL A1
# instances, so a typo here must fail at plan time, not at trial end.
variable "node_ocpus" {
  description = "OCPUs for the node. Always Free maximum is 2."
  type        = number
  default     = 2

  validation {
    condition     = var.node_ocpus >= 1 && var.node_ocpus <= 2
    error_message = "node_ocpus must be 1-2: the Always Free A1 allowance is 2 OCPU in total (ADR 0001)."
  }
}

variable "node_memory_gbs" {
  description = "Memory (GB) for the node. Always Free maximum is 12."
  type        = number
  default     = 12

  validation {
    condition     = var.node_memory_gbs >= 1 && var.node_memory_gbs <= 12
    error_message = "node_memory_gbs must be 1-12: the Always Free A1 allowance is 12 GB in total (ADR 0001)."
  }
}

variable "boot_volume_gbs" {
  description = "Boot volume size (47 GB is the minimum; 200 GB total is Always Free across all volumes)."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_gbs >= 47 && var.boot_volume_gbs <= 100
    error_message = "boot_volume_gbs must be 47-100 to leave room in the 200 GB Always Free volume allowance."
  }
}

variable "k3s_version" {
  description = "Pinned k3s release so a rebuild produces the same cluster (ADR 0001)."
  type        = string
  default     = "v1.36.5+k3s1"
}

variable "vcn_cidr" {
  description = "VCN address space. Differs from the OKE VCN (10.20.0.0/16)."
  type        = string
  default     = "10.30.0.0/16"
}
