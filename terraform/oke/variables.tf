# Values for the first four come from terraform.tfvars, written (git-ignored)
# by scripts/bootstrap-state.sh. See example.tfvars.

variable "tenancy_ocid" {
  description = "Tenancy OCID (used to look up availability domains)."
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

variable "bastion_client_cidr" {
  description = "CIDR allowed to open Bastion sessions to the private API endpoint (your public IP as /32)."
  type        = string

  validation {
    condition     = can(cidrhost(var.bastion_client_cidr, 0)) && var.bastion_client_cidr != "0.0.0.0/0"
    error_message = "bastion_client_cidr must be a valid CIDR and not 0.0.0.0/0 (ADR 0010)."
  }
}

variable "kubernetes_version" {
  description = "OKE Kubernetes version for the control plane and nodes. Pinned so plans stay stable."
  type        = string
  default     = "v1.36.4"
}

variable "node_image_name" {
  description = "Exact OKE x86 node image name; must match kubernetes_version. Pinned so a new Oracle image does not cause drift."
  type        = string
  default     = "Oracle-Linux-9.8-2026.09.18-0-OKE-1.36.4-1923"
}

variable "node_shape" {
  description = "Worker shape. x86 Flex only (ADR 0015)."
  type        = string
  # E5, not E4: on 2026-10-23 E4.Flex was OUT_OF_HOST_CAPACITY in every fault
  # domain of the home region (checked with `oci compute compute-capacity-report
  # create`), which made node pool creation fail with "exceeded max retry count".
  default = "VM.Standard.E5.Flex"

  # Guardrail: A1 nodes here would count toward the 2 OCPU / 12 GB Always Free
  # limit; exceeding it at trial end disables ALL A1 instances, including the
  # long-lived k3s node.
  validation {
    condition     = !can(regex("A1", var.node_shape))
    error_message = "A1 shapes are not allowed for OKE nodes (ADR 0015)."
  }
}

variable "node_ocpus" {
  description = "OCPUs per worker."
  type        = number
  default     = 1
}

variable "node_memory_gbs" {
  description = "Memory (GB) per worker."
  type        = number
  default     = 8
}

variable "node_count" {
  description = "Workers in the pool. Two is the minimum to prove a PDB-respecting drain."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 3
    error_message = "node_count must be 1-3; this is a cost-capped demo."
  }
}

variable "boot_volume_gbs" {
  description = "Boot volume size per worker (50 GB is the minimum)."
  type        = number
  default     = 50
}

variable "vcn_cidr" {
  description = "VCN address space. Subnets are carved from it in network.tf."
  type        = string
  default     = "10.20.0.0/16"
}

variable "pods_cidr" {
  description = "Flannel pod network. Must not overlap the VCN."
  type        = string
  default     = "10.244.0.0/16"
}

variable "services_cidr" {
  description = "Kubernetes Service network. Must not overlap the VCN or pods."
  type        = string
  default     = "10.96.0.0/16"
}
