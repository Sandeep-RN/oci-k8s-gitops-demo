# Terraform

One root per lifecycle, each with its own state key in the shared bucket:

| Root | What | Lifecycle |
|------|------|-----------|
| `shared/` | Postgres backup bucket, lifecycle rule, write-only IAM for the nodes (ADR 0017) | Long-lived; bucket has `prevent_destroy` |
| `k3s/` | The Always Free k3s node and its network (ADR 0001, 0022): VCN, public subnet, security list (SSH from one CIDR, 80/443), one A1 instance | Long-lived; the instance has `prevent_destroy`. Applied; the node runs since 2026-11-11 |
| `guardrails/` | Tenancy quota policy (the hard cap) and one budget with three alert rules (ADR 0021) | Long-lived; tightened to the Always Free steady state after the OKE teardown (2026-11-15) |

## One-time bootstrap (ADR 0003)

The compartment and the versioned state bucket are created outside Terraform:

```
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
scripts/bootstrap-state.sh     # idempotent; writes git-ignored backend.hcl and, if absent, a terraform.tfvars in shared/, k3s/ and guardrails/
```

Auth uses short-lived session tokens (`auth = "SecurityToken"`), not a
long-lived API key on disk. Refresh with `oci session refresh --profile oke-demo`.

## k3s node (`k3s/`, ADR 0001, 0022)

- The node is Always Free sized: variable validations refuse more than 2 OCPU
  or more than 12 GB of memory (`k3s/variables.tf`).
- cloud-init installs k3s and runs only at first boot, which is why `user_data`
  is ignored after creation (`ignore_changes` in `k3s/main.tf`).
- Reach the cluster with `scripts/k3s-tunnel.sh` and check it with
  `scripts/k3s-verify.sh`. See [k3s-access](../docs/runbooks/k3s-access.md) and
  [k3s-bootstrap](../docs/runbooks/k3s-bootstrap.md).

## Cost guardrails (`guardrails/`, ADR 0021)

- Holds one tenancy quota policy (the hard cap) and one budget with three
  alert rules (the alarm).
- Real values live only in the git-ignored `guardrails/terraform.tfvars`; the
  repo has placeholders only. Steps and checks are in
  [cost-guardrails](../docs/runbooks/cost-guardrails.md).

## Troubleshooting: "Out of host capacity" or a work request that gives up

If a create fails with `Out of host capacity`, or a work request logs
`Validating nodes: 0 provisioned, 0 provisioning` until it gives up, the shape
has no host capacity. Check without launching anything:

```
oci compute compute-capacity-report create --compartment-id <tenancy-ocid> \
  --availability-domain <ad-name> \
  --shape-availabilities '[{"instanceShape":"VM.Standard.A1.Flex","instanceShapeConfig":{"ocpus":2,"memoryInGBs":12},"faultDomain":"FAULT-DOMAIN-1"}]'
```

`OUT_OF_HOST_CAPACITY` means no host in that fault domain right now. A1
capacity appears in short windows: `scripts/a1-wait-and-apply.sh` polls for it
(kept as history of the 2026-11-11 wait, ADR 0001).

The retired OKE target (ADR 0015, destroyed 2026-11-15) lived in `oke/`; its
code was removed in demo #182, and the commit history has it.
## Shared resources (`shared/`, ADR 0017)

Outlives any one cluster. `scripts/bootstrap-state.sh` writes the git-ignored
`shared/terraform.tfvars` (`tenancy_ocid`, `compartment_ocid`, `region`), then:

```
cd terraform/shared
terraform init -backend-config=../backend.hcl
terraform plan -out=shared.tfplan   # expect 5 resources: bucket, lifecycle rule, dynamic group, 2 policies
terraform apply shared.tfplan
```

The dynamic group needs permission to manage IAM at the tenancy root
(tenancy administrators have it).
