# Placeholders only. Copy to the git-ignored terraform.tfvars and fill in.
# tenancy_ocid, compartment_ocid and region: same values as ../oke/terraform.tfvars.
tenancy_ocid     = "ocid1.tenancy.oc1..<placeholder>"
compartment_ocid = "ocid1.compartment.oc1..<placeholder>"
region           = "<home-region>"
oci_profile      = "oke-demo"

ssh_allowed_cidr = "<your-public-ip>/32"
ssh_public_key   = "ssh-ed25519 AAAA...placeholder you@laptop"

# Defaults are already the Always Free maximum (2 OCPU / 12 GB / 50 GB boot).
# node_ocpus      = 2
# node_memory_gbs = 12
