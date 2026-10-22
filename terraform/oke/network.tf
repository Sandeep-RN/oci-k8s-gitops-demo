# Network for the OKE target, following Oracle's flannel example layout:
#   api      private  Kubernetes API endpoint + Bastion private endpoint
#   workers  private  nodes; internet egress via NAT (GHCR pulls), OCI via SGW
#   lb       public   load balancers created by Services
# Security lists are per subnet and stateful. Rules are listed as data so the
# full picture is readable in one place.

locals {
  api_cidr     = cidrsubnet(var.vcn_cidr, 12, 0) # /28, 10.20.0.0/28 by default
  workers_cidr = cidrsubnet(var.vcn_cidr, 8, 10) # /24
  lb_cidr      = cidrsubnet(var.vcn_cidr, 8, 20) # /24

  osn_cidr = data.oci_core_services.all.services[0].cidr_block # "all services" label for the SGW
  anywhere = "0.0.0.0/0"

  # ICMP type 3 code 4 ("fragmentation needed") keeps Path MTU discovery working.
  # proto: "6" TCP, "1" ICMP, "all".
  api_ingress = [
    { src = local.workers_cidr, proto = "6", min = 6443, max = 6443, desc = "workers to Kubernetes API" },
    { src = local.workers_cidr, proto = "6", min = 12250, max = 12250, desc = "workers to OKE control plane" },
    { src = local.api_cidr, proto = "6", min = 6443, max = 6443, desc = "Bastion endpoint to Kubernetes API" },
    { src = local.workers_cidr, proto = "1", min = null, max = null, desc = "path MTU discovery" },
  ]
  api_egress = [
    { dst = local.osn_cidr, dst_type = "SERVICE_CIDR_BLOCK", proto = "6", min = 443, max = 443, desc = "control plane to OCI services" },
    { dst = local.osn_cidr, dst_type = "SERVICE_CIDR_BLOCK", proto = "1", min = null, max = null, desc = "path MTU discovery" },
    { dst = local.workers_cidr, dst_type = "CIDR_BLOCK", proto = "6", min = null, max = null, desc = "control plane to workers" },
    { dst = local.workers_cidr, dst_type = "CIDR_BLOCK", proto = "1", min = null, max = null, desc = "path MTU discovery" },
    { dst = local.api_cidr, dst_type = "CIDR_BLOCK", proto = "6", min = 6443, max = 6443, desc = "Bastion endpoint to Kubernetes API" },
  ]

  workers_ingress = [
    { src = local.workers_cidr, proto = "all", min = null, max = null, desc = "pod and node traffic, incl. flannel VXLAN" },
    { src = local.api_cidr, proto = "6", min = null, max = null, desc = "control plane to workers" },
    { src = local.lb_cidr, proto = "6", min = 30000, max = 32767, desc = "load balancer to NodePorts" },
    { src = local.lb_cidr, proto = "6", min = 10256, max = 10256, desc = "load balancer health check (kube-proxy)" },
    { src = local.anywhere, proto = "1", min = null, max = null, desc = "path MTU discovery" },
  ]
  workers_egress = [
    { dst = local.workers_cidr, dst_type = "CIDR_BLOCK", proto = "all", min = null, max = null, desc = "pod and node traffic" },
    { dst = local.api_cidr, dst_type = "CIDR_BLOCK", proto = "6", min = 6443, max = 6443, desc = "Kubernetes API" },
    { dst = local.api_cidr, dst_type = "CIDR_BLOCK", proto = "6", min = 12250, max = 12250, desc = "OKE control plane" },
    { dst = local.osn_cidr, dst_type = "SERVICE_CIDR_BLOCK", proto = "6", min = null, max = null, desc = "OCI services via SGW" },
    # Internet only through the NAT gateway (no public IPs on workers): image pulls, DNS, NTP.
    { dst = local.anywhere, dst_type = "CIDR_BLOCK", proto = "all", min = null, max = null, desc = "internet via NAT" },
  ]

  lb_ingress = [
    { src = local.anywhere, proto = "6", min = 80, max = 80, desc = "HTTP" },
    { src = local.anywhere, proto = "6", min = 443, max = 443, desc = "HTTPS" },
  ]
  # Pre-opened here so the cloud controller can run with security-list
  # management "None"; otherwise it edits these lists and Terraform drifts.
  lb_egress = [
    { dst = local.workers_cidr, dst_type = "CIDR_BLOCK", proto = "6", min = 30000, max = 32767, desc = "to NodePorts" },
    { dst = local.workers_cidr, dst_type = "CIDR_BLOCK", proto = "6", min = 10256, max = 10256, desc = "health check" },
  ]
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${local.name}-vcn"
  dns_label      = "okedemo"
  freeform_tags  = local.tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-igw"
  freeform_tags  = local.tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-nat"
  freeform_tags  = local.tags
}

resource "oci_core_service_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-sgw"
  freeform_tags  = local.tags

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-rt-public"
  freeform_tags  = local.tags

  route_rules {
    destination       = local.anywhere
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-rt-private"
  freeform_tags  = local.tags

  route_rules {
    destination       = local.anywhere
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    destination       = local.osn_cidr
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

resource "oci_core_security_list" "api" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-sl-api"
  freeform_tags  = local.tags

  dynamic "ingress_security_rules" {
    for_each = local.api_ingress
    content {
      source      = ingress_security_rules.value.src
      protocol    = ingress_security_rules.value.proto
      description = ingress_security_rules.value.desc

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.proto == "6" && ingress_security_rules.value.min != null ? [1] : []
        content {
          min = ingress_security_rules.value.min
          max = ingress_security_rules.value.max
        }
      }
      dynamic "icmp_options" {
        for_each = ingress_security_rules.value.proto == "1" ? [1] : []
        content {
          type = 3
          code = 4
        }
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = local.api_egress
    content {
      destination      = egress_security_rules.value.dst
      destination_type = egress_security_rules.value.dst_type
      protocol         = egress_security_rules.value.proto
      description      = egress_security_rules.value.desc

      dynamic "tcp_options" {
        for_each = egress_security_rules.value.proto == "6" && egress_security_rules.value.min != null ? [1] : []
        content {
          min = egress_security_rules.value.min
          max = egress_security_rules.value.max
        }
      }
      dynamic "icmp_options" {
        for_each = egress_security_rules.value.proto == "1" ? [1] : []
        content {
          type = 3
          code = 4
        }
      }
    }
  }
}

resource "oci_core_security_list" "workers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-sl-workers"
  freeform_tags  = local.tags

  dynamic "ingress_security_rules" {
    for_each = local.workers_ingress
    content {
      source      = ingress_security_rules.value.src
      protocol    = ingress_security_rules.value.proto
      description = ingress_security_rules.value.desc

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.proto == "6" && ingress_security_rules.value.min != null ? [1] : []
        content {
          min = ingress_security_rules.value.min
          max = ingress_security_rules.value.max
        }
      }
      dynamic "icmp_options" {
        for_each = ingress_security_rules.value.proto == "1" ? [1] : []
        content {
          type = 3
          code = 4
        }
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = local.workers_egress
    content {
      destination      = egress_security_rules.value.dst
      destination_type = egress_security_rules.value.dst_type
      protocol         = egress_security_rules.value.proto
      description      = egress_security_rules.value.desc

      dynamic "tcp_options" {
        for_each = egress_security_rules.value.proto == "6" && egress_security_rules.value.min != null ? [1] : []
        content {
          min = egress_security_rules.value.min
          max = egress_security_rules.value.max
        }
      }
    }
  }
}

resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-sl-lb"
  freeform_tags  = local.tags

  dynamic "ingress_security_rules" {
    for_each = local.lb_ingress
    content {
      source      = ingress_security_rules.value.src
      protocol    = ingress_security_rules.value.proto
      description = ingress_security_rules.value.desc
      tcp_options {
        min = ingress_security_rules.value.min
        max = ingress_security_rules.value.max
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = local.lb_egress
    content {
      destination      = egress_security_rules.value.dst
      destination_type = egress_security_rules.value.dst_type
      protocol         = egress_security_rules.value.proto
      description      = egress_security_rules.value.desc
      tcp_options {
        min = egress_security_rules.value.min
        max = egress_security_rules.value.max
      }
    }
  }
}

resource "oci_core_subnet" "api" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = local.api_cidr
  display_name               = "${local.name}-api"
  dns_label                  = "api"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.api.id]
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "workers" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = local.workers_cidr
  display_name               = "${local.name}-workers"
  dns_label                  = "workers"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.workers.id]
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "lb" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.this.id
  cidr_block        = local.lb_cidr
  display_name      = "${local.name}-lb"
  dns_label         = "lb"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.lb.id]
  freeform_tags     = local.tags
}
