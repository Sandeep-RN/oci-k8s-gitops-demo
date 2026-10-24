terraform {
  required_version = ">= 1.6.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.10"
    }
  }

  # Native OCI backend (ADR 0003). Bucket, namespace, region and auth come from
  # the git-ignored ../backend.hcl:  terraform init -backend-config=../backend.hcl
  # Own state key, separate from OKE's, so destroying the OKE target can never
  # reach this node (ADR 0015).
  backend "oci" {
    key = "k3s/terraform.tfstate"
  }
}

provider "oci" {
  region = var.region
  # Short-lived session token from `oci session authenticate`; no API key on disk.
  auth                = "SecurityToken"
  config_file_profile = var.oci_profile
}
