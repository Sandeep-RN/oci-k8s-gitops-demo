# Placeholders only. Copy tenancy_ocid and region from ../oke/terraform.tfvars
# into a git-ignored terraform.tfvars in this folder and set the rest there.
tenancy_ocid = "ocid1.tenancy.oc1..<placeholder>"
region       = "<home-region>"
oci_profile  = "oke-demo"

# Budget: whole number in the account's rate-card currency.
budget_monthly_amount       = 7
budget_early_warning_amount = 1
budget_alert_recipients     = "you@example.com"

# Only while OKE runs (ADR 0015). Delete these three lines after the teardown
# (#13) and apply: the defaults (0, 0, 200) are the Always Free steady state.
e5_ocpus_quota          = 2
e5_memory_gbs_quota     = 16
block_storage_gbs_quota = 250
