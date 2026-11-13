# Architecture decision records

One record per decision. A record is not rewritten when things change: the status line points to the record that amends or replaces it.

| # | Decision | Status | Amended or superseded by |
|---|---|---|---|
| [0001](0001-single-node-k3s-on-always-free-a1.md) | Single-node k3s on one Always Free A1 VM (2 OCPU / 12 GB), protected from destroy | Accepted | Amended by 0022 |
| [0002](0002-ubuntu-2404-aarch64-node-os.md) | Ubuntu 24.04 aarch64 as the node OS | Accepted | |
| [0003](0003-terraform-state-in-object-storage.md) | Terraform state in a versioned Object Storage bucket, native `oci` backend | Accepted | |
| [0004](0004-nlb-tls-passthrough-to-traefik.md) | NLB with TCP passthrough to Traefik; TLS in the cluster; standard Ingress | Partly superseded | 0020, 0022 |
| [0005](0005-cert-manager-cloudflare-dns01.md) | cert-manager with Let's Encrypt DNS-01 through Cloudflare | Accepted | Amended by 0020 |
| [0006](0006-sealed-secrets.md) | Sealed Secrets, with every sealing key backed up offline | Accepted | |
| [0007](0007-postgres-statefulset-with-dump-backups.md) | One Postgres replica as a StatefulSet, nightly `pg_dump` to Object Storage | Accepted | Amended by 0017, 0022 |
| [0008](0008-observability-and-slo.md) | kube-prometheus-stack, a 7-day redirect SLO, multi-window burn-rate alerts to Discord | Accepted | Amended by 0019 |
| [0009](0009-ci-commits-image-tag-to-gitops-repo.md) | CI opens an auto-merging tag-bump pull request in the gitops repo; CI never touches a cluster | Accepted | |
| [0010](0010-node-access-ssh-tunnel.md) | SSH key-only from one CIDR, no public Kubernetes API, kubectl through a tunnel | Accepted | Amended by 0022 |
| [0011](0011-workflow-and-scope.md) | Pull-request workflow, core and stretch scope, cut order | Accepted | |
| [0012](0012-node-firewall-and-cloud-init.md) | cloud-init opens the image's host firewall; the security list is the gate | Accepted | Amended by 0022 |
| [0013](0013-dns-and-reserved-ip.md) | Reserved public IP and a Terraform-managed DNS record | Superseded | 0020, 0022 |
| [0014](0014-admin-ui-access.md) | Admin UIs only through port-forward | Accepted | |
| [0015](0015-oke-ephemeral-second-target.md) | OKE as a short-lived second target on trial credit | Accepted (served until 2026-11-12; teardown is issue #13) | Amended by 0020, 0022 |
| [0016](0016-readiness-checks-pod-local-state-only.md) | Readiness checks pod-local state only | Accepted | Amended by 0019 |
| [0017](0017-backup-auth-instance-principals-write-only.md) | Backups authenticate as the instance, with a write-only policy | Accepted | |
| [0018](0018-app-database-role-least-privilege.md) | The backend uses its own non-superuser Postgres role | Accepted | Amended by 0022 |
| [0019](0019-in-cluster-synthetic-redirect-probe.md) | An in-cluster synthetic probe feeds the redirect SLO | Accepted | |
| [0020](0020-tls-and-public-hostname-on-oke.md) | TLS and the public hostname on OKE: Traefik, external-dns, token-gated link creation | Accepted | Amended by 0021 (one context line), 0022 (k3s parts) |
| [0021](0021-pay-as-you-go-with-guardrails.md) | Pay As You Go, with a tenancy quota policy as the cap and a budget as the alarm | Accepted | |
| [0022](0022-moving-the-demo-from-oke-to-k3s.md) | Moving to k3s: edge with no load balancer, real client IPs, reused sealing key, data moved, rebuild on the same VM | Accepted | |
| [0023](0023-argocd-app-of-apps-with-prune-and-self-heal.md) | ArgoCD, one app-of-apps root per cluster, automated sync with prune and self-heal (recorded later) | Accepted | |
| [0024](0024-secret-scanning-in-layers.md) | Secret scanning in layers: gitleaks hook, full-history gitleaks in CI, GitHub push protection; custom OCI rules (recorded later) | Accepted | |

## Where to start

- [0016](0016-readiness-checks-pod-local-state-only.md): readiness checks only what is local to a pod, because a shared database in readiness removed every pod at once; the trade-off is that a pod can be "ready" while it can only answer 503.
- [0022](0022-moving-the-demo-from-oke-to-k3s.md): k3s has no load balancer and uses `externalTrafficPolicy: Local` to see real client IPs; the trade-off is a single node, so a reboot is an outage.
- [0021](0021-pay-as-you-go-with-guardrails.md): the account went Pay As You Go only after a tenancy quota policy (the hard cap) and a budget (only an alarm) were proven; the trade-off is that a budget alert can arrive a day late, so the quota carries the protection.
- [0009](0009-ci-commits-image-tag-to-gitops-repo.md): CI opens an auto-merging tag-bump pull request in the gitops repo instead of touching a cluster; the trade-off is one extra token to protect and a fast check that auto-merge must wait on.
- [0017](0017-backup-auth-instance-principals-write-only.md): backups authenticate as the instance with a write-only policy, so a compromised pod cannot read or delete them; the trade-off is that any pod on the node can still upload junk.
- [0019](0019-in-cluster-synthetic-redirect-probe.md): an in-cluster blackbox probe sends a request every 30 s so the SLO works with no visitors; the trade-off is that the SLI is mostly synthetic and measures the path from inside the cluster.
