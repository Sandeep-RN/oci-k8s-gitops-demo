output "backup_bucket_name" {
  description = "Bucket the backup CronJob writes to. The namespace is looked up at runtime, never committed."
  value       = oci_objectstorage_bucket.pg_backups.name
}

output "backup_retention_days" {
  value = var.backup_retention_days
}
