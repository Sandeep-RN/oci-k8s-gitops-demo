# 0007. PostgreSQL as a StatefulSet with nightly dump backups

Status: Accepted (2026-10-21, revised 2026-10-21 after review)

## Context
The app needs a database. On a single 12 GB node an operator's failover has nothing to fail over to, and every extra controller costs memory and learning time.

## Decision
- Run one PostgreSQL replica as a StatefulSet on a local-path volume.
- A nightly CronJob runs `pg_dump` to an Object Storage bucket with a lifecycle rule that deletes dumps after a set number of days, keeping usage well under 20 GB.
- The CronJob authenticates to Object Storage with instance principals (a dynamic group and policy for the node) if that works from pods; otherwise a narrowly scoped key stored as a SealedSecret. Decided in the Phase 3 spec.
- A restore is tested, not assumed.

## Consequences
- Data loss window is up to a day.
- A tested restore is part of the runbook and the demo.

## At scale
CloudNativePG (or a managed database) with replicas, continuous WAL archiving and point-in-time recovery.
