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

  assert {
    condition     = aws_lightsail_key_pair.operator.name == "rivet-operator"
    error_message = "The Lightsail key pair must use the stable operator name."
  }

  assert {
    condition = (
      aws_lightsail_key_pair.operator.public_key ==
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test"
    )
    error_message = "The Lightsail key pair must contain only the supplied public key."
  }

  assert {
    condition = (
      aws_lightsail_instance.workspace.name == "rivet-workspace" &&
      aws_lightsail_instance.workspace.availability_zone == "ap-south-1a" &&
      aws_lightsail_instance.workspace.blueprint_id == "ubuntu_24_04" &&
      aws_lightsail_instance.workspace.bundle_id == "medium_3_0" &&
      aws_lightsail_instance.workspace.ip_address_type == "ipv4"
    )
    error_message = "The Lightsail instance must match the accepted location, image, size, and address type."
  }

  assert {
    condition = (
      aws_lightsail_instance.workspace.key_pair_name ==
      aws_lightsail_key_pair.operator.name
    )
    error_message = "The Lightsail instance must use the managed operator key pair."
  }

  assert {
    condition = (
      yamldecode(aws_lightsail_instance.workspace.user_data).users[1].name ==
      "rivet-admin"
    )
    error_message = "The Lightsail instance must receive the reviewed cloud-init template."
  }

  assert {
    condition     = aws_lightsail_instance.workspace.tags.Name == "rivet-workspace"
    error_message = "The Lightsail instance must carry its stable Name tag."
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
