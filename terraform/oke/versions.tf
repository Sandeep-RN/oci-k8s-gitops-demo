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
  # Own state key, so destroying OKE can never touch the k3s node (ADR 0015).
  backend "oci" {
    key = "oke/terraform.tfstate"
  }
}

provider "oci" {
  region = var.region
  # Short-lived session token from `oci session authenticate`; no API key on disk.
  auth                = "SecurityToken"
  config_file_profile = var.oci_profile
}
