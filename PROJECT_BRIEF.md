# Project brief: oci-k8s-gitops-demo

The single source of facts about this project for anything written about it
somewhere else: a resume, a portfolio page, a profile, a post, an interview
answer. **Last verified: 2026-11-14.**

## How to use this file

For a person, or for an AI assistant working in another project:

1. **Use only the facts and numbers in this file.** Each number has a source.
   Do not round up, combine numbers, or add a number that is not here.
2. **This is a personal project.** It is not work done for an employer, and it
   must never be described as production experience.
3. **Do not claim what the "Not done" section lists.** Saying the limits out
   loud is part of how this project is presented.
4. **Prefer the ready-made text** in "Ready to use" to writing new claims.
5. **Check the date above.** Two items are still open (the OKE teardown and the
   rebuild proof). "What changes next" at the end says which lines to update
   when they close. If this file is more than a month old, read the
   [README](README.md) first.
6. **Ask the owner** for anything that is missing. Do not fill a gap by guessing.

## Summary

**One line.** A production-shaped Kubernetes platform on one free Oracle Cloud
VM: GitOps delivery, an SLO with burn-rate alerts, tested backups, and every
decision written down.

**50 words.** A small link-shortener service on Kubernetes (k3s) on Oracle
Cloud's free tier. Every change is delivered through Git: CI builds and scans
the image, a pull request changes the tag, ArgoCD deploys it. It has HTTPS, an
availability SLO with burn-rate alerts, nightly backups with tested restores,
and 24 recorded decisions.

**150 words.** I wanted to run Kubernetes the way a production service should
be run, at a cost of zero. The free ARM capacity I planned for was unavailable
for three weeks, so I first built everything on a two-node managed cluster
(OKE) paid from trial credit, and used it for the tests one node cannot show: a
node drain under live traffic (1264 requests, 0 failed) and a rollout under
traffic (514 requests, 0 failed, about 7 minutes from merge to live). Free
capacity only arrived after I upgraded the account, which I did only after a
quota policy was in place as a hard spending cap and proven to refuse a launch.
I then rebuilt the stack on a single-node k3s cluster from Git (every
application healthy 3.5 minutes after the root was applied), restored all 34
database rows from backup, and made the cutover with one pull request: the DNS
record was absent for 25 seconds.

## Status

Live at <https://demo.sandeeprn.in> on a single-node k3s cluster since
2026-11-12. The OKE target served the site until 2026-11-12. It still exists
with no public way in; its teardown is issue
[#13](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/13) (due
2026-11-15).

## Facts

| | |
|---|---|
| Name | oci-k8s-gitops-demo |
| Kind | Personal project. One person: design, decisions, build, operation |
| Period | 2026-10-20 to 2026-11-14 for the build; two open items below |
| Repos (public) | [infrastructure and docs](https://github.com/Sandeep-RN/oci-k8s-gitops-demo), [application and CI](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app), [Kubernetes manifests](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-gitops) |
| Live URL | <https://demo.sandeeprn.in> (landing page with a working short link; API page at `/docs`) |
| Cloud | Oracle Cloud Infrastructure. One Always Free Ampere A1 VM: 2 OCPU, 12 GB, arm64, Ubuntu 24.04. (Oracle's [Always Free page](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) gives 1,500 OCPU hours and 9,000 GB hours a month, "equivalent to 2 OCPUs and 12 GB of memory"; checked 2026-11-13) |
| Kubernetes | k3s v1.36 on one node (today). OKE, two nodes, for the multi-node tests (2026-10-22 to 2026-11-12) |
| Size of the work | 162 merged pull requests (16 of them automated image-tag bumps, 5 from Dependabot), 24 ADRs, 8 runbooks, 3 evidence write-ups |
| Cost | Target $0 a month. The OKE target cost about SGD 3.05 a day, paid from trial credit |
| Built with | An AI coding assistant, Claude Code. See "How it was built" |

**Tools, by layer** (use these exact names for skills and tags):

| Layer | Tools |
|---|---|
| Infrastructure as code | Terraform (OCI provider, remote state in Object Storage), cloud-init, Bash |
| Kubernetes | k3s, OKE, Kustomize (base and overlays), Helm |
| GitOps | ArgoCD (app of apps, automated sync with prune and self-heal), Sealed Secrets |
| CI/CD | GitHub Actions, Docker (multi-arch: amd64 and arm64), GHCR, Trivy, gitleaks, pre-commit |
| Edge | Traefik, cert-manager, Let's Encrypt (DNS-01), external-dns, Cloudflare DNS |
| Observability | Prometheus, Alertmanager, Grafana, kube-prometheus-stack, blackbox exporter, SLOs, multi-window burn-rate alerts, promtool tests |
| Data | PostgreSQL (StatefulSet), `pg_dump` backups to Object Storage, restore drills |
| Application | Python, FastAPI, pytest |
| Practice | ADRs, runbooks, pull requests only, issue-first tracking, cost guardrails (OCI quota policy and budget) |

## Results

Every row has a source. The README has the same table; keep the two equal.

| What was tested | Result | Source |
|---|---|---|
| A change, from merge to running in the cluster | About 7 minutes, no manual step | [evidence 2026-11-08](docs/evidence/oke-final-2026-11-10.md) |
| Rollout under live traffic | 514 requests, 0 failed | same |
| Node drain under live traffic (two nodes) | 1264 requests, 0 failed. The disruption budget refused the drain that would have taken the last pod | same |
| SLO alert on a real outage | A planned 5-minute database outage fired the critical alert to Discord 7.5 minutes after it began; it then resolved | [#53](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/53) |
| A whole cluster from Git | On a new node, 10 ArgoCD Applications were Synced and Healthy 3.5 minutes after the root Application was applied (after the key restore and the ArgoCD install) | [evidence 2026-11-12](docs/evidence/k3s-bootstrap-2026-11-12.md) |
| Moving the live site to another cluster | The cutover was one pull request. DNS record absent for 25 seconds. All 34 rows restored | same |
| Backup and restore | Nightly dumps. Restored twice: a drill on 2026-10-25, and for real in the move on 2026-11-12 | [runbook](docs/runbooks/postgres-backup-restore.md) |
| Image scan gate | Blocked a real HIGH CVE before the image was pushed | [evidence 2026-11-08](docs/evidence/oke-final-2026-11-10.md) |
| Rate limit per client | One client's burst of 600 requests got 282 answers of 429. That Traefik sees each client's own address was measured with a packet capture. Not run: the check that a second client still gets 200 during the burst | [#115](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/115), [ADR 0022](docs/adr/0022-moving-the-demo-from-oke-to-k3s.md) |
| Spend cap | A launch outside the allowed shapes was refused by the quota policy | [ADR 0021](docs/adr/0021-pay-as-you-go-with-guardrails.md), [#113](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/113) |

How to quote these honestly:

- The drain, rollout and alert tests ran on the **two-node OKE target**, not on
  the single k3s node.
- The traffic in those tests was **under one request a second**. They show
  that planned disruptions lose no requests. They are not load tests.
- The SLO is 99.5% of redirects over 7 days. It is a target with alerts. It is
  **not** a measured uptime figure, so never write "99.5% uptime".
- **25 seconds** is how long the DNS record was absent. It is not a downtime
  figure: a resolver could keep the old address for up to 5 minutes, and what
  users saw was not measured. Before the one pull request came a key restore,
  two manual applies and a data restore (about 35 minutes).
- In the alert test the page arrived **after** the 5-minute outage had ended
  (outage 13:07:11 to 13:12:49, page 13:14:39). Say "paged 7.5 minutes after
  the outage began", never "detected the outage in real time".
- "Paged" means a message in a Discord channel. There is no pager and no
  on-call rota.

## The story

1. **The goal.** Show Kubernetes, CI/CD, GitOps and observability working
   together on a real, public service, built so it can stay up for $0 a month.
2. **The first problem: no capacity.** From 2026-10-22 the free ARM VM could not
   be created: the region had no capacity. A polling script kept trying. Rather
   than wait, the whole stack was built on a two-node managed cluster (OKE) paid
   from trial credit, with a teardown date set on day one
   ([ADR 0015](docs/adr/0015-oke-ephemeral-second-target.md)).
3. **Reliability, proven.** On OKE: the pipeline end to end, an SLO whose alert
   was fired by a planned outage, backups with a restore drill, a node drain
   and a rollout under live traffic with no failed request. A real HTTPS
   hostname followed on 2026-10-31
   ([ADR 0020](docs/adr/0020-tls-and-public-hostname-on-oke.md)).
4. **The cost decision.** Upgrading the account to Pay As You Go was the one
   lever left to get free capacity. A budget on OCI only sends an email, up to a
   day late, so a quota policy went in first as a hard cap and was proven with
   a launch that had to fail
   ([ADR 0021](docs/adr/0021-pay-as-you-go-with-guardrails.md)). The free VM was
   created in the same minute as the upgrade, on 2026-11-11.
5. **The move.** k3s on one node has no load balancer. A packet capture showed
   how to keep real client IPs without one, which also made the rate limit per
   client ([ADR 0022](docs/adr/0022-moving-the-demo-from-oke-to-k3s.md)). On
   2026-11-12 the cluster was built from Git, the data restored, and the live
   hostname moved by one pull request.
6. **What is honest about it.** One node is not highly available, and the docs
   say so. The multi-node proofs were made where they could be made. Every
   limit is listed in [docs/roadmap.md](docs/roadmap.md).

## Decisions and why

| Decision | Why | ADR |
|---|---|---|
| CI opens a pull request that changes the image tag; ArgoCD pulls it | No cluster credential exists outside the cluster, and Git is the audit log | [0009](docs/adr/0009-ci-commits-image-tag-to-gitops-repo.md) |
| Readiness checks only the pod itself | A database check in readiness removed every pod at once and hid the errors from the SLO | [0016](docs/adr/0016-readiness-checks-pod-local-state-only.md) |
| An SLO with multi-window burn-rate alerts | Page on budget burn, not on every blip | [0008](docs/adr/0008-observability-and-slo.md) |
| A synthetic probe inside the cluster | GitHub ran the outside probe every few hours, not every few minutes | [0019](docs/adr/0019-in-cluster-synthetic-redirect-probe.md) |
| Backups with a write-only identity | A compromised pod cannot read or delete backups | [0017](docs/adr/0017-backup-auth-instance-principals-write-only.md) |
| The app uses its own database role, not the superuser | Least privilege | [0018](docs/adr/0018-app-database-role-least-privilege.md) |
| Secrets in Git as Sealed Secrets | The repos are public; the key is backed up offline and its restore was drilled | [0006](docs/adr/0006-sealed-secrets.md) |
| A quota policy as the cap, a budget as the alarm | A budget cannot stop spend | [0021](docs/adr/0021-pay-as-you-go-with-guardrails.md) |
| No load balancer on k3s | Real client IPs and no cost; the price is no redundancy at the edge | [0022](docs/adr/0022-moving-the-demo-from-oke-to-k3s.md) |
| One node on the free tier | $0 a month; high availability is given up, and said so | [0001](docs/adr/0001-single-node-k3s-on-always-free-a1.md) |

All 24: [docs/adr/README.md](docs/adr/README.md).

## Problems found and fixed

Each one happened. The issue has the detail.

| Problem | Cause | Fix |
|---|---|---|
| The SLO missed errors during a database outage ([#61](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/61)) | Readiness checked the shared database, so every pod left the Service and requests were refused, not counted | Readiness checks only the pod; the app answers a fast 503 that the SLO counts (ADR 0016) |
| The paging alert did not fire in the first live test ([#53](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/53)) | Three 15-second outages are about 2.5% of the hour: below the paging threshold, correctly | A sustained 5-minute outage was designed; the alert fired and resolved |
| "Must spread across nodes" left both pods on one node ([#76](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/76)) | The spread rule counted pods of the old and new version together during a rollout | Spread per ReplicaSet (`matchLabelKeys`); checked over three rollouts |
| Public DNS got a private address ([#99](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/99)) | The load balancer reported its private IP too, and external-dns published it | Private ranges are excluded |
| The rate limit never fired ([#106](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/106)) | The load balancer hid client IPs, so all clients shared a few buckets | On k3s, `externalTrafficPolicy: Local` keeps client IPs, measured with a packet capture (ADR 0022) |
| A token test passed for the wrong reason ([#105](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/105)) | The variable held another token's value, so the 201 proved nothing | Check the outcome (`created_by` on the stored link), not only the status code |
| No free capacity for three weeks ([#111](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/111)) | Not documented by Oracle. A trial account in a region with one availability domain never got the free ARM shape | Guardrails first, then Pay As You Go; capacity arrived the same minute (ADR 0021) |
| The scan gate failed a one-line change ([#117](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/117)) | Two fixable HIGH CVEs had appeared in the base image | Upgrade that package in the Dockerfile; the gate did its job |
| The cutover was blocked by my own CI rule ([#133](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/133)) | CI required an Ingress in every overlay; the cutover had to delete one | The same pull request reversed the rule for the old cluster |
| The key backup was too long for the password manager ([#132](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/132)) | An annotation held the private key a second time | A minimal export of the key |

## Not done

Do not claim any of these.

- **High availability.** One node. A reboot or an upgrade is an outage.
- **A rebuild of the k3s cluster.** The runbook section is written, not run
  ([#57](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/57)).
- **Load or performance testing.** None. The tests ran at under one request a
  second.
- **Autoscaling, NetworkPolicies, a log stack, a dead man's switch** for the
  monitoring stack.
- **Terraform plan or apply in CI.** CI runs only offline checks (`fmt`,
  `validate`, `test`, no cloud credentials). `plan` and `apply` are run by
  hand from a laptop.
- **A measured uptime figure** or a measured recovery time.
- **Database replication.** One replica; up to 24 hours of data can be lost.

The full list, with what would come next: [docs/roadmap.md](docs/roadmap.md).

## How it was built

Built between 2026-10-20 and 2026-11-14 with an AI coding assistant (Claude
Code). The assistant wrote much of the YAML, Terraform and scripts, and first
drafts of the docs. The owner made the decisions, applied the infrastructure,
ran or supervised every live test, and reviewed and merged the pull requests.
A second model reviewed the first ADRs and found real errors. The `CLAUDE.md`
files in the three repos are the instructions given to the assistant.

When this project is described anywhere, say this plainly if asked. The skill
shown is deciding, verifying and operating, not typing YAML.

## Ready to use

### Resume bullets

Pick three to five. Do not merge two bullets into one bigger claim.

- Built a GitOps delivery pipeline (GitHub Actions, Trivy, ArgoCD) in which a
  merge reaches the cluster in about 7 minutes with no manual step and no
  cluster credentials outside the cluster.
- Defined a 7-day availability SLO with multi-window burn-rate alerts
  (Prometheus, Alertmanager) and proved the critical alert with a planned
  outage; found and fixed a readiness-probe design that hid errors from the
  SLO.
- Moved a live service between Kubernetes clusters (two-node OKE to
  single-node k3s): the new cluster synced from Git in 3.5 minutes, every
  database row was restored from backup, and the cutover was one reviewed pull
  request with the DNS record absent for 25 seconds.
- Showed that planned disruptions lose no requests on a two-node cluster: a
  node drain (1264 requests) and a rollout (514 requests) under live traffic,
  0 failed, using PodDisruptionBudgets and topology spread.
- Put a hard spending cap on a cloud account as code (Terraform, OCI quota
  policy) and proved it by a launch it had to refuse, before enabling pay as
  you go; the service is designed to cost $0 a month.
- Recorded 24 architecture decisions and wrote 8 runbooks; nightly PostgreSQL
  backups with a write-only identity, restored twice.

### Portfolio card

```yaml
title: "Kubernetes GitOps Platform on OCI Free Tier"
description: "A production-shaped service on one free VM: ArgoCD GitOps delivery in about 7 minutes from merge to live, a 7-day SLO with burn-rate alerts proven by a planned outage, tested backups, and a live move between clusters with 25 seconds without a DNS record."
tags: ["Kubernetes", "ArgoCD", "GitOps", "Terraform", "Prometheus", "SLI/SLO", "GitHub Actions", "OCI"]
status: "in-progress"   # change to "done" when #13 and #57 are closed
date: "2026-11"
github: "https://github.com/Sandeep-RN/oci-k8s-gitops-demo"
```

### Short texts

**Two sentences.** I built and operate a small public service on Kubernetes
the way I would want a production one run: delivered only through Git, with an
SLO that alerts, backups that were restored, and every decision written down.
It runs on one free Oracle Cloud VM. I moved it there from a two-node cluster,
and the cutover was one pull request with the DNS record absent for 25
seconds.

**Profile line.** Kubernetes GitOps platform on OCI's free tier: ArgoCD,
Terraform, an SLO with burn-rate alerts, tested backups. Live at
demo.sandeeprn.in.

**Project description (about 100 words).** A link-shortener service run as a
production one should be, on Oracle Cloud's free tier. GitHub Actions builds,
scans and pushes a multi-arch image, a pull request changes the tag, and
ArgoCD deploys it: about 7 minutes from merge to live. The service has HTTPS
with automatic certificates, a 7-day availability SLO with burn-rate alerts
that I proved with a planned outage, and nightly backups I have restored
twice. On a two-node cluster I drained a node under live traffic with no
failed request. I then moved the live site to a single free VM; the cutover
was one pull request. 24 decisions and 8 runbooks are in the repo.

### Diagram in plain ASCII

For pages that cannot render Mermaid.

```
  Developer --merge--> GitHub Actions --image--> GHCR
                       (test, build, scan)
                               |
                               | tag-bump pull request
                               v
                          gitops repo
                               ^
                               | pulls, then applies
  +----------------------------|-------------------------------+
  | One free VM (Ampere A1, 2 OCPU / 12 GB) running k3s        |
  |                            |                               |
  |   ArgoCD ------------------+                               |
  |                                                            |
  |   Traefik ------> link shortener x2 ------> PostgreSQL     |
  |   (TLS, HSTS,                                    |         |
  |    rate limit)                                   |         |
  |                                                  |         |
  |   Prometheus + Alertmanager                      |         |
  +------^---------------|---------------------------|---------+
         |               v                           v
      Visitor         Discord                 Object Storage
      (HTTPS)       (SLO alerts)             (nightly backups)
```

## Links

- Live site: <https://demo.sandeeprn.in>
- Start here: [README](README.md), then [docs/architecture.md](docs/architecture.md)
- Decisions: [docs/adr/README.md](docs/adr/README.md)
- Proof: [docs/evidence/](docs/evidence/)
- Videos: [node drain, 2:00](https://youtu.be/ypoLkJUmsCI), [rollout under traffic, 1:45](https://youtu.be/_CFu4mpSBlg)
- Limits and next steps: [docs/roadmap.md](docs/roadmap.md)
- Write-ups of the problems, as issues: [label `post-idea`](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues?q=label%3Apost-idea)

## What changes next

Update this file, then everything written from it, when these close:

| When | Change |
|---|---|
| OKE teardown done ([#13](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/13)) | "Status": replace the OKE sentence with the teardown date. "Facts", Cost: add the first Cost Analysis result after the teardown |
| Rebuild proof done ([#57](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/57)) | "Not done": remove the rebuild line. "Results": add the measured rebuild time. Portfolio card: `status: "done"` |
