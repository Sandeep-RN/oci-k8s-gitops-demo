# k3s bootstrap and DNS switch: the stack from Git, then the live site moved (2026-11-12)

Evidence for [#8](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/8),
with the live checks of
[#114](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/114),
[#115](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/115) and
[#116](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/116). This ran
on the **single-node k3s cluster** (ADR 0001, 0022). The steps are the runbook
[k3s-bootstrap](../runbooks/k3s-bootstrap.md), which was rewritten afterwards
to match what was run
([PR #131](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/pull/131)).

## Setup

- One Ampere A1 VM, 2 OCPU / 12 GB, Ubuntu 24.04 aarch64, k3s v1.36.5+k3s1,
  created on 2026-11-11. Nothing was deployed on it before this run.
- The OKE target kept serving `https://demo.sandeeprn.in` until step 7.
- Steps 1 to 6 ran on the afternoon of 2026-11-12 (IST). The DNS switch and the
  public check ran at about 22:10 UTC the same day (03:40 IST on 2026-11-13).

Addresses and the names of secrets are left out.

## 1. The cluster from Git

The Sealed Secrets key was restored from the offline backup first. Then two
manual applies: the ArgoCD install, and the cluster root
(`argocd/clusters/k3s/root.yaml`). Everything else came from the gitops repo.

| Measure | Value |
|---|---|
| Manual `kubectl apply` commands after the key restore | 2 |
| ArgoCD Applications Synced and Healthy | 10 of 10 (the root and 9 children), 3.5 minutes after the root was applied |
| SealedSecrets decrypted with the restored key | 8 of 8 |
| Keys made by the new controller itself | 0 (its public certificate equals the one committed in the gitops repo) |
| Production certificate | Issued on the first order, within 3 minutes of the app sync |
| Steps 1 to 6 in total | About 35 minutes, most of it the key restore |

The `link-shortener` Application needs CRDs that the monitoring app installs.
It can sync before those CRDs exist (a sync wave would not make ArgoCD wait for
them; see step 4 of the bootstrap runbook), so it retries; one retry was enough.

## 2. The edge before DNS moved

Tested under the real hostname with `curl --resolve`, while public DNS still
pointed at OKE:

| Check | Result |
|---|---|
| `externalTrafficPolicy` of Traefik's Service | `Local` (ADR 0022) |
| Address in the Ingress status | The node's public IP (compared without printing either) |
| `GET /healthz` over HTTPS | 200, certificate chain trusted, issuer Let's Encrypt |
| `GET` on port 80 | 301 to HTTPS |
| k3s's external-dns while OKE owned the record | No create, update or delete |

## 3. The data

A fresh backup was taken on OKE, downloaded, and restored into the new, empty
PostgreSQL on k3s.

| Measure | Value |
|---|---|
| Rows in the dump | 34 |
| Rows in the table after the restore | 34, owned by the app's own role (ADR 0018) |
| The landing page's example short link on k3s | 302 |
| First backup written from k3s | `link-shortener/k3s/<timestamp>.pgc`, listed in the bucket |

The k3s backup also proved that the node's write-only identity may write to
the bucket (ADR 0017). OKE's next nightly backup ran on schedule under its own
name, `link-shortener/oke/<timestamp>.pgc`.

## 4. The DNS switch

The switch was one pull request in the gitops repo
([PR #59](https://github.com/Sandeep-RN/oci-k8s-gitops-demo-gitops/pull/59)).
It removed the Ingress from the OKE overlay. Each cluster's external-dns owns
its record by a TXT owner id, so OKE had to let go before k3s could take over.

| Time (UTC, 2026-11-12) | Event |
|---|---|
| 22:10:14 | Pull request merged |
| 22:13:00 | OKE's external-dns deleted its A and TXT records |
| 22:13:25 | k3s's external-dns created its own |

The record was absent for **25 seconds**. Its TTL is 300 seconds, so a resolver
could keep the old address for up to 5 minutes. A request sent there would no
longer reach the app, because OKE's Ingress was gone (expected, not measured).

## 5. The public check afterwards

| Check | Result |
|---|---|
| `scripts/verify-public-url.sh --production --hsts`, no token | 10 passed, 1 skipped, 1 failed (the one check that needs a link token) |
| The same script with the owner's link token, without the burst | 9 passed, 0 failed, 2 skipped |
| Link created with the owner's token | Stored in the k3s database with `created_by = owner` |
| Burst of 600 requests from one client | 282 answers of 429 |
| Alerts firing on k3s | Only `Watchdog` (the always-on test alert) |
| In-cluster redirect probe | Succeeding |
| External probe (GitHub Actions) | The 3 scheduled runs after the switch (2026-11-12 22:40 UTC to 2026-11-13 10:50 UTC) all succeeded |

The token check also proved that the `link-tokens` SealedSecret decrypted with
the reused key, and that the app may write to the restored table.

## What had to change against the draft runbook

The draft was written before the cluster existed. The run found these:

- The sealing-key backup taken with `-o yaml` held the private key twice (once
  in a `last-applied-configuration` annotation) and was too long for the
  password manager. The backup is now a minimal export.
- The gitops CI required an Ingress in every overlay, so it blocked the pull
  request that had to delete one. The same pull request changed the rule: the
  OKE overlay must now have no Ingress.
- k3s's Traefik answers a GET on port 80 with 301. OKE's older Traefik answered
  308 with the same setting. The verify script accepts both.
- The certificate is ordered as soon as the app syncs, so it is checked one
  step earlier than planned.
- The OCI session expires after about an hour, between steps.

## What this shows, and what it doesn't

- Shows: a new cluster reaches the full stack from the Git repo with two
  manual applies and one key restore; sealed files written for one cluster
  decrypt on another once the key is restored; a live hostname can move between
  clusters through a reviewed pull request with a gap of seconds; the backup
  restores into a different cluster with every row.
- Doesn't show: a **rebuild** of this cluster. The runbook's rebuild section is
  written but not run
  ([#57](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/57)). Three
  commands in the runbook were rewritten after the run and are marked there as
  not run in their final form.
- Doesn't show: that a second client still gets 200 while another client is
  rate limited. Only the one-client burst was run.
- Not checked in this run: the nightly backup schedule on k3s (only a manual
  backup), Prometheus memory use against the estimate for the 12 GB node, and a
  disk-full alert for the `local-path` volumes.
- One node cannot show what the OKE tests showed: a drain or a node failure
  here is an outage (ADR 0001). See
  [oke-final-2026-11-10.md](oke-final-2026-11-10.md).
