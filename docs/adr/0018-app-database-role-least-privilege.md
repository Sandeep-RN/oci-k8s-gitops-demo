# 0018. The backend connects with its own non-superuser database role

Status: Accepted (2026-10-25)

## Context
The backend connected to Postgres as `POSTGRES_USER`, the role the official image creates at first start. That role is a **superuser** (found during the #53 outage test, tracked in #65). A superuser can run operating system commands on the database server (`COPY ... TO PROGRAM`), read every role's password hash, create roles, and change any setting. So a bug in the app, such as SQL injection, would hand an attacker the Postgres container and every other database on it.

Constraints:
- The app creates its own table on first use (ADR 0016). Since Postgres 15, `CREATE TABLE IF NOT EXISTS` needs `CREATE` on the schema **even when the table already exists**. Tested on 18.6: a role with only `SELECT`/`INSERT` gets "permission denied for schema public".
- The OKE database already exists, so the image's init scripts (`/docker-entrypoint-initdb.d`) will never run again. Whatever creates the role has to work on an existing database as well as a fresh one (k3s).
- Readiness is pod-local (ADR 0016). A backend pod whose credentials do not work yet would still be Ready and answer 503s, so the role must exist **before** any pod uses it.

## Decision
- **App role** `linkshortener_app`: `LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS`. It has `CONNECT` on the app database and `USAGE, CREATE` on schema `public`, and it **owns the `links` table**. The app code does not change.
- **Admin role** (`POSTGRES_USER`, still a superuser) is kept for the Postgres server itself, the nightly backup (ADR 0017) and the role setup. The backend no longer receives it.
- **Role setup:** an ArgoCD Sync hook Job, `postgres-app-role`, runs `sql/app-role.sql` as the admin on **every sync**. The script is idempotent: it creates the role if missing, restates its attributes and password, grants, and hands an existing `links` table to the role. Values come from the environment (`\getenv`), not command-line arguments.
- **Order** by sync wave: Postgres and Secrets (wave 0, waited on until healthy), then the Job (wave 1, waited on until it completes), then the backend Deployment (wave 2).
- **Credentials:** a second SealedSecret, `postgres-app-credentials`, per cluster. Its random password was generated inside the sealing pipe, so no person has seen it. Rotation: re-seal with a new password and sync; the Job sets it before the backend restarts with it.

Rejected:
- **A role with only `SELECT`/`INSERT` on `links`.** Stricter, but the app would have to stop creating its table and the schema would move to the gitops repo, apart from the code that uses it. Owning one table is already far from superuser.
- **Init scripts in the Postgres image.** They run only on an empty data directory, so they would never run on OKE, and a password rotation would need manual SQL.
- **An init container in the backend that creates the role.** The backend pod would then hold the admin password, which is what this change removes.

## Consequences
- The backend can no longer run OS commands, read password hashes, create roles, or touch other databases' objects. Verified in a test with the same SQL: all three were denied.
- Every sync, including each image bump, runs one short Job before the backend changes. If Postgres is down, the sync fails before the backend changes, and the Application's sync retry tries again. A deploy cannot proceed during a database outage. That is acceptable here: new pods could not serve during the outage anyway.
- Restoring a dump as the admin would leave the table owned by the admin and unusable by the app until the next sync. The restore runbook therefore restores with `--role=linkshortener_app`.
- The k3s overlay needs its own `postgres-app-credentials` SealedSecret when that cluster is built (it also needs `postgres-credentials`).
- Backups still use the superuser. A read-only backup role (`pg_read_all_data`) would pair well with this, but it is not done yet.

## At scale
- Separate migrations from runtime: a migration role owns the schema and runs migrations as a pipeline step, and the runtime role gets only DML. That becomes worth it once there are several tables, schema changes that need review, or more than one service per database.
- Short-lived credentials instead of a static password: a secrets manager issuing per-pod database users with a TTL (for example Vault's database engine), or IAM authentication on a managed database.
- On a managed Postgres service there is usually no true superuser at all, so this split is the default there.
