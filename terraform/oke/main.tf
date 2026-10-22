locals {
  name = "oke-demo"

  # Tags make the teardown check in Cost Analysis a single filter (ADR 0015).
  tags = {
    project     = "oci-k8s-gitops-demo"
    lifecycle   = "ephemeral-oke"
    teardown_by = "2026-11-15"
  }

  ad            = data.oci_identity_availability_domains.ads.availability_domains[0].name
  fault_domains = [for fd in data.oci_identity_fault_domains.fds.fault_domains : fd.name]

  node_image_ids = [
    for s in data.oci_containerengine_node_pool_option.all.sources :
    s.image_id if s.source_name == var.node_image_name
  ]
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# The home region has a single AD, so spreading across fault domains is the
# only placement diversity available (no multi-AZ claims in the README).
data "oci_identity_fault_domains" "fds" {
  compartment_id      = var.tenancy_ocid
  availability_domain = local.ad
}

data "oci_containerengine_node_pool_option" "all" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_ocid
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_ocid
  name               = local.name
  kubernetes_version = var.kubernetes_version
  vcn_id             = oci_core_vcn.this.id
  # Basic: free control plane. Enhanced is billed per cluster-hour and is the
  # console default, so this is set explicitly (ADR 0015).
  type          = "BASIC_CLUSTER"
  freeform_tags = local.tags

  # Same overlay model as k3s; no per-pod VCN IPs or extra VNIC limits.
  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  # Private API endpoint only; kubectl goes through OCI Bastion (ADR 0010).
  endpoint_config {
    is_public_ip_enabled = false
    subnet_id            = oci_core_subnet.api.id
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.lb.id]

    kubernetes_network_config {
      pods_cidr     = var.pods_cidr
      services_cidr = var.services_cidr
    }
  }
}

resource "oci_containerengine_node_pool" "workers" {
  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_ocid
  name               = "${local.name}-workers"
  kubernetes_version = var.kubernetes_version
  node_shape         = var.node_shape
  freeform_tags      = local.tags

  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gbs
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = try(local.node_image_ids[0], null) # validated by the precondition below
    boot_volume_size_in_gbs = var.boot_volume_gbs
  }

  node_config_details {
    size          = var.node_count
    freeform_tags = local.tags

    # Listing every fault domain lets OKE place each node in a different one.
    placement_configs {
      availability_domain = local.ad
      subnet_id           = oci_core_subnet.workers.id
      fault_domains       = local.fault_domains
    }
  }

  initial_node_labels {
    key   = "pool"
    value = "workers"
  }

  lifecycle {
    precondition {
      condition     = length(local.node_image_ids) == 1
      error_message = "node_image_name not found (or ambiguous) in this region. List images with: oci ce node-pool-options get --node-pool-option-id all"
    }
    precondition {
      condition     = strcontains(var.node_image_name, "OKE-${trimprefix(var.kubernetes_version, "v")}-")
      error_message = "node_image_name must be built for kubernetes_version."
    }
  }
}

# Free managed bastion: port-forwarding sessions to the private API endpoint.
# Sessions are short-lived and created on demand (not in Terraform state).
resource "oci_bastion_bastion" "this" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  name                         = "okedemo" # bastion names must be alphanumeric
  target_subnet_id             = oci_core_subnet.api.id
  client_cidr_block_allow_list = [var.bastion_client_cidr]
  max_session_ttl_in_seconds   = 10800 # 3 h, the service maximum
  freeform_tags                = local.tags
}
