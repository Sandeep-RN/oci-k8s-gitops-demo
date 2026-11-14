# Known limits and what comes next

As of 2026-11-14. This page lists what is still open, what the project does
not do, what I would do next, and what would change for a real production
system. It is the other half of the [README](../README.md).

## Open work

| Item | Issue | State |
|---|---|---|
| Tear down the OKE target, then tighten the quotas to the Always Free sizes | [#13](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/13), [#113](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/113) | Due 2026-11-15 |
| Rebuild the k3s cluster on the same VM from Git, the key backup and the data backup | [#57](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/57) | Runbook section written, not run |
| Final README pass and a 3-minute video | [#58](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/58) | After #13 and #57 |
| Count the sealing keys after the first renewal on k3s; a second key needs a new backup | [k3s-bootstrap](runbooks/k3s-bootstrap.md), step 2 | After 2026-11-23 |
| Alerts on k3s for certificate expiry, Traefik 5xx and a full disk (next step 11) | [#140](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/140) | Not started |
| Live checks on k3s: Prometheus memory, the Traefik ServiceMonitor, volume stats | [#141](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/141) | Not started |

## Known limits

These are accepted, each for a reason that is written down.

| Limit | Why it is accepted | ADR |
|---|---|---|
| One node. A reboot, a k3s upgrade or a Traefik restart is an outage | The constraint is $0 a month. Multi-node behaviour was shown on OKE | [0001](adr/0001-single-node-k3s-on-always-free-a1.md), [0022](adr/0022-moving-the-demo-from-oke-to-k3s.md) |
| One PostgreSQL replica on the node's disk. Up to 24 hours of data can be lost. The time to recover is not measured yet | Nightly dumps with a tested restore fit a demo. #57 measures the time | [0007](adr/0007-postgres-statefulset-with-dump-backups.md) |
| The public address is the node's own, sealed into the cluster by hand | The node is never destroyed, so the address does not change in practice | [0022](adr/0022-moving-the-demo-from-oke-to-k3s.md) |
| If the monitoring stack itself dies, nothing pages | The outside probe still runs, but only every few hours | [0019](adr/0019-in-cluster-synthetic-redirect-probe.md) |
| Backups use the node's identity, so any pod on the node could add objects to the backup bucket | The identity is write-only: it cannot read, overwrite or delete a backup | [0017](adr/0017-backup-auth-instance-principals-write-only.md) |
| No logs are kept beyond the pods' own | A log stack was cut for memory and time | [0011](adr/0011-workflow-and-scope.md) |
| No autoscaling and no load test | Both were first in the cut order | [0011](adr/0011-workflow-and-scope.md) |

## Next steps

These come from a review of all three repos on 2026-11-13, in the order I
would take them. Items marked Done were finished on 2026-11-13 or 2026-11-14;
the others are not started.

**Small, with no effect on the running site**

1. Done: `scripts/seal-link-tokens.sh` (gitops repo) writes to the k3s
   overlay (issue #171). It wrote to the OKE overlay, so a token change made
   as documented did not reach the live site.
2. Done: a mistaken delete is kept away from the database (issue #158).
   Removing the app's ArgoCD Application file would have deleted its namespace,
   and the database's volume claim with it. The Namespace is now marked so
   ArgoCD never deletes it, checked on the live cluster.
3. Done: CI for this repo (`.github/workflows/checks.yml`, issue #3) runs
   `terraform fmt`, `validate` and `test` for the four roots, shellcheck, and
   the offline script test.
4. Done, in a different way (issue #159): with three merges in quick
   succession, the change filter could skip the middle one. On `main`, the
   app's CI now compares the commit with the one that is deployed, not with the
   previous push, so a skipped run cannot hide a code change.
5. Partly done: Dependabot proposes updates for Actions (all three repos),
   Terraform providers and pre-commit hooks (this repo), and Python packages and
   the base image (app repo), issue #161. Not done: chart and image versions in
   the gitops repo, the base image pinned by digest, Python packages pinned with
   hashes.
6. Done: a secret-scan rule for public IPv4 addresses (`public-ipv4` in each
   repo's `.gitleaks.toml`, issue #167). IPv6 is not covered.

**Changes the running cluster (each needs a live check)**

7. NetworkPolicies: default deny in the app's namespace, then allow Traefik,
   Prometheus, the probe and the database paths. Block the cloud metadata
   address for every pod except the backup job. k3s ships a NetworkPolicy
   controller; it has not been tried on this node.
8. Pod Security labels on the namespaces. The workloads already run as
   non-root, read-only, with all capabilities dropped.
9. A dead man's switch: send the `Watchdog` alert to a heartbeat service.
10. A `preStop` sleep and a shutdown test for the backend. A terminating pod
    can still get a request for a moment; one 502 was seen on 2026-11-02.
11. Alerts for certificate expiry and for a full disk on the `local-path`
    volumes.
12. Scan the pushed multi-arch image, sign it, and attach an SBOM.
13. A GitHub App instead of a personal access token for the tag-bump pull
    request.
14. A load test, to find what breaks first on 2 OCPU.

## What would change at scale

Each ADR ends with an "At scale" section. In short:

- **Cluster:** three or more nodes across availability domains with a managed
  control plane, so a drain or a node failure is not an outage.
- **Data:** a managed PostgreSQL, or an operator with replicas and continuous
  WAL archiving, for a recovery point of minutes instead of a day.
- **Edge:** a load balancer that keeps client IPs and a reserved address,
  instead of one node's own. Rate-limit state shared between replicas, or
  moved to a CDN or WAF.
- **Delivery:** promotion between environments (today one image tag in the
  base reaches every cluster at once), progressive rollouts, one ArgoCD
  project per team.
- **Secrets:** a managed secret store with workload identity, and keys per
  cluster.
- **Infrastructure:** `terraform plan` in CI with short-lived cloud identity,
  drift detection, shared modules instead of four copies of the provider
  block.
- **Observability:** SLO rules from a generator instead of long raw windows,
  long-term metric storage, logs and traces, and paging with escalation
  instead of one chat channel.
- **Cost:** quotas per team as hard caps, budgets per cost centre, and an
  automated response to a budget event.
