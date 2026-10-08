mock_provider "aws" {}

variables {
  operator_ipv4_cidr        = "203.0.113.10/32"
  operator_ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test"
  budget_notification_email = "operator@example.com"
}

run "accepts_valid_operator_inputs" {
  command = plan

  assert {
    condition     = local.instance_name == "rivet-workspace"
    error_message = "The instance must use the stable workspace name."
  }

  assert {
    condition     = local.key_pair_name == "rivet-operator"
    error_message = "The key pair must use the stable operator name."
  }

  assert {
    condition     = local.static_ip_name == "rivet-workspace-ip"
    error_message = "The static IP must use the stable workspace name."
  }
}

run "rejects_unrestricted_ssh" {
  command = plan

  variables {
    operator_ipv4_cidr = "0.0.0.0/0"
  }

  expect_failures = [
    var.operator_ipv4_cidr,
  ]
}

run "rejects_private_key_material" {
  command = plan

  variables {
    operator_ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----"
  }

  expect_failures = [
    var.operator_ssh_public_key,
  ]
}

run "rejects_malformed_budget_email" {
  command = plan

  variables {
    budget_notification_email = "not-an-email"
  }

  expect_failures = [
    var.budget_notification_email,
  ]
}
