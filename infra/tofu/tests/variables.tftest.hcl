mock_provider "aws" {}

variables {
  operator_ipv4_cidr        = "203.0.113.10/32"
  operator_ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test"
  budget_notification_email = "operator@example.com"
}

run "accepts_valid_operator_inputs" {
  command = plan
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
