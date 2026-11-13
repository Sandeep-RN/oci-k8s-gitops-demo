# Terraform

One root per lifecycle, each with its own state key in the shared bucket:

| Root | What | Lifecycle |
|------|------|-----------|
| `oke/` | Short-lived OKE target (ADR 0015) | Served the site until 2026-11-12; destroy is issue #13 (due 2026-11-15) |
| `shared/` | Postgres backup bucket, lifecycle rule, write-only IAM for the nodes (ADR 0017) | Long-lived; bucket has `prevent_destroy` |
| `k3s/` | The Always Free k3s node and its network (ADR 0001, 0022): VCN, public subnet, security list (SSH from one CIDR, 80/443), one A1 instance | Long-lived; the instance has `prevent_destroy`. Applied; the node runs since 2026-11-11 |
| `guardrails/` | Tenancy quota policy (the hard cap) and one budget with three alert rules (ADR 0021) | Long-lived; tightened after the OKE teardown |

## One-time bootstrap (ADR 0003)

The compartment and the versioned state bucket are created outside Terraform:

```
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
scripts/bootstrap-state.sh     # idempotent; writes git-ignored backend.hcl and oke/terraform.tfvars
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

## OKE target (`oke/`, ADR 0015)

The OKE target served the site until 2026-11-12. It still exists with no
public way in; its teardown is issue #13 (due 2026-11-15).

```
cd terraform/oke
terraform init -backend-config=../backend.hcl
terraform plan -out=oke.tfplan      # expect 15 resources on first run
terraform apply oke.tfplan          # ~10-15 min; starts billing (about SGD 3.05 a day)
```

- Basic cluster (free control plane), 2 × `VM.Standard.E5.Flex` 1 OCPU / 8 GB
  (E4 had no host capacity; see Troubleshooting below), one per fault domain.
  A variable validation rejects A1 shapes.
- Private API endpoint and private workers. kubectl goes through OCI Bastion
  (ADR 0010); `bastion_client_cidr` in `terraform.tfvars` must be your current
  public IP as a /32.
- Every resource is tagged `lifecycle = ephemeral-oke`, `teardown_by = 2026-11-15`
  for the Cost Analysis check after `terraform destroy`.
- Outputs holding OCIDs or IPs are sensitive; read with `terraform output -raw <name>`.

### kubectl access (private API via Bastion)

```
scripts/oke-tunnel.sh                       # holds the tunnel open; Ctrl+C closes it
kubectl --kubeconfig ~/.kube/oke-demo.kubeconfig get nodes   # in another terminal
```

The script creates a throwaway SSH key and a Bastion port-forwarding session
(max 3 h), writes a kubeconfig outside the repo pointing at `127.0.0.1` with
`tls-server-name` set to the API's private IP, and deletes the session on exit.
`oci` must be on PATH, because kubectl calls it to fetch tokens.

### Troubleshooting: node pool fails with "Work request exceeded max retry count"

If the work-request logs show `Validating nodes: 0 provisioned, 0 provisioning`
until it gives up, the shape usually has no host capacity. Check, per fault
domain, without launching anything:

```
oci compute compute-capacity-report create --compartment-id <tenancy-ocid> \
  --availability-domain <ad-name> \
  --shape-availabilities '[{"instanceShape":"VM.Standard.E5.Flex","instanceShapeConfig":{"ocpus":1,"memoryInGBs":8},"faultDomain":"FAULT-DOMAIN-1"}]'
```

`OUT_OF_HOST_CAPACITY` means pick another x86 Flex shape whose service limit is
above zero (`oci limits value list --service-name compute`). The same check
applies to the A1 node.

## Shared resources (`shared/`, ADR 0017)

Outlives any one cluster. Copy `tenancy_ocid`, `compartment_ocid` and `region`
from `oke/terraform.tfvars` into a git-ignored `shared/terraform.tfvars`, then:

```
cd terraform/shared
terraform init -backend-config=../backend.hcl
terraform plan -out=shared.tfplan   # expect 5 resources: bucket, lifecycle rule, dynamic group, 2 policies
terraform apply shared.tfplan
```

The dynamic group needs permission to manage IAM at the tenancy root
(tenancy administrators have it).
