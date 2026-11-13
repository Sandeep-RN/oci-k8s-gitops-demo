# Working in this repo

- **Pull requests only.** `main` needs a pull request and a linear history
  (ADR 0011).
- **An issue first.** Every task starts from an issue in its phase milestone.
  This repo tracks the issues of all three repos, so pull requests in the other
  two close them with the full reference:
  `Closes Sandeep-RN/oci-k8s-gitops-demo#N`.
- **A change of approach needs a new ADR** in `docs/adr/`. An ADR is not
  rewritten later: its status line points to the ADR that amends or replaces
  it. The index is [docs/adr/README.md](docs/adr/README.md).
- **Install the hooks once:** `pip install pre-commit && pre-commit install`.
  They run gitleaks (with custom OCI rules in `.gitleaks.toml`),
  `terraform fmt` and `terraform validate`. CI scans the full history with
  gitleaks too, because `git commit --no-verify` skips hooks.
- **This repo is public.** Never commit tfstate, real `*.tfvars`, OCI keys,
  kubeconfig, OCIDs, public IPs, passwords or tokens. Use `example.tfvars`
  with placeholders.
- **Terraform is applied by hand**, by the owner, with a short-lived session
  token. There is no Terraform check in CI yet; see
  [docs/roadmap.md](docs/roadmap.md).
- **Docs say only what was run.** A runbook step or a number in
  `docs/evidence/` comes from a real run. If something was not run, the doc
  says so.
