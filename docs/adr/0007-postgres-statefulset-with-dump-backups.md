# 0007. PostgreSQL as a StatefulSet with nightly dump backups

Status: Accepted (2026-10-21)

## Context
The app needs a database. On a single 12 GB node an operator's failover has nothing to fail over to, and every extra controller costs memory and learning time.

## Decision
Run one PostgreSQL replica as a StatefulSet on a local-path volume. A nightly CronJob runs `pg_dump` to Object Storage. A restore is tested, not assumed.

## Consequences
- Data loss window is up to a day.
- A tested restore is part of the runbook and the demo.

## At scale
CloudNativePG (or a managed database) with replicas, continuous WAL archiving and point-in-time recovery.
