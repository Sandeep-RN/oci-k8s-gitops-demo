# Terraform

One root per lifecycle, each with its own state key in the shared bucket:

| Root | What | Lifecycle |
|------|------|-----------|
| `oke/` | Short-lived OKE target (ADR 0015) | Destroy by 2026-11-15 |
| `shared/` | Postgres backup bucket, lifecycle rule, write-only IAM for the nodes (ADR 0017) | Long-lived; bucket has `prevent_destroy` |
| `k3s/` | Always Free k3s node and network (ADR 0001); the network is applied, the node waits for A1 capacity. Edge and DNS per ADR 0020 (no reserved IP; external-dns) | Long-lived, `prevent_destroy`; not applied yet (waiting for A1 capacity, `scripts/a1-wait-and-apply.sh`) |

## One-time bootstrap (ADR 0003)

The compartment and the versioned state bucket are created outside Terraform:

```
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
scripts/bootstrap-state.sh     # idempotent; writes git-ignored backend.hcl and oke/terraform.tfvars
```

Auth uses short-lived session tokens (`auth = "SecurityToken"`), not a
long-lived API key on disk. Refresh with `oci session refresh --profile oke-demo`.

## OKE target (`oke/`, ADR 0015)

```
cd terraform/oke
terraform init -backend-config=../backend.hcl
terraform plan -out=oke.tfplan      # expect 15 resources on first run
terraform apply oke.tfplan          # ~10-15 min; starts billing (~$2/day)
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
