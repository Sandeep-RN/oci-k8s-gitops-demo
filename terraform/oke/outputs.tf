# OCIDs and IPs are marked sensitive so `terraform output` and apply logs do
# not print them into screenshots (public repo). Read one with:
#   terraform output -raw <name>

output "cluster_id" {
  value     = oci_containerengine_cluster.this.id
  sensitive = true
}

output "api_private_endpoint" {
  description = "host:port of the private Kubernetes API endpoint (reach it via Bastion)."
  value       = oci_containerengine_cluster.this.endpoints[0].private_endpoint
  sensitive   = true
}

output "bastion_id" {
  value     = oci_bastion_bastion.this.id
  sensitive = true
}

output "node_pool_summary" {
  description = "Non-sensitive summary for the README and checks."
  value = {
    kubernetes_version = var.kubernetes_version
    shape              = var.node_shape
    ocpus              = var.node_ocpus
    memory_gbs         = var.node_memory_gbs
    nodes              = var.node_count
    fault_domains      = length(local.fault_domains)
  }
}
