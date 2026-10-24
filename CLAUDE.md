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

## Post ideas

The owner publishes a weekly post from real problems hit while building this
project. Capture them as they happen, as GitHub issues labelled `post-idea` in
this repo. That label is separate from the triage vocabulary above; do not
add triage labels to post ideas.

- **When to offer:** after resolving a non-obvious problem, hitting a
  surprising gotcha, or making a decision with a real trade-off, offer to log
  it. Ask first; never log silently.
- **Format:** four sections: **Problem**, **What I tried**, **What fixed it**,
  **What I still don't know**. Then one line: `Evidence:` a commit, PR, ADR or
  file path.
- **Public repo:** never put secrets, real OCIDs, tenancy or Object Storage
  namespaces, IP addresses, key fingerprints, account numbers, or anything
  about the owner's employer in an issue. Use obviously fake values
  (`ocid1.tenancy.oc1..aaaafake`, `203.0.113.10`).
- **Only real events:** log only what actually happened, with the actual
  outcome. Do not invent or round up results; "unresolved" is a valid answer.
- **No duplicates:** search existing `post-idea` issues first
  (`gh issue list -R Sandeep-RN/oci-k8s-gitops-demo --label post-idea --state all`).
- Logging an idea is not publishing it. Never post anything anywhere.
