# The repo is public, so addresses are marked sensitive: they are hidden in plan
# and apply output (and in pasted logs). Read one deliberately with
#   terraform output -raw public_ip

output "public_ip" {
  description = "Public IP for SSH."
  value       = oci_core_instance.node.public_ip
  sensitive   = true
}

output "instance_id" {
  description = "Instance OCID."
  value       = oci_core_instance.node.id
  sensitive   = true
}
