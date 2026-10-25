# Backup storage and its access (ADR 0007, ADR 0017). All Always Free:
# Object Storage within 20 GB; IAM is free.

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.tenancy_ocid
}

resource "oci_objectstorage_bucket" "pg_backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = var.backup_bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  # No versioning: the backup job may only create new objects (never overwrite
  # or delete), so there are no older versions to protect.
  versioning = "Disabled"

  freeform_tags = { project = "oci-k8s-gitops-demo", purpose = "pg-backups" }

  lifecycle {
    # Backups are the one thing a rebuild cannot recreate.
    prevent_destroy = true
  }
}

# Old dumps expire on their own, so the backup job never needs delete rights.
resource "oci_objectstorage_object_lifecycle_policy" "pg_backups" {
  namespace = data.oci_objectstorage_namespace.this.namespace
  bucket    = oci_objectstorage_bucket.pg_backups.name

  rules {
    name        = "expire-dumps"
    action      = "DELETE"
    target      = "objects"
    is_enabled  = true
    time_amount = var.backup_retention_days
    time_unit   = "DAYS"
  }

  # Lifecycle rules run as the Object Storage service, which needs its own policy.
  depends_on = [oci_identity_policy.objectstorage_lifecycle]
}

# Every instance in the project compartment: the OKE workers now, the k3s node
# later. The compartment holds nothing else.
resource "oci_identity_dynamic_group" "cluster_nodes" {
  compartment_id = var.tenancy_ocid
  name           = "oci-k8s-gitops-demo-nodes"
  description    = "Instances in the oci-k8s-gitops-demo compartment (cluster nodes); used for instance-principal backups."
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_ocid}'}"
}

resource "oci_identity_policy" "pg_backups_write_only" {
  compartment_id = var.compartment_ocid
  name           = "oci-k8s-gitops-demo-pg-backups-write-only"
  description    = "Nodes may add new objects to the backup bucket; nothing else (ADR 0017)."
  # Write-only on purpose. Any pod on a node can obtain instance-principal
  # credentials (pods reach the metadata service), so the policy is the real
  # boundary: create new objects and list them, but never read, overwrite or
  # delete a backup. Restores run with the operator's own login.
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.cluster_nodes.name} to manage objects in compartment id ${var.compartment_ocid} where all {target.bucket.name = '${oci_objectstorage_bucket.pg_backups.name}', any {request.permission = 'OBJECT_CREATE', request.permission = 'OBJECT_INSPECT'}}",
  ]
}

resource "oci_identity_policy" "objectstorage_lifecycle" {
  compartment_id = var.compartment_ocid
  name           = "oci-k8s-gitops-demo-objectstorage-lifecycle"
  description    = "Lets Object Storage run lifecycle rules (expire old dumps) in this compartment."
  statements = [
    "Allow service objectstorage-${var.region} to manage object-family in compartment id ${var.compartment_ocid}",
  ]
}
