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
