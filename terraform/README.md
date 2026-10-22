# Terraform

One root per lifecycle, each with its own state key in the shared bucket:

| Root | What | Lifecycle |
|------|------|-----------|
| `oke/` | Short-lived OKE target (ADR 0015) | Destroy by 2026-11-15 |
| `node/` (later) | Always Free k3s node, NLB (ADR 0001) | Long-lived, `prevent_destroy` |

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

- Basic cluster (free control plane), 2 × `VM.Standard.E4.Flex` 1 OCPU / 8 GB,
  one per fault domain. A variable validation rejects A1 shapes.
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
