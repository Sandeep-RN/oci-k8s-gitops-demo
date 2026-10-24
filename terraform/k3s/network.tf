# One public subnet for the node. Inbound is SSH from one CIDR only; 6443 is
# never opened (kubectl goes through an SSH tunnel, ADR 0010). Ports 80/443 from
# the Network Load Balancer are added with the edge ticket (ADR 0004).

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${local.name}-vcn"
  dns_label      = "k3sdemo"
  freeform_tags  = local.tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-igw"
  freeform_tags  = local.tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-rt-public"
  freeform_tags  = local.tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_security_list" "node" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name}-sl"
  freeform_tags  = local.tags

  ingress_security_rules {
    source      = var.ssh_allowed_cidr
    protocol    = "6" # TCP
    description = "SSH from the allowed CIDR only"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # ICMP type 3 code 4 ("fragmentation needed") keeps Path MTU discovery working.
  ingress_security_rules {
    source      = "0.0.0.0/0"
    protocol    = "1" # ICMP
    description = "path MTU discovery"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    description = "outbound: package installs, image pulls, DNS, NTP"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.this.id
  cidr_block        = cidrsubnet(var.vcn_cidr, 8, 1) # /24
  display_name      = "${local.name}-public"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.node.id]
  freeform_tags     = local.tags
}
