# Placeholders only. scripts/bootstrap-state.sh writes tenancy_ocid, region and
# oci_profile into a git-ignored terraform.tfvars in this folder; set the rest
# there.
tenancy_ocid = "ocid1.tenancy.oc1..<placeholder>"
region       = "<home-region>"
oci_profile  = "oke-demo"

# Budget: whole number in the account's rate-card currency.
budget_monthly_amount       = 7
budget_early_warning_amount = 1
budget_alert_recipients     = "you@example.com"
