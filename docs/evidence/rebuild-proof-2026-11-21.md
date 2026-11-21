# Rebuild proof: the cluster deleted and rebuilt on the same VM (2026-11-20 and 21)

Evidence for [#57](https://github.com/Sandeep-RN/oci-k8s-gitops-demo/issues/57).
This ran on the **single-node k3s cluster** (ADR 0001, 0022). The steps are the
"Rebuild proof" section of the runbook
[k3s-bootstrap](../runbooks/k3s-bootstrap.md), which was corrected afterwards to
match what was run. Times are UTC on 2026-11-20 (the evening; it was after 02:00
IST on 2026-11-21). Addresses and the names of secrets are left out.

## What was deleted, and what was not

| Deleted (by `k3s-uninstall.sh`) | Kept |
|---|---|
| The cluster state, ArgoCD, every workload, the PostgreSQL volume | The VM, its boot volume and its public address (`prevent_destroy`) |
| The sealing key inside the cluster | The DNS record (never touched; external-dns keeps it), the backup bucket, the Terraform state |

The VM was not replaced on purpose: A1 capacity is scarce (ADR 0001, 0022). So
this proves the rebuild of the cluster, not of the machine.

## Before the uninstall

| Check | Result |
|---|---|
| `scripts/k3s-verify.sh` | 9 of 9 passed |
| `terraform plan` in `terraform/k3s` | No changes (the baseline for the check afterwards) |
| ArgoCD Applications | 10 of 10 Synced and Healthy |
| SealedSecrets | 8 of 8 `Synced=True`, 1 sealing key |
| Fresh sealing-key backup from k3s (minimal export) | 6844 bytes, 1 key, no `last-applied` annotation; accepted by a server-side dry run against the live cluster |
| Where the key backup was kept | The password manager. Its text was read back out of the manager before the uninstall |
| Fresh database backup | A manual Job, `link-shortener/k3s/<timestamp>.pgc`, 3236 bytes, listed in the bucket |
| Rows in that dump, counted by `pg_restore` without restoring | 38; the live table also had 38 |

## The rebuild

| Time | Event | Since the uninstall finished |
|---|---|---|
| 20:39:54 | `k3s-uninstall.sh` finished | 0 |
| 20:45:47 | `bootstrap-node.sh` finished, node Ready (k3s v1.36.5+k3s1, pinned) | 5 min 53 s |
| 20:46:46 | First `k3s-verify.sh`: 8 of 9. `pod-dns-internet` failed because the run came about a minute after k3s started | |
| 20:47:47 | `pod-dns-internet` passed on the re-run | |
| 20:54:55 | Key restored, ArgoCD installed, cluster root applied | 14 min 1 s |
| 20:57:51 | All 10 Applications Synced and Healthy, 8 of 8 SealedSecrets `Synced=True`, certificate READY | 17 min 57 s |
| 21:00:30 | Data restored (the restore itself took 1 min 40 s) | **20 min 36 s** |

- **Two manual applies after the key restore**, as on the first bootstrap: the
  ArgoCD install and the cluster root. Everything else came from the gitops repo.
- **The key was restored from the password manager's copy**, not from a file on
  disk. The copy came back one byte longer (a trailing newline), which YAML
  ignores. The proof that it was the right key: the new controller decrypted all
  8 SealedSecrets, and it made no key of its own (1 key on the cluster).
- **The time between 20:46:46 and 20:54:55** is mostly a person: copying the key
  out of the password manager, then the ArgoCD install and its rollout.
- **Applications to healthy took under 3 minutes** after the root was applied
  (20:54:55 to a check at 20:57:51; an earlier check at 20:55:40 still showed
  some Progressing or Missing). The first bootstrap took 3.5 minutes.
- **One production certificate** was ordered (Let's Encrypt allows about 5 per
  week per name) and was READY at the first check.

## After the rebuild

| Check | Result |
|---|---|
| Edge, tested with `curl --resolve` | `/healthz` 200 with a trusted chain; issuer Let's Encrypt production; port 80 answers 301 to HTTPS |
| Ingress address equals the node's address | Yes (compared without printing either); Traefik `externalTrafficPolicy` is `Local` |
| Table before the restore | Empty: the landing page's example link returned 404 |
| Database restore | `pg_restore` finished; 38 rows in the dump and 38 in the table, owned by the app's own role (ADR 0018) |
| Example link after the restore | 302 |
| `scripts/verify-public-url.sh --production`, no token | 10 passed, 1 failed (the one check that needs a link token), including the 600-request burst and the recovery |
| The same script with the owner's token, without the burst | 9 passed, 0 failed, 1 skipped |
| First backup from the rebuilt node | `link-shortener/k3s/<timestamp>.pgc`, 3236 bytes, listed. The node's write-only identity may still write to the bucket (ADR 0017) |
| Alerts firing | Only `Watchdog`. Before that first backup `PostgresBackupMissing` also fired, as it does on any new CronJob with no successful run |
| In-cluster redirect probe | Succeeding |
| `terraform plan` afterwards | No changes |
| DNS | One public A record, not proxied, present before and after (nothing in the runbook touches it) |

**Recovery time:** about **21 minutes** from the end of the uninstall to a site
with its data back. The site was fully down for about the first 18 of them, then
answered with an empty table until the restore. This includes the time a person
needed for the key and for pasting commands. **Recovery point:** the backup
taken just before, so nothing was lost here; in an unplanned loss it would be
the last nightly dump, up to 24 hours (ADR 0007).

## What the run found

The runbook was changed for each of these:

- After the reinstall the cluster has a new certificate authority and client
  certificate, so the old kubeconfig stops working. Fetch it again with
  `scripts/k3s-tunnel.sh --no-tunnel`; a tunnel that is already open keeps working.
- `scripts/k3s-verify.sh` fails its DNS and internet check if it runs less than
  about two minutes after k3s starts. It passes when run again.
- Restore the backup **by name**. The nightly job runs at 03:00 IST and can write
  a newer, almost empty object while the cluster is being rebuilt.
- `PostgresBackupMissing` fires until one manual backup has run on the rebuilt
  cluster. Take it at the end of step 6.
- The pasted-block habit needs a stop: copying the key out of the password
  manager and then copying a command from another window overwrites the
  clipboard. The first read-back of the key note was a copy of a command, not of
  the key; the server-side dry run rejected it (523 bytes, no Secret), and the
  check was repeated with the key in the clipboard.

## What this shows, and what it doesn't

- Shows: the cluster can be deleted and rebuilt from the Git repo, the key
  backup and the database backup, on the same VM, with the DNS record untouched.
  A key stored only in a password manager is enough to decrypt every sealed
  file. The data came back with every row. `terraform plan` was empty before and
  after.
- Doesn't show: a rebuild of the **VM**. The reinstall used the bootstrap script
  already on the node. A replaced VM would take the Terraform and cloud-init
  path, which stays untested (`prevent_destroy`; ADR 0001, 0022).
- Doesn't show: a restore from a *nightly* backup after a real failure. The
  backup used was a manual one taken minutes earlier.
- Doesn't show: a clean-clone `terraform plan`. The plan ran in the working
  checkout, which was initialised before.
- The start of the uninstall was not timestamped, so the times above count from
  its end. The real total is a few seconds longer.
- Not checked: that a second client still gets 200 during another client's
  burst (see [k3s-bootstrap-2026-11-12.md](k3s-bootstrap-2026-11-12.md)).
  Checked later the same day: [k3s-live-checks-2026-11-21.md](k3s-live-checks-2026-11-21.md).
