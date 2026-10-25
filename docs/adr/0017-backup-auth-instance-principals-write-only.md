# 0017. Backups authenticate with instance principals, write-only

Status: Accepted (2026-10-25). Settles the open point in ADR 0007.

## Context
ADR 0007 left open how the nightly `pg_dump` CronJob authenticates to Object Storage: instance principals "if that works from pods", otherwise a narrowly scoped key stored as a SealedSecret.

Checked on OKE (2026-10-25): pods reach the instance metadata service (HTTP 200 from a throwaway pod), so instance principals work from pods. That also means **any** pod on a node can obtain the node's credentials, the app included. OKE Workload Identity, which would scope credentials to one service account, needs an Enhanced cluster, which is billed (ADR 0015).

## Decision
- The nodes are a dynamic group: every instance in the project compartment (the OKE workers now, the k3s node later). It needs no key, no rotation, and works the same on both clusters.
- Because any pod can use those credentials, the **policy is the boundary**, and it is write-only. The group may only create new objects and list them in the backup bucket (`OBJECT_CREATE`, `OBJECT_INSPECT`): no read, no overwrite, no delete.
- Old dumps expire through a bucket lifecycle rule (14 days), run by the Object Storage service under its own policy. The job never needs delete rights.
- Restores run from the operator's laptop with their own login, not from the cluster.
- The bucket, dynamic group and policies live in a separate Terraform root, `terraform/shared`, with its own state key. Destroying a cluster root can never remove the backups, and the bucket has `prevent_destroy`.
- The Object Storage namespace identifies the tenancy, so it is never committed. The job looks it up at runtime.

## Consequences
- A compromised pod could upload junk into the bucket, but cannot read, alter or delete existing backups. A ransomware-style "delete the backups first" is not possible from the cluster.
- Upload names must be unique (a timestamp), because overwriting is not allowed.
- Pods that should never touch OCI still can, within this policy. Blocking the metadata service for other pods would need NetworkPolicy, which flannel on OKE does not enforce.

## At scale
Workload identity (per service account) instead of node identity, separate buckets per environment, object lock or retention rules for immutability, and cross-region replication.
