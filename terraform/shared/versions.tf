terraform {
  required_version = ">= 1.6.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.10"
    }
  }

  # Native OCI backend (ADR 0003): terraform init -backend-config=../backend.hcl
  # Own state key: resources here outlive any one cluster (OKE now, k3s later),
  # so destroying a cluster root can never remove the backups.
  backend "oci" {
    key = "shared/terraform.tfstate"
  }
}

provider "oci" {
  region = var.region
  # Short-lived session token from `oci session authenticate`; no API key on disk.
  auth                = "SecurityToken"
  config_file_profile = var.oci_profile
}
