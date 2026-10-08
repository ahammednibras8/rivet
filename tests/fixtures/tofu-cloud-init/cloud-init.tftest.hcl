variables {
  operator_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test"
}

run "renders_minimal_ansible_bridge" {
  command = plan

  assert {
    condition     = local.cloud_init.package_update == true
    error_message = "Cloud-init must refresh package metadata."
  }

  assert {
    condition = toset(local.cloud_init.packages) == toset([
      "python3",
      "python3-apt",
    ])
    error_message = "Cloud-init must install only the Ansible Python prerequisites."
  }

  assert {
    condition = (
      length(local.cloud_init.users) == 2 &&
      local.cloud_init.users[0] == "default" &&
      local.cloud_init.users[1].name == "rivet-admin" &&
      local.cloud_init.users[1].lock_passwd == true &&
      local.cloud_init.users[1].sudo == "ALL=(ALL) NOPASSWD:ALL"
    )
    error_message = "Cloud-init must retain the default user and create the locked Rivet administrator."
  }

  assert {
    condition = local.cloud_init.users[1].ssh_authorized_keys == [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test",
    ]
    error_message = "Cloud-init must install exactly the supplied public key."
  }

  assert {
    condition = (
      local.cloud_init.ssh_pwauth == false &&
      local.cloud_init.disable_root == true
    )
    error_message = "Cloud-init must disable password and root SSH login."
  }

  assert {
    condition = (
      !contains(keys(local.cloud_init), "runcmd") &&
      !contains(keys(local.cloud_init), "write_files") &&
      !strcontains(local.rendered_cloud_init, "PRIVATE KEY")
    )
    error_message = "Cloud-init must not contain provisioning commands, embedded files, or private keys."
  }
}
