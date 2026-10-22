# Placeholders only. scripts/bootstrap-state.sh writes the real, git-ignored
# terraform.tfvars; add bastion_client_cidr to it before planning.
tenancy_ocid        = "ocid1.tenancy.oc1..<placeholder>"
compartment_ocid    = "ocid1.compartment.oc1..<placeholder>"
region              = "<home-region>"
oci_profile         = "oke-demo"
bastion_client_cidr = "<your-public-ip>/32"
