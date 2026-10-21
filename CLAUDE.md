# oci-k8s-gitops-demo (infra + docs)

Workspace-level rules and PLAN.md live one folder up. Read them first.

- This repo: Terraform for OCI, architecture docs, ADRs, runbooks.
- Keep instance shape/size in variables (OCPU, memory, node count). The node
  is free-sized (2 OCPU / 12 GB) from day 1 (ADR 0001); trial credit is for
  disposable experiments only.
- Run `terraform fmt` and `terraform validate` before committing.
- Never commit tfstate, tfvars with real values, keys or OCIDs. Provide
  `example.tfvars` with placeholders only.
- Every change of approach gets an ADR in docs/adr/.

## Agent skills

### Issue tracker

GitHub Issues on Sandeep-RN/oci-k8s-gitops-demo via the `gh` CLI; this repo tracks work for all three repos. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one GLOSSARY.md and docs/adr/ at the repo root. See `docs/agents/domain.md`.
