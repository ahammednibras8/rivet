# Issue #33 workspace-reprovisioning evidence

Verification date: 2026-10-17

This public record contains only redacted infrastructure and service results.
It excludes AWS account identifiers, public and private addresses, SSH key
material, Tailscale identities, authorization URLs, credentials, repository
approvals, organization repository names, and organization source code.

## Scope boundary

- Tracking issue: [#33](https://github.com/ahammednibras8/rivet/issues/33)
- The workspace was created from the reviewed OpenTofu and Ansible
  configuration rather than restored from the destroyed personal-workspace
  snapshot.
- No organization credential, approval manifest, repository, or source code
  was installed during this issue.
- The existing single-user, human-review, loopback-only T3, private
  administration, and protected-state boundaries remain in force.

## Infrastructure replacement

The human-reviewed saved OpenTofu plan contained exactly six create actions:

```text
aws_budgets_budget.workspace                                 create
aws_lightsail_instance.workspace                            create
aws_lightsail_instance_public_ports.workspace               create
aws_lightsail_key_pair.operator                             create
aws_lightsail_static_ip.workspace                           create
aws_lightsail_static_ip_attachment.workspace                create
```

The replacement used the reviewed Ubuntu 24.04 image, 4 GiB Lightsail plan,
Mumbai region, static address, scoped bootstrap SSH rule, required tags,
automatic snapshot configuration, and USD 30 monthly budget. OpenTofu format
and validation passed. The final refresh reported:

```text
No changes. Your infrastructure matches the configuration.
plan_exit_status=0
```

## SSH trust bootstrap

Lightsail did not populate the API `hostKeys` witness for this new instance.
Before the host contained credentials or organization data, the operator
approved the documented trust-on-first-use fallback. Three independent
ED25519 scans returned one fingerprint. The key was pinned before login, and
the pinned fingerprint matched `/etc/ssh/ssh_host_ed25519_key.pub` after the
first strict connection. Cloud-init then reported `extended_status: done`
with no errors.

During diagnosis, an AWS-generated, short-lived browser-SSH credential was
inadvertently emitted only into the private operator thread. It was not used,
the bootstrap firewall remained restricted to the operator address, and work
paused until the temporary certificate expired. No persistent key,
organization credential, or organization data was exposed.

## Configuration convergence

The clean-host check exposed two ordering assumptions before organization data
was present:

- the T3 role queried the service account during check mode even though check
  mode had not created it;
- the repository-access role expected its local command directory to have
  been created by the later T3 role.

Both failures received focused regression coverage and minimal idempotent
fixes. The first real run intentionally stopped before host-firewall
activation until Tailscale enrollment was complete. Private SSH was verified
before convergence continued. The successful runs reported:

```text
rivet-workspace : ok=56 changed=14 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
rivet-workspace : ok=54 changed=0  unreachable=0 failed=0 skipped=2 rescued=0 ignored=0
```

The zero-change second run proves Ansible idempotence on the replacement.

## Private access and service recovery

The stale Tailscale record for the destroyed host was removed. The online
replacement received the canonical `rivet-workspace` machine name, key expiry
was disabled for unattended operation, and both relayed and direct WireGuard
connectivity succeeded. Public application listeners were not added.

T3 runs as the non-root `rivet` user under an enabled user-level systemd
service with lingering enabled. Before and after reboot, its only TCP listener
was:

```text
127.0.0.1:3773
```

The clean host completed the documented headless T3 Connect authorization.
The phone connected to the new environment over mobile data. After an actual
host reboot, it reconnected without SSH repair or T3 re-pairing. A post-reboot
inspection at 39.52 seconds of host uptime reported:

```json
{
  "serviceActive": true,
  "serviceEnabled": true,
  "desired": true,
  "authenticated": true,
  "linked": true,
  "relayClientStatus": "available",
  "loopbackOnly": true
}
```

The replacement is therefore online and ready for the separately controlled
organization credential and private repository allowlist installation.
