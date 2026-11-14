# Runbook: Postgres backups and restore

ADR 0007 (nightly `pg_dump`), ADR 0017 (write-only instance-principal access).

Applies to the k3s cluster, which serves the site since 2026-11-12. The
commands were first run on the OKE target on 2026-10-25: manual backup,
permission checks, and a restore drill whose result matched the live data row
for row. On 2026-11-12 OKE's backup was restored into k3s Postgres (34 rows,
equal to the dump; step 6 of [k3s-bootstrap](k3s-bootstrap.md)), and a backup
written from k3s proved that the node may write to the bucket. The nightly
CronJob then ran on schedule on k3s: the Jobs of 2026-11-13 and 2026-11-14
completed (the bucket objects themselves were not listed).

## Not yet run on k3s in this form

Only the kubeconfig changed for these. Run each once on k3s and remove it from
this list:

- the four `$K` commands in "The alert fired" step 1 (CronJob, Jobs by label, `dump` and `upload` logs)
- the restore drill into the scratch database `restore_drill` (steps 2 to 4)

Every command names the k3s kubeconfig, because kubectl's default context on
the laptop may be another cluster:

```bash
K="kubectl --kubeconfig $HOME/.kube/k3s.kubeconfig"     # k3s, NOT the OKE kubeconfig
```

## How backups work

| | |
|---|---|
| Schedule | CronJob `link-shortener/postgres-backup`, 03:00 Asia/Kolkata nightly (21:30 UTC) |
| Format | `pg_dump --format=custom` (checked with `pg_restore --list` before upload) |
| Destination | Bucket `oci-k8s-gitops-demo-pg-backups`, objects `link-shortener/<cluster>/<UTC timestamp>.pgc`, where the cluster (`oke` or `k3s`) is set by each overlay. The change merged on 2026-11-12. The first OKE object with the new name was a manual backup at 2026-11-12 07:48 UTC; the first nightly one ran at 2026-11-12 21:30 UTC (03:00 IST on 2026-11-13). Older OKE objects have no cluster segment: `link-shortener/<UTC timestamp>.pgc` |
| Retention | 14 days, deleted by a bucket lifecycle rule (`terraform/shared`) |
| Cluster's access | **Write-only**: create and list objects in that bucket; read, overwrite and delete are refused (verified on OKE, see below; on k3s only the write was checked) |
| Restore access | Your own OCI login, from the laptop |
| Alert | `PostgresBackupMissing` (warning): no success in 26 h, or none on record |

The Object Storage namespace identifies the tenancy, so it is never committed.
Every command looks it up:

```bash
OCI="oci --auth security_token --profile oke-demo"
NS=$($OCI os ns get --query data --raw-output | tr -d '\r')
B=oci-k8s-gitops-demo-pg-backups
```

Access to the cluster: [access runbook](access.md).

## The alert fired: PostgresBackupMissing

1. Look at the last runs:

   ```bash
   $K -n link-shortener get cronjob postgres-backup
   $K -n link-shortener get jobs -l app.kubernetes.io/name=postgres-backup --sort-by=.metadata.creationTimestamp
   $K -n link-shortener logs job/<job-name> -c dump
   $K -n link-shortener logs job/<job-name> -c upload
   ```

2. Match the failure:

   | Symptom | Likely cause |
   |---|---|
   | `dump` fails to connect | Postgres down or credentials changed (`postgres-credentials` SealedSecret) |
   | `upload`: `BucketNotFound` / `NotAuthorizedOrNotFound` on **put** | The write-only policy or dynamic group is missing or changed: `terraform plan` in `terraform/shared` |
   | `upload`: `ObjectAlreadyExists` | Two runs in the same second (should not happen with `concurrencyPolicy: Forbid`) |
   | No Job at all | CronJob suspended or deleted; check that ArgoCD is Synced |
   | Alert right after the CronJob was created | Expected until the first success; run one manually (below) |

3. Run a backup now, outside the schedule. This creates a one-off Job from the
   CronJob's own template; nothing in Git changes:

   ```bash
   J=postgres-backup-manual-$(date -u +%H%M)
   $K -n link-shortener create job --from=cronjob/postgres-backup "$J"
   $K -n link-shortener wait job/"$J" --for=condition=complete --timeout=400s
   $K -n link-shortener logs job/"$J" -c upload | tail -1      # uploaded link-shortener/k3s/<timestamp>.pgc
   ```

   The upload log ends with `uploaded link-shortener/k3s/<timestamp>.pgc` (the
   job refuses to run if the overlay sets no cluster). The alert clears within
   about 15 minutes.

## Restore drill (do this after any change to the backup path)

Restores a dump into a scratch database next to the live one and compares
them. The live database is only read.

```bash
# 1. Pick and download a dump with your own login (the cluster cannot read it).
$OCI os object list -ns "$NS" -bn "$B" --query 'data[].{name:name,size:size}' --output table
O=link-shortener/<cluster>/<timestamp>.pgc     # older OKE objects: link-shortener/<timestamp>.pgc
$OCI os object get -ns "$NS" -bn "$B" --name "$O" --file restore.pgc    # Git Bash on Windows: give --file a Windows path (cygpath -w)

# 2. Restore into a scratch database.
psql_() { $K -n link-shortener exec -i postgres-0 -- sh -c "psql -X -At -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -d $1 -c \"$2\""; }
psql_ postgres "CREATE DATABASE restore_drill"
$K -n link-shortener exec -i postgres-0 -- sh -c 'pg_restore --no-owner --exit-on-error -U "$POSTGRES_USER" -d restore_drill' < restore.pgc

# 3. Compare: rows in the dump vs live rows created before the dump time.
psql_ restore_drill "SELECT count(*) FROM links"
psql_ linkshortener "SELECT count(*) FROM links WHERE created_at <= '<dump time, UTC>+00'"

# 4. Clean up.
psql_ postgres "DROP DATABASE restore_drill"
rm restore.pgc   # it holds real data
```

Result on 2026-10-25 (OKE): 9 rows restored, identical (code and URL) to the 9
live rows created before the dump.

## Real restore

Decide first which case you are in. A dump only holds data up to its time;
links created after it are lost (ADR 0007 accepts up to a day).

**A. Bad data, database still running** (for example, rows deleted by
mistake). Restore into a scratch database first (drill steps 1-3), check it,
then replace the live table:

```bash
$K -n link-shortener exec -i postgres-0 -- sh -c 'pg_restore --no-owner --role=linkshortener_app --clean --if-exists --exit-on-error -U "$POSTGRES_USER" -d linkshortener' < restore.pgc
```

`--clean --if-exists` drops and recreates the `links` table from the dump.
`--role=linkshortener_app` makes the restored table belong to the app's role
(ADR 0018). Without it the table belongs to the admin and the app gets
"permission denied" until the next ArgoCD sync hands it back.
Requests during those seconds may get 503; the app recovers on its own.

**B. Volume lost.** On k3s the volume is a `local-path` directory on the
node's boot disk (5Gi requested, `overlays/k3s` in the gitops repo), tied to
the one node. If only the PVC is gone, the StatefulSet starts Postgres on a
new, empty volume, the app creates an empty table on its first request
(ADR 0016), and the same `pg_restore --clean --if-exists` command as in A
restores the data. Losing the node or its disk loses the volume too; then the
path is the rebuild section of [k3s-bootstrap](k3s-bootstrap.md) (#57,
written but not run yet), whose step 6 restores the newest backup this way.

After either case: check with `curl` (access runbook) that an old short link
still redirects.

## What was verified on OKE (2026-10-25)

- Manual Job: dump 2,140 bytes, upload in 43 s, namespace looked up at run time.
- From a pod with the node's credentials: **list allowed; read, overwrite,
  delete and listing other buckets all denied.** OCI answers "not found"
  rather than "forbidden", so it does not reveal what exists.
- The downloaded dump was unchanged after the overwrite attempt.
- Restore drill: identical data (above).

## Notes

- Backups are logical (`pg_dump`). There is no point-in-time recovery; see
  ADR 0007 "At scale".
- The bucket has `prevent_destroy`, and `terraform/shared` is separate from
  the cluster roots: tearing down OKE (#13) leaves the backups in place.
- The app connects as its own non-superuser role, `linkshortener_app` (ADR 0018).
  Backups and restores use the admin role (`POSTGRES_USER`); the restore
  switches to the app role for the objects it creates.
