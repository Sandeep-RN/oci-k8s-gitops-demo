# Known limits and what comes next

As of 2026-11-13. This page lists what is still open, what the project does
not do, what I would do next, and what would change for a real production
system. It is the other half of the [README](../README.md).

## Open work

| Item | Issue | State |
|---|---|---|
| Tear down the OKE target, then tighten the quotas to the Always Free sizes | [#13](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/13), [#113](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/113) | Due 2026-11-15 |
| Rebuild the k3s cluster on the same VM from Git, the key backup and the data backup | [#57](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/57) | Runbook section written, not run |
| Final README pass and a 3-minute video | [#58](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/58) | After #13 and #57 |
| Count the sealing keys after the first renewal on k3s; a second key needs a new backup | [k3s-bootstrap](runbooks/k3s-bootstrap.md), step 2 | After 2026-11-23 |

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
would take them. None is started.

**Small, with no effect on the running site**

1. Point `scripts/seal-link-tokens.sh` (gitops repo) at the k3s overlay. It
   still writes to the OKE overlay, so a token change made as documented would
   not reach the live site.
2. Keep a mistaken delete away from the database. Today, removing the app's
   ArgoCD Application file would delete its namespace, and the database's
   volume claim with it. Marking the Namespace so ArgoCD never deletes it
   closes that path.
3. CI for this repo: `terraform fmt` and `validate` for the four roots,
   shellcheck, and the script test that exists but never runs. Today only the
   pre-commit hook checks them.
4. Make the app's CI build every commit on `main`. With three merges in quick
   succession, the change filter can skip the middle one.
5. Automated dependency updates for charts, images, Actions and providers. Pin
   the app's base image by digest and its Python packages with hashes.
6. A secret-scan rule for public IP addresses. The rule against committing
   them is enforced only by review today.

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
