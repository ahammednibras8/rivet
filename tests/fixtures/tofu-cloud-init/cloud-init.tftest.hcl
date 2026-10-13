variables {
  operator_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test"
}

run "renders_minimal_ansible_bridge" {
  command = plan

  assert {
    condition = startswith(
      local.rendered_bootstrap,
      "#!/usr/bin/env bash\n\nset -eu\n"
    )
    error_message = "The Lightsail bootstrap must be a fail-fast Bash script."
  }

  assert {
    condition = alltrue([
      strcontains(local.rendered_bootstrap, "apt-get update"),
      strcontains(local.rendered_bootstrap, "python3"),
      strcontains(local.rendered_bootstrap, "python3-apt"),
      strcontains(local.rendered_bootstrap, "ufw"),
    ])
    error_message = "The bootstrap must install the managed-node prerequisites required by Ansible."
  }

  assert {
    condition = strcontains(
      local.rendered_bootstrap,
      "/usr/sbin/ufw --force disable"
    )
    error_message = "The bootstrap must leave UFW disabled until Ansible installs the approved operator rule."
  }

  assert {
    condition = alltrue([
      strcontains(local.rendered_bootstrap, "useradd"),
      strcontains(local.rendered_bootstrap, "--create-home"),
      strcontains(local.rendered_bootstrap, "--groups adm,sudo"),
      strcontains(local.rendered_bootstrap, "passwd --lock rivet-admin"),
      strcontains(local.rendered_bootstrap, "rivet-admin ALL=(ALL) NOPASSWD:ALL"),
    ])
    error_message = "The bootstrap must create the locked Rivet administrator with passwordless sudo."
  }

  assert {
    condition = strcontains(
      local.rendered_bootstrap,
      "rivet_operator_public_key=\"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7 rivet-test\""
    )
    error_message = "The bootstrap must install exactly the supplied public key."
  }

  assert {
    condition = alltrue([
      strcontains(local.rendered_bootstrap, "PermitRootLogin no"),
      strcontains(local.rendered_bootstrap, "PasswordAuthentication no"),
      strcontains(local.rendered_bootstrap, "KbdInteractiveAuthentication no"),
      strcontains(local.rendered_bootstrap, "AuthenticationMethods publickey"),
      strcontains(local.rendered_bootstrap, "AllowUsers rivet-admin ubuntu"),
      strcontains(local.rendered_bootstrap, "install -d -m 0755 /run/sshd"),
      strcontains(local.rendered_bootstrap, "/usr/sbin/sshd -t"),
      strcontains(local.rendered_bootstrap, "systemctl reload-or-try-restart ssh.service"),
    ])
    error_message = "The bootstrap must validate and install the initial SSH hardening policy."
  }

  assert {
    condition = (
      !strcontains(local.rendered_bootstrap, "PRIVATE KEY") &&
      !strcontains(local.rendered_bootstrap, "BEGIN OPENSSH") &&
      !strcontains(local.rendered_bootstrap, "curl ") &&
      !strcontains(local.rendered_bootstrap, "wget ")
    )
    error_message = "The bootstrap must not contain private keys or download executable content."
  }
}
