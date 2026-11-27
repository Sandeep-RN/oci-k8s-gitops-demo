# Project brief: oci-k8s-gitops-demo

The single source of facts about this project for anything written about it
somewhere else: a resume, a portfolio page, a profile, a post, an interview
answer. **Last full verification: 2026-11-23**
([#225](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/225)).
**Partly re-verified: 2026-11-26**
([#263](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/263)).

- **Checked again on 2026-11-26:** the counts of pull requests, ADRs, runbooks
  and evidence write-ups; the state of the open items; the "Results" numbers
  against their evidence files and issue comments (for the spend cap, the #113
  comment); the new sections on the public pages and the AI reviews, against the
  ADRs, pull requests, issues, the application code and read-only requests to
  the public sites (no browser rendering); that the three video links answer.
- **Not checked again, each keeps its earlier date:** the cost (2026-11-23),
  Oracle's Always Free page (2026-11-13), anything that needs access to the
  cluster or the cloud account (alerts loaded and inactive, the VM, the running
  k3s version, pod memory and restarts), "Problems found and fixed" and "The
  story".

## How to use this file

For a person, or for an AI assistant working in another project:

1. **Use only the facts and numbers in this file.** Each number has a source.
   Do not round up, combine numbers, or add a number that is not here.
2. **This is a personal project.** It is not work done for an employer, and it
   must never be described as production experience.
3. **Do not claim what the "Not done" section lists.** Saying the limits out
   loud is part of how this project is presented.
4. **Prefer the ready-made text** in "Ready to use" to writing new claims.
5. **Check the dates above.** Two items are still open on 2026-11-26: the
   3-minute video (#58) and the live check of ADR 0025 (#196). "What changes
   next" at the end says which lines to update when they close. If this file
   is more than a month old, read the [README](README.md) first.
6. **Ask the owner** for anything that is missing. Do not fill a gap by guessing.

## Summary

**One line.** A production-shaped Kubernetes platform on one free Oracle Cloud
VM: GitOps delivery, an SLO with burn-rate alerts, tested backups, and every
decision written down.

**50 words.** A small link-shortener service on Kubernetes (k3s) on Oracle
Cloud's free tier. Every change is delivered through Git: CI builds the image
behind a scan gate, a pull request changes the tag, ArgoCD deploys it. It has
HTTPS, an availability SLO with burn-rate alerts, nightly backups with tested restores,
and 27 recorded decisions.

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
2026-11-12. The OKE target served the site until 2026-11-12 and was destroyed
on 2026-11-15 (issue [#13](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/13)).
A second application, an on-call assistant, runs on the same node at
<https://ask.sandeeprn.in> (its numbers: "Second application" below). The two
sites link to each other. Since 2026-11-23 the landing page shows live platform
data, and since 2026-11-24 a "Platform metrics" page charts it (see "Public
pages and live data").

## Facts

| | |
|---|---|
| Name | oci-k8s-gitops-demo |
| Kind | Personal project. One person: design, decisions, build, operation |
| Period | 2026-10-20 to 2026-11-14 for the build; tests and the second application to 2026-11-23; the public status pages and dashboard screenshots 2026-11-23 and 24; two open items below |
| Repos (public) | [infrastructure and docs](https://github.com/Sandeep-RN/oci-k8s-gitops-demo), [application and CI](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app), [Kubernetes manifests](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-gitops) |
| Live URL | <https://demo.sandeeprn.in> (landing page with a working short link and a live data strip; "Platform metrics" at [`/status`](https://demo.sandeeprn.in/status); API page at `/api/docs`) |
| Cloud | Oracle Cloud Infrastructure. One Always Free Ampere A1 VM: 2 OCPU, 12 GB, arm64, Ubuntu 24.04. (Oracle's [Always Free page](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) gives 1,500 OCPU hours and 9,000 GB hours a month, "equivalent to 2 OCPUs and 12 GB of memory"; checked 2026-11-13) |
| Kubernetes | k3s v1.36 on one node (today). OKE, two nodes, for the multi-node tests (2026-10-22 to 2026-11-12) |
| Size of the work | On 2026-11-26 (18:00 UTC): 244 merged pull requests across the three platform repos (83 infrastructure and docs, 44 application, 117 manifests; 46 of them automated image-tag bumps, 17 of those for the assistant's image; 10 from Dependabot; counted with `gh pr list --state merged`), plus 28 in the assistant's repo. 27 ADRs, 9 runbooks, 6 evidence write-ups (the Markdown files in `docs/adr/` without the index, in `docs/runbooks/` and in `docs/evidence/`). The landing page shows no counts since [#264](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/264): take them from here, with their date |
| Cost | Target $0 a month. The OKE target cost about SGD 3.05 a day, paid from trial credit: SGD 44.96 in total for 2026-11-01 to 2026-11-15 (SGD 45.69 for 2026-10-22 to 2026-11-06, [evidence](docs/evidence/oke-final-2026-11-10.md)). Cost Analysis confirmed $0 for OKE from 2026-11-16: SGD 0.00 for every service on each day from 2026-11-16 to 2026-11-22, and 0.00 so far on 2026-11-23 (last charges 2026-11-15, the teardown day, [#13](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/13)). The remaining credit balance cannot be shown (the Console's subscription panel returns an error): do not claim it. The monthly budget is SGD 7, so November's SGD 44.96 (all before 2026-11-16) makes it read over budget until it resets on 2026-12-01 |
| Second application | An on-call assistant that answers from the project's documents, live at <https://ask.sandeeprn.in>, in [its own repo](https://github.com/Sandeep-RN/oncall-assistant). Its page links to the platform site and has a "Built with" badge row ([oncall-assistant#67](https://github.com/Sandeep-RN/oncall-assistant/pull/67), seen live 2026-11-26). Use only the numbers in the README section "A second app"; its answer quality and SLO are not measured yet |
| Alerts on k3s | Besides the SLO burn-rate and probe alerts: six platform alerts added on 2026-11-23, each with a runbook section. Certificate expiry (`CertificateExpiringSoon`, `CertificateNotReady`, `CertManagerMetricsMissing`) and Traefik 5xx (`TraefikServerErrorsHigh`, `TraefikMetricsMissing`) in the [edge runbook](docs/runbooks/edge.md); node disk (`NodeRootDiskLow`) in the [k3s node runbook](docs/runbooks/k3s-node.md). Tested with `promtool` unit tests and checked live as loaded and inactive; none has fired on the real cluster ([#140](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/140)) |
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
| Deleting the cluster and rebuilding it on the same VM | 20 min 36 s from the end of the uninstall to the data restored: 10 Applications healthy after 17 min 57 s, all 38 rows back, `terraform plan` empty before and after. Includes the time a person needed; the VM itself was not rebuilt | [evidence 2026-11-21](docs/evidence/rebuild-proof-2026-11-21.md) |
| Backup and restore | Nightly dumps. Restored three times: a drill on 2026-10-25, for real in the move on 2026-11-12, and in the rebuild on 2026-11-21 ([evidence](docs/evidence/rebuild-proof-2026-11-21.md)) | [runbook](docs/runbooks/postgres-backup-restore.md) |
| Image scan gate | Blocked a real HIGH CVE before the image was pushed | [evidence 2026-11-08](docs/evidence/oke-final-2026-11-10.md) |
| Rate limit per client | One client's burst of 600 requests got 282 answers of 429. That Traefik sees each client's own address was measured with a packet capture. On 2026-11-21 a laptop got 1410 x 429 over a 60 second flood while a phone on mobile data was served normally on every reload (an observation: Traefik's counters cannot be split by client) | [#115](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/115), [ADR 0022](docs/adr/0022-moving-the-demo-from-oke-to-k3s.md), [evidence](docs/evidence/k3s-live-checks-2026-11-21.md) |
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
- **20 min 36 s** is one measured rebuild of the cluster, counted from the end
  of the uninstall, with a person pasting commands and a backup taken minutes
  before. Say "rebuilt in about 21 minutes in one run", not "an RTO of 21
  minutes". The site was fully down for about the first 18 of them.
- In the alert test the page arrived **after** the 5-minute outage had ended
  (outage 13:07:11 to 13:12:49, page 13:14:39). Say "paged 7.5 minutes after
  the outage began", never "detected the outage in real time".
- "Paged" means a message in a Discord channel. There is no pager and no
  on-call rota.
- **The image scan gate** (Trivy) scans an **amd64** build before anything is
  pushed; CI then builds and pushes amd64 and arm64 (the app repo's
  `.github/workflows/ci.yml`, read 2026-11-26). The arm64 image the node runs
  is not scanned itself. Say "a scan gate before the push", never "the arm64
  image is scanned" or "the multi-arch image is scanned".
- **ADR 0025** (a second application inside a hard cap) is **designed, not
  verified**, until [#196](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/196)
  closes. Say "designed a hard cap for a second application", never "proved
  the cap protects the first". The four single checks posted in #196 on
  2026-11-22 may be quoted one at a time, as they are written there: the
  negative priority was accepted; every pod is QoS `Burstable`; the quota
  refused an over-cap pod on a server-side dry run; each pod's peak memory
  stayed within its budget line. Never combine them into "ADR 0025 verified".
- The **six k3s platform alerts** (certificate, Traefik 5xx, node disk) have
  **not fired** on the real cluster; they are tested with `promtool` only.
  Say "alerts with runbooks", never that they caught a problem.
- **Restored three times**: each restore used a backup taken for it (a manual
  run of the backup job or a fresh dump), not a scheduled nightly file. The
  restore path is tested; a restore of a nightly file was not run separately.

## Public pages and live data

Shipped on 2026-11-23 and 24. These are not rows of "Results".

| What | Facts | Source |
|---|---|---|
| Landing page | Rebuilt: navigation, stack badges, a diagram drawn in SVG, link cards to the sources (typed counts removed on 2026-11-27, #264), cards, a link to the assistant | [#229](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/229), [app#40](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app/pull/40) |
| API page | Swagger UI moved to `/api/docs` (the old `/docs` answers 404) with a dark theme that follows the visitor's system setting. It still loads Swagger UI from a third-party CDN | [app#41](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app/pull/41); read-only requests 2026-11-26 |
| Live status strip | `/api/status` returns rounded aggregates (SLO, request rate, node CPU, memory and network transmit, running pods, running commit, ArgoCD sync and health). 11 fixed PromQL queries in code; a background refresh every 30 seconds into a cached snapshot; a visitor's request never calls Prometheus | [ADR 0026](docs/adr/0026-live-status-endpoint-allowlisted-queries-cached-snapshot.md), [live check in #230](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/230) (2026-11-23) |
| "Platform metrics" page | `/status`: 8 charts as SVG drawn on the server, no JavaScript on the page, 9 fixed range queries refreshed every 5 minutes; windows of 24 hours and 7 days, with deploy markers | [ADR 0027](docs/adr/0027-history-charts-server-rendered-svg-from-a-cached-range-snapshot.md), [live check in #235](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/235) (2026-11-24) |
| No admin UI made public | Grafana, Prometheus and ArgoCD get no public Ingress; both pages show only chosen numbers | [ADR 0014](docs/adr/0014-admin-ui-access.md), ADR 0026 |
| Dashboard screenshots | Three Grafana dashboards on the live k3s node, captured 2026-11-24 at about 20:00 UTC: the project's own redirect SLO dashboard, a node dashboard and a per-pod dashboard | [evidence 2026-11-24](docs/evidence/grafana-dashboards-2026-11-24.md) |

How to quote these honestly:

- The percentages on the live pages (100% when read on 2026-11-26) are **not**
  a measured uptime figure and **not** evidence of user traffic: the traffic is
  about 0.03 requests a second, mostly the in-cluster probe (ADR 0027).
- Prometheus keeps 8 days. On 2026-11-26 the 7-day charts still said they had
  5.9 of 7 days of data. The screenshots show the last 24 hours, taken when
  Prometheus held about 4 days, so their "7 days" SLO panels had less than 7.
- "Live" means a cached snapshot: about 30 seconds old for the strip and about
  5 minutes for the charts.
- The live checks did not cover the strip's polling and hidden-tab pause or the
  chart hover text in a real browser, nor stale or degraded-Prometheus
  behaviour in production (#230, #235).

## Independent AI security reviews

Two features, and only these two among those above, had a separate security
review: the status strip's backend and the history charts. The reviewer was an
**AI model** in a fresh, read-only session that had not written the code. It was
not a human reviewer, an audit or a penetration test. Each time the feature was
merged switched off, reviewed, fixed, and only then switched on. The pull
requests call it an "independent security review".

| Feature | What the review found | What was done |
|---|---|---|
| Status strip ([app#42](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app/pull/42)) | A Prometheus that dribbled its answer slowly left query threads stuck (6 per refresh, never ending); a 1 MiB answer cap let one refresh peak at 125.8 MiB in a pod limited to 128 Mi; weak tests; smaller points, such as a 503 before the first refresh that would count toward the server-error alert | Fixed in [app#43](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app/pull/43): at most 3 stuck threads, which end by themselves; a 64 KiB cap, 4.8 MiB peak; real-socket tests; 200 with `available: false` ([ADR 0026](docs/adr/0026-live-status-endpoint-allowlisted-queries-cached-snapshot.md), amended). One low finding was left on purpose. Then switched on ([gitops#111](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-gitops/pull/111)) |
| History charts ([app#45](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app/pull/45)) | No high finding. Two medium: one tiny number from Prometheus blanked every chart, and the memory chart showed no data if there were two series. Also weak tests and smaller faults, such as a missing deploy marker after a rollback | Fixed in [app#46](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app/pull/46), then switched on ([gitops#115](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-gitops/pull/115)). A follow-up hygiene change for the status strip ([#244](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/244), [app#48](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app/pull/48)) was merged on 2026-11-26. The build after the merge failed the image scan on a new finding in the base image, so the change reached the site only with that fix ([#266](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/266), [app#49](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-app/pull/49)), at about 19:10 UTC that day, and was then [checked live](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/244#issuecomment-7201389048) |

The before and after numbers are from the reviewer's test scripts and the
branch's tests, not from production. The landing page rebuild, the API page and
the screenshots had no such review: do not extend the claim to them or to the
platform as a whole.

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
| A second application on the same node, inside a hard cap: its own namespace, a quota of 1 GiB of memory and 1 CPU for everything in it, and a lower priority than the link shortener | The free tier gives one node, so the second app must not be able to starve the first. **Designed, not yet verified:** the live check is [#196](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/196), still open | [0025](docs/adr/0025-second-application-on-the-node-inside-a-hard-cap.md) |
| Live data on the public site comes from fixed queries and a cached snapshot, not from public admin tools | Visitors see how the platform behaves; Prometheus has no authentication, and a public Grafana or ArgoCD is a large attack surface | [0026](docs/adr/0026-live-status-endpoint-allowlisted-queries-cached-snapshot.md) |
| History charts drawn on the server as SVG, with no client JavaScript | No script to allow or review in the browser and no charting library | [0027](docs/adr/0027-history-charts-server-rendered-svg-from-a-cached-range-snapshot.md) |

All 27: [docs/adr/README.md](docs/adr/README.md).

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
- **A rebuild of the VM itself.** The cluster was rebuilt on the same VM
  ([#57](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/57)); a
  replaced VM would take the Terraform and cloud-init path, which is untested.
- **Load or performance testing.** None. The tests ran at under one request a
  second.
- **Autoscaling, NetworkPolicies, a log stack, a dead man's switch** for the
  monitoring stack.
- **Terraform plan or apply in CI.** CI runs only offline checks (`fmt`,
  `validate`, `test`, no cloud credentials). `plan` and `apply` are run by
  hand from a laptop.
- **A measured uptime figure.** The recovery time was measured once (20 min
  36 s, from a backup taken minutes earlier); it is not a guarantee.
- **Database replication.** One replica; up to 24 hours of data can be lost.
- **A verified cap for the second application.** ADR 0025 is designed and
  deployed; its live check
  ([#196](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/196)) is
  still open.
- **A real firing of the k3s platform alerts.** Unit-tested only
  ([#140](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/140)).
- **A human security review, an audit or a penetration test.** The only
  reviews of the public status features were by an AI model (see "Independent AI
  security reviews").
- **Public dashboards.** Grafana is private; the public has two pages of chosen
  numbers and three screenshots.
- **Real user traffic.** The live pages show mostly the platform's own probe.

The full list, with what would come next: [docs/roadmap.md](docs/roadmap.md).

## How it was built

Built between 2026-10-20 and 2026-11-14 with an AI coding assistant (Claude
Code). The assistant wrote much of the YAML, Terraform and scripts, and first
drafts of the docs. The owner made the decisions, applied the infrastructure,
ran or supervised every live test, and reviewed and merged the pull requests.
A second model reviewed the first ADRs and found real errors. On 2026-11-23 and
24 a separate AI session also security-reviewed the status strip and the history
charts before they were switched on. The `CLAUDE.md` files in the three repos
are the instructions given to the assistant.

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
- Recorded 27 architecture decisions and wrote 9 runbooks; nightly PostgreSQL
  backups with a write-only identity, restored three times.
- Deleted the Kubernetes cluster and rebuilt it on the same VM from Git, an
  offline key backup and a data backup: rebuilt in about 21 minutes in one
  run, every database row back, `terraform plan` empty before and after.
- Published live platform metrics without making Grafana or Prometheus public
  (fixed query allowlist, cached snapshot, server-drawn SVG charts), and
  switched each of the two features on only after a separate AI security review
  and fixes for its medium findings.

### Portfolio card

```yaml
title: "Kubernetes GitOps Platform on OCI Free Tier"
description: "A production-shaped service on one free VM: ArgoCD GitOps delivery in about 7 minutes from merge to live, a 7-day SLO with burn-rate alerts proven by a planned outage, tested backups, and a live move between clusters with 25 seconds without a DNS record."
tags: ["Kubernetes", "ArgoCD", "GitOps", "Terraform", "Prometheus", "SLI/SLO", "GitHub Actions", "OCI"]
status: "in progress"   # done except the 3-minute video (#58); set "done" when #58 closes (#196 belongs to the second app and does not block this card)
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
production one should be, on Oracle Cloud's free tier. GitHub Actions passes a
scan gate and pushes a multi-arch image, a pull request changes the tag, and
ArgoCD deploys it: about 7 minutes from merge to live. The service has HTTPS
with automatic certificates, a 7-day availability SLO with burn-rate alerts
that I proved with a planned outage, and nightly backups with a restore path I
have used three times. On a two-node cluster I drained a node under live
traffic with no failed request. I then moved the live site to a single free VM;
the cutover was one pull request. 27 decisions and 9 runbooks are in the repo.

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
- Platform metrics: <https://demo.sandeeprn.in/status>; API page: <https://demo.sandeeprn.in/api/docs>
- Second application: <https://ask.sandeeprn.in>
- Dashboard screenshots: [Grafana, 2026-11-24](docs/evidence/grafana-dashboards-2026-11-24.md)
- Start here: [README](README.md), then [docs/architecture.md](docs/architecture.md)
- Decisions: [docs/adr/README.md](docs/adr/README.md)
- Proof: [docs/evidence/](docs/evidence/)
- Videos: [node drain, 2:00](https://youtu.be/ypoLkJUmsCI), [rollout under traffic, 1:45](https://youtu.be/_CFu4mpSBlg), [OKE live tour: app, ArgoCD, Grafana SLO, alerts, 9:36](https://youtu.be/jkP26YOaopc)
- Limits and next steps: [docs/roadmap.md](docs/roadmap.md)
- Write-ups of the problems, as issues: [label `post-idea`](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues?q=label%3Apost-idea)

## What changes next

Update this file, then everything written from it, when these close.
#13 (Cost Analysis, closed 2026-11-16) and #57 (rebuild proof, closed
2026-11-20) are done and already reflected above. On 2026-11-26 neither #58 nor
#196 had closed.

| When | Change |
|---|---|
| The 3-minute video is recorded and [#58](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/58) closes | Add the video to "Links" and to the README's "Evidence"; set the portfolio card to `status: "done"` (#196 does not block the card: it is the second application's check) |
| [#196](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/196) closes (ADR 0025 on the live node, including 7 days of the link shortener's SLO unaffected) | "Decisions": change ADR 0025 from "designed, not yet verified" to what #196 measured; drop its quoting rule or replace it with the measured result |
| Optional: the final credit balance can be read in OCI Billing | "Facts", Cost: add it. Until then do not claim it |
| [#219](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/219) closes (November invoice and budget, dated 2026-12-02 to 12-05) | "Facts", Cost: add what it recorded. Until then claim nothing about cost after 2026-11-23 |
| The 7-day charts on `/status` hold a full 7 days (check the page) | "Public pages and live data": drop the "5.9 of 7 days" sentence |
