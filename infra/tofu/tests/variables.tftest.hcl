mock_provider "aws" {}

variables {
  operator_ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test"
  budget_notification_email = "operator@example.com"
}

run "accepts_valid_operator_inputs" {
  command = plan

  assert {
    condition     = var.bootstrap_ipv4_cidr == "192.0.2.1/32"
    error_message = "Bootstrap SSH must fail closed to the TEST-NET-1 sentinel unless explicitly overridden."
  }

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
      aws_lightsail_instance.workspace.bundle_id == "medium_3_1" &&
      aws_lightsail_instance.workspace.ip_address_type == "ipv4"
    )
    error_message = "The Lightsail instance must match the accepted location, image, size, and address type."
  }

  assert {
    condition = try(
      length(aws_lightsail_instance.workspace.add_on) == 1 &&
      one(aws_lightsail_instance.workspace.add_on).type == "AutoSnapshot" &&
      one(aws_lightsail_instance.workspace.add_on).status == "Enabled" &&
      one(aws_lightsail_instance.workspace.add_on).snapshot_time == "20:00",
      false
    )
    error_message = "The workspace must create one daily automatic snapshot at 20:00 UTC."
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
      startswith(
        aws_lightsail_instance.workspace.user_data,
        "#!/usr/bin/env bash\n"
      ) &&
      strcontains(
        aws_lightsail_instance.workspace.user_data,
        "passwd --lock rivet-admin"
      ) &&
      strcontains(
        aws_lightsail_instance.workspace.user_data,
        "/usr/sbin/ufw --force disable"
      ) &&
      strcontains(
        aws_lightsail_instance.workspace.user_data,
        "rivet_operator_public_key=\"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test\""
      )
    )
    error_message = "The Lightsail instance must receive the reviewed shell bootstrap."
  }

  assert {
    condition     = aws_lightsail_instance.workspace.tags.Name == "rivet-workspace"
    error_message = "The Lightsail instance must carry its stable Name tag."
  }

  assert {
    condition     = aws_lightsail_static_ip.workspace.name == "rivet-workspace-ip"
    error_message = "The Lightsail static IP must use the stable workspace name."
  }

  assert {
    condition = (
      aws_lightsail_static_ip_attachment.workspace.static_ip_name ==
      aws_lightsail_static_ip.workspace.name &&
      aws_lightsail_static_ip_attachment.workspace.instance_name ==
      aws_lightsail_instance.workspace.name
    )
    error_message = "The protected static IP must attach to the Rivet workspace instance."
  }

  assert {
    condition = (
      aws_lightsail_instance_public_ports.workspace.instance_name ==
      aws_lightsail_instance.workspace.name &&
      length(aws_lightsail_instance_public_ports.workspace.port_info) == 1 &&
      one(aws_lightsail_instance_public_ports.workspace.port_info).protocol == "tcp" &&
      one(aws_lightsail_instance_public_ports.workspace.port_info).from_port == 22 &&
      one(aws_lightsail_instance_public_ports.workspace.port_info).to_port == 22 &&
      one(aws_lightsail_instance_public_ports.workspace.port_info).cidrs ==
      toset(["192.0.2.1/32"]) &&
      length(one(aws_lightsail_instance_public_ports.workspace.port_info).ipv6_cidrs) == 0 &&
      length(one(aws_lightsail_instance_public_ports.workspace.port_info).cidr_list_aliases) == 0
    )
    error_message = "The public firewall must replace Lightsail defaults with fail-closed bootstrap SSH only."
  }

  assert {
    condition = (
      aws_budgets_budget.workspace.name == "rivet-monthly-cost" &&
      aws_budgets_budget.workspace.budget_type == "COST" &&
      aws_budgets_budget.workspace.limit_amount == "30" &&
      aws_budgets_budget.workspace.limit_unit == "USD" &&
      aws_budgets_budget.workspace.time_unit == "MONTHLY" &&
      one(aws_budgets_budget.workspace.cost_types).include_tax == true &&
      length(aws_budgets_budget.workspace.cost_filter) == 0
    )
    error_message = "The account-wide monthly budget must include tax and enforce the USD 30 governance limit."
  }

  assert {
    condition = (
      length(aws_budgets_budget.workspace.notification) == 3 &&
      contains([
        for alert in aws_budgets_budget.workspace.notification :
        "${alert.notification_type}:${alert.threshold}"
      ], "ACTUAL:80") &&
      contains([
        for alert in aws_budgets_budget.workspace.notification :
        "${alert.notification_type}:${alert.threshold}"
      ], "FORECASTED:100") &&
      contains([
        for alert in aws_budgets_budget.workspace.notification :
        "${alert.notification_type}:${alert.threshold}"
      ], "ACTUAL:100") &&
      alltrue([
        for alert in aws_budgets_budget.workspace.notification :
        alert.comparison_operator == "GREATER_THAN" &&
        alert.threshold_type == "PERCENTAGE"
      ])
    )
    error_message = "The budget must define the accepted actual and forecasted percentage alerts."
  }

  assert {
    condition = nonsensitive(alltrue([
      for alert in aws_budgets_budget.workspace.notification :
      length(alert.subscriber_email_addresses) == 1
    ]))
    error_message = "Every budget alert must have exactly one private email subscriber."
  }

  assert {
    condition = (
      output.workspace_instance_name == aws_lightsail_instance.workspace.name &&
      output.workspace_ipv4_address ==
      aws_lightsail_static_ip_attachment.workspace.ip_address &&
      output.workspace_ssh_user == "rivet-admin"
    )
    error_message = "Outputs must expose only the stable operational connection values."
  }
}

run "accepts_scoped_bootstrap_ipv4" {
  command = plan

  variables {
    bootstrap_ipv4_cidr = "203.0.113.10/32"
  }

  assert {
    condition     = var.bootstrap_ipv4_cidr == "203.0.113.10/32"
    error_message = "Bootstrap SSH must accept one explicitly supplied IPv4 /32."
  }

  assert {
    condition = (
      one(aws_lightsail_instance_public_ports.workspace.port_info).cidrs ==
      toset(["203.0.113.10/32"])
    )
    error_message = "The public firewall must use the explicitly supplied bootstrap IPv4 /32."
  }
}

run "rejects_unrestricted_bootstrap_ssh" {
  command = plan

  variables {
    bootstrap_ipv4_cidr = "0.0.0.0/0"
  }

  expect_failures = [
    var.bootstrap_ipv4_cidr,
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
