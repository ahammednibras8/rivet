# ADR-0005: Use Tailscale for private administration

- Status: Accepted
- Date: 2026-10-13
- Decision owners: Project maintainers
- Review trigger: Tailnet ownership change, multi-user administration,
  unavailable recovery path, or replacement of AWS Lightsail

## Context

Rivet needs an administrative route for hardened OpenSSH and Ansible that is
separate from the T3 client route selected by ADR-0003. A control node's public
IPv4 address can rotate, so durable host access must not depend on maintaining
the same address in both the Lightsail firewall and UFW.

AWS creates Ubuntu Lightsail instances with public TCP ports 22 and 80 open to
all addresses by default. The AWS provider's
`aws_lightsail_instance_public_ports` resource requires at least one
`port_info` block, so omitting that resource does not express or reproduce a
zero-port policy. The accepted design must replace those AWS defaults during a
fresh provision while failing closed after bootstrap.

Tailscale can provide a private network path without replacing OpenSSH or
Ansible. Enrollment authority is interactive and must not be stored in Git,
OpenTofu state, cloud-init, or Ansible variables.

## Decision

Rivet will use standard OpenSSH over the Tailscale network for routine host
administration. This is not Tailscale SSH, Tailscale Serve, Tailscale Funnel,
or a T3 client route.

The administrative path has two explicit stages:

1. During initial provisioning or an approved rebuild, OpenTofu replaces the
   Lightsail default rules with one TCP/22 rule restricted to the control
   node's reviewed IPv4 `/32`. UFW remains disabled while the bootstrap runs.
2. Ansible installs the pinned Tailscale client and stops before the firewall
   role unless `tailscale status --json` reports `BackendState` as `Running`.
   A human enrolls `rivet-workspace`, disables key expiry for that trusted
   server, verifies private SSH, and reruns Ansible over its Tailscale address.

After private convergence:

- UFW allows inbound TCP/22 only on `tailscale0` and denies other inbound
  traffic;
- the Lightsail TCP/22 source is replaced with `192.0.2.1/32`, an unroutable
  TEST-NET-1 sentinel;
- no public IPv6 CIDR, Lightsail browser-connect alias, HTTP, HTTPS, or T3
  listener is allowed;
- public TCP/22 must be unreachable; and
- OpenTofu and a second Ansible run must both report no drift.

The OpenTofu variable defaults to the sentinel. Supplying a real bootstrap
`/32` is a deliberate, temporary human action, never a routine response to a
rotating address.

The server uses the ordinary hardened `sshd` configuration and the dedicated
Rivet RSA key. Tailscale transports packets only. Host-key verification remains
mandatory when the connection switches from the static public address to the
Tailscale address.

## Why this option

This separates three concerns cleanly:

- T3 Connect remains the only route used by T3 clients;
- Tailscale supplies private network reachability for administration; and
- OpenSSH continues to own host authentication and authorization.

Routine Ansible runs no longer depend on a residential or mobile public IP.
The staged enrollment guard prevents a new host from enabling private-only UFW
rules before the private route exists. The sentinel resource also preserves
declarative ownership of the Lightsail firewall and overwrites AWS's unsafe
base-image defaults on a fresh provision.

## Security boundaries

- Tailscale enrollment URLs are single-use secrets and must not be published.
- Tailscale auth keys, OAuth credentials, and reusable enrollment authority
  are out of scope and must not enter repository files or OpenTofu state.
- Tailscale SSH is disabled; access remains subject to the OpenSSH key and
  daemon policy.
- The server's Tailscale key expiry is disabled only after interactive
  enrollment and only for the trusted always-on server.
- A control device must be removed from the tailnet when lost or retired.
- Tailnet access policy and device ownership require a new review before a
  second administrator or user is added.

## Failure and recovery

A Tailscale control-plane or daemon failure can remove the routine
administrative route. The sentinel must not be widened casually: any public
bootstrap recovery requires a reviewed plan, an exact `/32`, explicit human
approval, and a documented return to sentinel state. Until a separate
break-glass procedure is implemented and tested, rebuild or recovery work is
handled as an exceptional operation rather than a permanently open fallback.

T3 Connect may remain available to the product while Tailscale is unavailable,
but it is not treated as an administrative shell or as proof that OpenSSH is
recoverable.

## Consequences

- Operators must install and authenticate the Tailscale client on approved
  control devices.
- Initial provisioning has a deliberate interactive enrollment checkpoint.
- The tailnet becomes an administrative dependency and must be included in
  device-revocation and recovery procedures.
- The Lightsail firewall contains one sentinel-scoped rule because the current
  provider cannot declare an empty public-port set.
- The provider limitation is tracked upstream in
  [hashicorp/terraform-provider-aws#50420](https://github.com/hashicorp/terraform-provider-aws/issues/50420).

## Verification

The decision is accepted only while automated and manual checks prove:

1. a fresh plan replaces Lightsail defaults with exactly one scoped TCP/22
   rule;
2. `/0` bootstrap inputs are rejected;
3. Ansible cannot reach the host-firewall role before Tailscale reports
   `Running`;
4. the final Lightsail rule uses only `192.0.2.1/32`;
5. UFW permits SSH only on `tailscale0`;
6. public TCP/22 is unreachable while private SSH succeeds;
7. the second Ansible run reports `changed=0`; and
8. the final OpenTofu plan exits with zero changes and zero drift.

## References

- [ADR-0003: T3 Connect remote access](0003-use-t3-connect-for-phase-1-remote-access.md)
- [ADR-0004: OpenTofu and Ansible automation](0004-use-opentofu-and-ansible-for-phase-1-automation.md)
- [AWS Lightsail default firewall rules](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-firewall-and-port-mappings-in-amazon-lightsail.html#default-firewall-rules)
- [AWS CLI `close-instance-public-ports`](https://docs.aws.amazon.com/cli/latest/reference/lightsail/close-instance-public-ports.html)
- [Tailscale key expiry](https://tailscale.com/docs/features/access-control/key-expiry)
- [Tailscale on Ubuntu with UFW](https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw)
