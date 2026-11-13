# Runbook: cost guardrails and the Pay As You Go upgrade

ADR 0021. Root: `terraform/guardrails`. Issue: #113.

> **Status:** steps 1 to 4 were done on 2026-11-10 and 2026-11-11 (guardrails
> applied and proven, Pay As You Go upgrade, next-day check). Step 5 (tighten
> the quotas) waits for the OKE teardown
> ([#13](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/13)). The
> steps below are the record of what was done.

The quota policy is the cap: a create request over a quota is refused. The
budget is only an alarm: an email, evaluated about once every 24 hours, which
stops nothing. Do the steps in order. **Do not upgrade to Pay As You Go until
step 2 has passed.**

## What is enforced

| Guardrail | While OKE runs | After the teardown (#13) |
|---|---|---|
| Compute, every shape | 0 | 0 |
| A1 (AD and regional) | 2 OCPU / 12 GB | 2 OCPU / 12 GB |
| E5 (OKE workers) | 2 OCPU / 16 GB | 0 / 0 |
| Boot + block volumes | 250 GB | 200 GB |
| Volume backups / replicas | 5 / 0 GB | 5 / 0 GB |
| Classic load balancers | 0 | 0 |
| Budget (whole tenancy) | email at SGD 1 actual, at 100% actual, at 100% forecast | same |

Not capped, only watched by the budget: Network Load Balancers, OKE
clusters, Object Storage, data transfer and all other services.

## 1. Apply (owner)

```bash
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
cd terraform/guardrails
# terraform.tfvars is git-ignored. In a fresh checkout, copy example.tfvars to
# it and fill in tenancy_ocid and region from ../oke/terraform.tfvars.
# Set budget_alert_recipients to your email.
grep -c 'REPLACE_ME' terraform.tfvars    # must print 0
terraform init -backend-config=../backend.hcl
terraform plan -out=guardrails.tfplan    # expect 5 to add: 1 quota policy, 1 budget, 3 alert rules
terraform apply guardrails.tfplan
```

OCI allows only one budget per target compartment. If the apply fails with
`400-LimitExceeded, 1 budgets already exist in target compartment`, another
budget (for example one made in the Console) already targets the root. Delete
it (Billing > Budgets), then plan and apply again: resources that were already
created stay in state, so the second plan shows only what's missing.

A plan cannot check the quota statements. A misspelt quota or family name
fails only at apply. If it does, fix the name from
`oci limits definition list --service-name <family> --compartment-id <tenancy>`,
not from the docs page.

## 2. Prove the quota blocks (before the upgrade)

**a. The Console:** Governance & Administration > Quota Policies shows
`oci-k8s-gitops-demo-cost-guardrails` with 12 statements, in order.

**b. Effective quotas** (read-only). `effective-quota-value` is present only
when a quota applies:

```bash
OCI="oci --profile oke-demo --auth security_token"
T=<tenancy-ocid>                       # from terraform.tfvars; never commit
AD=$($OCI iam availability-domain list --compartment-id "$T" --query 'data[0].name' --raw-output)
for L in standard-e4-core-count standard-e2-micro-core-count standard-a1-core-count standard-a1-core-regional-count standard-e5-core-count; do
  echo "$L"
  $OCI limits resource-availability get --service-name compute --limit-name "$L" \
    --compartment-id "$T" --availability-domain "$AD" \
    --query 'data.{quota:"effective-quota-value",used:used,available:available}' 2>/dev/null \
  || $OCI limits resource-availability get --service-name compute --limit-name "$L" \
    --compartment-id "$T" --query 'data.{quota:"effective-quota-value",used:used,available:available}'
done
```

Expected: E4 and micro have quota 0 and available 0. Both A1 counts have quota 2
(available 2 while there is no node). E5 has quota 2, used 2 and available 0. The
regional count needs no `--availability-domain`, which is why there's a fallback.

**c. A real launch the quota must refuse.** This uses E2.1.Micro on purpose: if
the quota somehow fails, the instance is Always Free and costs nothing.
Never test by asking for more A1 than the quota: if that went through, it
would be billed and would break the Always Free size.

```bash
C=<compartment-ocid>                   # from terraform.tfvars of oke/ or k3s/
SUBNET=$($OCI network subnet list --compartment-id "$C" \
  --query 'data[?"display-name"==`k3s-node-public`].id | [0]' --raw-output)
IMAGE=$($OCI compute image list --compartment-id "$C" --operating-system "Oracle Linux" \
  --operating-system-version 9 --shape VM.Standard.E2.1.Micro \
  --sort-by TIMECREATED --sort-order DESC --limit 1 --query 'data[0].id' --raw-output)
echo "subnet ${#SUBNET} chars, image ${#IMAGE} chars"   # both must be > 0
$OCI compute instance launch --compartment-id "$C" --availability-domain "$AD" \
  --shape VM.Standard.E2.1.Micro --subnet-id "$SUBNET" --image-id "$IMAGE" \
  --assign-public-ip false --display-name quota-test-delete-me \
  --query 'data.id' --raw-output
```

- **Pass:** the launch is refused with an error that names a quota or a limit.
  Paste the error message (not the request id) into #113.
- **Inconclusive:** "Out of host capacity". Capacity was checked before the
  quota, so this proves nothing. Rely on check b, and repeat c another day.
- **Fail:** an instance OCID is printed. Terminate it at once, and do NOT
  upgrade:
  `oci compute instance terminate --instance-id <id> --preserve-boot-volume false --force --profile oke-demo --auth security_token`

**d. The A1 watcher** (`scripts/a1-wait-and-apply.sh`): its next attempt must
still fail with out of capacity, not with a quota error. A quota error there
means the A1 allowance is wrong. Fix it before upgrading.

## 3. Upgrade to Pay As You Go (owner, Console)

1. Billing & Cost Management > Upgrade and Manage Payment > Upgrade to Pay As You Go.
   Menu names may differ slightly; the upgrade starts from the Billing area.
2. Enter and verify the card. The upgrade can take a while to finish; Oracle
   sends an email when the account is upgraded.
3. Record the date and time in #113.

Do not change any quota or budget during the upgrade.

## 4. The next day

- **Budget email.** The first evaluation after the apply should send all three
  alerts, because OKE has already spent more than the tolerance this month.
  No email within about 26 h of the apply: check the spam folder, then Billing
  > Budgets > `oci-k8s-gitops-demo-tenancy-monthly` (its last evaluation time
  and "% spent"). Note in #113 whether the alerts came. It also shows whether
  budgets count usage that the trial credit paid for (Oracle does not document this).
- **Cost Analysis** (Billing & Cost Management > Cost Analysis, grouped by
  service, daily): Compute should still be about SGD 3/day for OKE, and nothing
  new should appear.
- **Credit or card?** Under Billing, the trial credit balance should still be
  going down by the daily spend, and there should be no new invoice. Note in
  #113 which one is paying for OKE now.
- **Limits went up, quotas still hold:** repeat step 2b. The service limits
  may now be higher; the effective quotas must be unchanged.

## 5. After the OKE teardown (#13)

Once `terraform destroy` in `terraform/oke` is done and Cost Analysis shows no
OKE compute:

1. Delete the three overlap lines (`e5_ocpus_quota`, `e5_memory_gbs_quota`,
   `block_storage_gbs_quota`) from `terraform/guardrails/terraform.tfvars`.
2. `terraform plan`: expect exactly 1 to change (the quota statements: E5 to 0,
   storage to 200). Then apply.
3. Repeat step 2b: E5 quota 0, storage quota 200.

## When a quota blocks something you need

Raise the variable in a PR (the validations put an upper bound on each one; going
above Always Free needs a code change and a new look at ADR 0021), then plan and
apply. Never edit or delete the quota policy in the Console: Terraform would
show drift, and the cap would be gone in the meantime.
