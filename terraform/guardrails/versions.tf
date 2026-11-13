terraform {
  # 1.12.0 is the first release with the native `oci` backend used below.
  required_version = ">= 1.12.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.10"
    }
  }

  # Native OCI backend (ADR 0003): terraform init -backend-config=../backend.hcl
  # Own state key (ADR 0021): the guardrails change on their own schedule
  # (tightened after the OKE teardown, loosened for an experiment), and those
  # applies should never plan against the backup bucket in `shared`.
  backend "oci" {
    key = "guardrails/terraform.tfstate"
  }
}

provider "oci" {
  region = var.region
  # Short-lived session token from `oci session authenticate`; no API key on disk.
  auth                = "SecurityToken"
  config_file_profile = var.oci_profile
}
