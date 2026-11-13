# 0023. ArgoCD, app of apps, automated sync with prune and self-heal

Status: Accepted. Decided when the project was planned (2026-10-21) and built
in gitops PR #5 (2026-10-23); recorded later, on 2026-11-13. Earlier ADRs
(0006, 0009, 0014, 0015, 0018) already assume it.

## Context
- The Kubernetes API is not public (ADR 0010), and CI never touches a cluster
  (ADR 0009). A deploy tool that pushes from GitHub Actions cannot reach the
  cluster. An agent inside the cluster has to pull from Git.
- The gitops repo is the source of truth and is public. Every change to the
  cluster should be a reviewed, merged pull request, and drift made by hand
  should not survive.
- The same repo had to drive two clusters (OKE and k3s, ADR 0015 and 0022),
  and a cluster had to be rebuildable from Git plus a few restored keys
  (ADR 0001, 0006).
- The two common pull-based tools are ArgoCD and Flux. Both reconcile from
  Git, both support Kustomize and Helm.

## Decision
- **ArgoCD**, the upstream non-HA install, pinned
  (`argocd/install/kustomization.yaml`). After the first install, ArgoCD
  manages its own installation from that folder; upgrading it is a version
  change in a PR.
- **App of apps, one root per cluster.** `argocd/clusters/<cluster>/root.yaml`
  is the one manual apply after the install. It creates one Application per
  component from `argocd/clusters/<cluster>/apps/`. Sync waves create the
  foundations first (the AppProject, Sealed Secrets, cert-manager and
  monitoring at wave -1).
- **Automated sync with `prune: true` and `selfHeal: true`** on the root and
  the apps: a merged change is applied without a click, a file removed from
  Git is removed from the cluster, and a manual change is reverted. The team
  rule that follows: no `kubectl apply`, `edit` or `scale` once ArgoCD runs
  (`docs/runbooks/access.md`). The only planned exception is restoring the
  sealing keys, which must never be in Git (ADR 0006).
- **Deliberate exceptions, each commented in the manifest:**
  - ArgoCD's own Application has `prune: false`, so a bad commit can never
    make ArgoCD delete parts of itself.
  - The root has no resources finalizer, so deleting the root does not
    cascade-delete every app it created.
  - Workload apps get their own AppProject (`demo`), limited to this repo and
    the `link-shortener` namespace.

Why ArgoCD over Flux, for this project:
- Per-Application sync and health status, in a UI and in `kubectl get
  applications`. The runbooks and the evidence use it directly ("root-k3s and
  9 child Applications Synced/Healthy 3.5 minutes after `root.yaml`",
  `docs/evidence/k3s-bootstrap-2026-11-12.md`). The UI is reached by
  port-forward only (ADR 0014).
- Sync hooks and waves, which the app relies on: the database role is set by
  an ArgoCD Sync hook Job on every sync (ADR 0018).
- Flux would use fewer resources on a 2 OCPU / 12 GB node and has no
  component that serves a UI. That was the main point against ArgoCD; the
  node has had room for it.

## Consequences
- A rebuild is short and repeatable: install ArgoCD, restore the sealing key,
  apply the root. On k3s that took 3.5 minutes from `root.yaml` to all apps
  Healthy.
- **A merge to `main` deploys at once.** There is no staging environment; the
  checks in the gitops repo (`validate`) are the gate.
- **Removing a file is a delete.** Deleting or renaming an Application file
  makes the root prune it. An app with the resources finalizer (link-shortener)
  then deletes what it deployed, including its namespace and, with it, the
  Postgres volume claim. The tracked fix is `Delete=false` on the namespace
  (roadmap). The OKE teardown order exists for the same reason.
- Some manual actions leave drift that self-heal does not clear (for example
  the `restartedAt` annotation from `rollout restart`; see
  `docs/runbooks/sealed-secrets.md`, gotcha 2). Restart by deleting a pod.
- ArgoCD's own pods (server, repo server, application controller, Redis,
  ApplicationSet and notifications controllers, Dex) use memory on the one
  node. They have no requests or limits yet, because `argocd/install` was
  shared with OKE.
- Only the workload app is fenced by an AppProject. The platform apps
  (cert-manager, external-dns, monitoring, Sealed Secrets and the others)
  still use the unrestricted `default` project.

## At scale
ApplicationSets to generate the per-cluster apps instead of copying them;
one AppProject per team with explicit destinations; SSO with RBAC instead of
the admin login; sync windows; notifications to chat; the HA install; and a
staging cluster that a change reaches before production.
