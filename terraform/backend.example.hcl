# Placeholder for terraform/backend.hcl (git-ignored), which
# scripts/bootstrap-state.sh generates with real values (ADR 0003).
# Each root sets its own state `key` in its backend block.
# Use: terraform init -backend-config=../backend.hcl
bucket              = "oci-k8s-gitops-demo-tfstate"
namespace           = "<object-storage-namespace>"
region              = "<home-region>"
auth                = "SecurityToken"
config_file_profile = "<oci-cli-profile>"
