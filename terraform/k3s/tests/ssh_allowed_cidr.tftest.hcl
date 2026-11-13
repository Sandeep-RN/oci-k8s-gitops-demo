# Offline tests for the ssh_allowed_cidr validation (audit finding B11).
#
# Run:  terraform init -backend=false && terraform test   (in terraform/k3s)
#
# Nothing here touches OCI: the provider is mocked, every variable is supplied
# below with a fake value, and `command = plan` never creates anything. The
# real terraform.tfvars is not read. Addresses are documentation ranges only
# (RFC 5737: 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24).

mock_provider "oci" {
  # The instance reads the first availability domain and the first image from
  # these data sources; a mock returns empty lists, so give each one entry.
  mock_data "oci_identity_availability_domains" {
    defaults = {
      availability_domains = [{ name = "fake-AD-1" }]
    }
  }

  mock_data "oci_core_images" {
    defaults = {
      images = [{ id = "ocid1.image.oc1..fake" }]
    }
  }
}

variables {
  tenancy_ocid     = "ocid1.tenancy.oc1..fake"
  compartment_ocid = "ocid1.compartment.oc1..fake"
  region           = "fake-region-1"
  ssh_public_key   = "ssh-ed25519 AAAAfake test@example.invalid"
  ssh_allowed_cidr = "203.0.113.10/32"
}

run "accepts_a_single_host" {
  command = plan

  variables {
    ssh_allowed_cidr = "203.0.113.10/32"
  }
}

run "accepts_a_slash_24" {
  command = plan

  variables {
    ssh_allowed_cidr = "198.51.100.0/24"
  }
}

run "rejects_a_slash_8" {
  command = plan

  variables {
    ssh_allowed_cidr = "10.0.0.0/8"
  }

  expect_failures = [var.ssh_allowed_cidr]
}

run "rejects_a_slash_23_just_below_the_limit" {
  command = plan

  variables {
    ssh_allowed_cidr = "198.51.100.0/23"
  }

  expect_failures = [var.ssh_allowed_cidr]
}

run "rejects_the_whole_internet" {
  command = plan

  variables {
    ssh_allowed_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.ssh_allowed_cidr]
}

run "rejects_a_slash_1" {
  command = plan

  variables {
    ssh_allowed_cidr = "128.0.0.0/1"
  }

  expect_failures = [var.ssh_allowed_cidr]
}

run "rejects_garbage" {
  command = plan

  variables {
    ssh_allowed_cidr = "not-a-cidr"
  }

  expect_failures = [var.ssh_allowed_cidr]
}

run "rejects_a_bare_address_without_prefix" {
  command = plan

  variables {
    ssh_allowed_cidr = "203.0.113.10"
  }

  expect_failures = [var.ssh_allowed_cidr]
}

run "rejects_ipv6" {
  command = plan

  variables {
    ssh_allowed_cidr = "2001:db8::/32"
  }

  expect_failures = [var.ssh_allowed_cidr]
}
