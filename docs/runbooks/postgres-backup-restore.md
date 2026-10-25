# Runbook: Postgres backups and restore

ADR 0007 (nightly `pg_dump`), ADR 0017 (write-only instance-principal access).
Tested end to end on the OKE target on 2026-10-25: manual backup, permission
checks, and a restore drill whose result matched the live data row for row.
Every command below was run as written.

## How backups work

| | |
|---|---|
| Schedule | CronJob `link-shortener/postgres-backup`, 03:00 Asia/Kolkata nightly |
| Format | `pg_dump --format=custom` (checked with `pg_restore --list` before upload) |
| Destination | Bucket `oci-k8s-gitops-demo-pg-backups`, objects `link-shortener/<UTC timestamp>.pgc` |
| Retention | 14 days, deleted by a bucket lifecycle rule (`terraform/shared`) |
| Cluster's access | **Write-only**: create and list objects in that bucket; read, overwrite and delete are refused (verified, see below) |
| Restore access | Your own OCI login, from the laptop |
| Alert | `PostgresBackupMissing` (warning): no success in 26 h, or none on record |

The Object Storage namespace identifies the tenancy, so it is never committed.
Every command looks it up:

```bash
OCI="oci --auth security_token --profile oke-demo"
NS=$($OCI os ns get --query data --raw-output)
B=oci-k8s-gitops-demo-pg-backups
```

Access to the cluster: [access runbook](access.md).

## The alert fired: PostgresBackupMissing

1. Look at the last runs:

   ```bash
   kubectl -n link-shortener get cronjob postgres-backup
   kubectl -n link-shortener get jobs -l app.kubernetes.io/name=postgres-backup --sort-by=.metadata.creationTimestamp
   kubectl -n link-shortener logs job/<job-name> -c dump
   kubectl -n link-shortener logs job/<job-name> -c upload
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
   kubectl -n link-shortener create job --from=cronjob/postgres-backup postgres-backup-manual-$(date +%H%M)
   kubectl -n link-shortener wait job/postgres-backup-manual-<HHMM> --for=condition=complete --timeout=420s
   ```

   The upload log ends with `uploaded link-shortener/<timestamp>.pgc`. The
   alert clears within about 15 minutes.

## Restore drill (do this after any change to the backup path)

Restores a dump into a scratch database next to the live one and compares
them. The live database is only read.

```bash
# 1. Pick and download a dump with your own login (the cluster cannot read it).
$OCI os object list -ns "$NS" -bn "$B" --query 'data[].{name:name,size:size}' --output table
O=link-shortener/<timestamp>.pgc
$OCI os object get -ns "$NS" -bn "$B" --name "$O" --file restore.pgc

# 2. Restore into a scratch database.
psql_() { kubectl -n link-shortener exec -i postgres-0 -- sh -c "psql -X -At -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -d $1 -c \"$2\""; }
psql_ postgres "CREATE DATABASE restore_drill"
kubectl -n link-shortener exec -i postgres-0 -- sh -c 'pg_restore --no-owner --exit-on-error -U "$POSTGRES_USER" -d restore_drill' < restore.pgc

# 3. Compare: rows in the dump vs live rows created before the dump time.
psql_ restore_drill "SELECT count(*) FROM links"
psql_ linkshortener "SELECT count(*) FROM links WHERE created_at <= '<dump time, UTC>+00'"

# 4. Clean up.
psql_ postgres "DROP DATABASE restore_drill"
rm restore.pgc   # it holds real data
```

Result on 2026-10-25: 9 rows restored, identical (code and URL) to the 9 live
rows created before the dump.

## Real restore

Decide first which case you are in. A dump only holds data up to its time;
links created after it are lost (ADR 0007 accepts up to a day).

**A. Bad data, database still running** (for example, rows deleted by
mistake). Restore into a scratch database first (drill steps 1-3), check it,
then replace the live table:

```bash
kubectl -n link-shortener exec -i postgres-0 -- sh -c 'pg_restore --no-owner --role=linkshortener_app --clean --if-exists --exit-on-error -U "$POSTGRES_USER" -d linkshortener' < restore.pgc
```

`--clean --if-exists` drops and recreates the `links` table from the dump.
`--role=linkshortener_app` makes the restored table belong to the app's role
(ADR 0018). Without it the table belongs to the admin and the app gets
"permission denied" until the next ArgoCD sync hands it back.
Requests during those seconds may get 503; the app recovers on its own.

**B. Volume lost** (the PVC or block volume is gone). The StatefulSet starts
Postgres on a new, empty volume. The app creates an empty table on its first
request (ADR 0016). Then run the same `pg_restore --clean --if-exists` command
as in A.

After either case: check with `curl` (access runbook) that an old short link
still redirects.

## What was verified (2026-10-25)

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
