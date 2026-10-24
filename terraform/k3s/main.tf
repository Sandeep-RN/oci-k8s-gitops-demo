locals {
  name = "k3s-node"

  tags = {
    project   = "oci-k8s-gitops-demo"
    lifecycle = "always-free"
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# The image is looked up, not hard-coded: image OCIDs are region-specific and
# would otherwise end up in a public repo. Filtering by shape returns only the
# aarch64 build that runs on A1.
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "node" {
  compartment_id = var.compartment_ocid
  # The home region has a single AD (see docs); there is no other AD to try
  # when this one reports out of host capacity.
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = local.name
  shape               = var.shape
  freeform_tags       = local.tags

  shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    display_name     = "${local.name}-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    # No secrets here: the k3s token and kubeconfig are created on the node and
    # stay there (ADR 0010).
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
      k3s_version = var.k3s_version
    }))
  }

  # Block the instance metadata v1 endpoint (SSRF hardening).
  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  lifecycle {
    # A1 capacity is scarce; an instance that is destroyed may never come back
    # (ADR 0001). To lift this on purpose (the one-time rebuild proof), edit it
    # in a reviewed PR.
    prevent_destroy = true

    # Oracle publishes new image builds regularly. Without this, a newer image
    # would make Terraform want to replace the node. Changing user_data is NOT
    # ignored: it also forces replacement, so the plan fails on purpose and the
    # replacement has to be a deliberate decision.
    ignore_changes = [source_details[0].source_id]
  }
}
