# ADR-0002: Keep the Phase 1 host always on

- Status: Accepted
- Date: 2026-10-07
- Decision owners: Project maintainers
- Review trigger: Cost-limit pressure, measured idle waste, or a secure
  remote-wake design

## Context

Rivet exists so development can continue from a phone when the developer's
laptop is off or unavailable. The Phase 1 runtime therefore needs to be ready
without requiring a second trusted computer to start it.

The selected AWS Lightsail plan does not become cheaper when its instance is
stopped. AWS charges for Lightsail instances until they are deleted, including
while they are in the stopped state. Stop and start can still be useful for
maintenance, but they are not a cost-control mechanism for this host.

Deleting the instance would stop its compute charge, but resuming would then be
a provisioning and recovery operation. Lightsail restores a snapshot by
creating a new instance, and custom firewall rules from the original instance
do not carry over. A phone-only resume flow would consequently need privileged
AWS control-plane access, repeatable network configuration, readiness checks,
and a safe way to discover the replacement endpoint. Rivet has not designed or
secured that control plane in Phase 1.

T3 Code also requires its remote host to remain running and reachable while it
is used. Its Linux background service can start at boot and survive logout.
T3 Connect can recreate its tunnel when a linked host returns, but it does not
start a stopped or deleted cloud instance.

The operational facts in this record were checked on 2026-10-07. AWS billing
behavior and T3 lifecycle behavior must be rechecked before provisioning.

## Decision

The Phase 1 Lightsail instance will run continuously, 24 hours a day and seven
days a week.

The lifecycle policy is:

| Event | Phase 1 behavior |
| --- | --- |
| Normal operation | Keep the Lightsail instance running |
| No connected client | Keep the instance and T3 Code running |
| Laptop unavailable | No change; the laptop is outside the runtime path |
| Mobile disconnect | Keep all host processes running and allow reconnection |
| Host boot or reboot | Start T3 Code through its Linux background service |
| Planned maintenance | Reboot only after warning about interrupted work |
| Instance stop | Manual exception for troubleshooting, not routine operation |
| Instance deletion | Explicit teardown or disaster recovery only |
| Snapshot restore | Recovery procedure, not ordinary resume behavior |

Rivet will not implement automatic idle suspension, scheduled shutdown, or
snapshot-delete-restore cycling in Phase 1. No Phase 1 component may delete the
instance merely to remain below the spending limit.

T3 Code will be installed with `t3 service install` for the non-root service
user. The resulting systemd user service and lingering configuration must be
verified rather than assumed. Rivet must not run T3 Code as root.

This decision selects host lifecycle behavior only. It does not select T3
Connect, Tailscale, or direct HTTPS as the connection route, and it does not
claim high availability for the single-host design.

## Why this option

Always-on operation is the only Phase 1 choice that meets the immediate-access
product promise without adding another remote control system. A suspended host
cannot run T3 Code, receive mobile actions, continue an agent task, or recover
itself. Requiring the developer to enter the AWS console from a phone would
make provider administration part of every resume and would create a second
mobile authentication and authorization path that Rivet would need to secure.

Always-on operation also fits the accepted cost decision. The selected
Lightsail plan has a USD 24 monthly maximum before tax, and stopping it does
not reduce that charge. Automated stop and start would therefore add downtime
and recovery risk without producing the intended saving.

The decision does not mean every activity survives a reboot. T3 documents that
service restarts interrupt running agent turns, terminals, and remote clients.
Saved threads, settings, and project files remain, and supported threads can
optionally continue after restart, but terminal commands may still be lost.
Continuous operation reduces those interruptions; it does not hide them.

## Availability acceptance gate

Before Phase 1 accepts this lifecycle, the real Lightsail host must pass all of
the following checks without using the developer's laptop:

1. Install T3 Code for a non-root user with `t3 service install`.
2. Verify that the systemd user unit is enabled, active, and configured to
   survive logout.
3. Start a repository thread, disconnect every client, and confirm that the T3
   service and intended agent work remain on the host.
4. Reconnect from the official T3 Code mobile app without creating a new
   workspace or recloning the repository.
5. Perform a planned host reboot and measure the time from reboot initiation to
   successful mobile reconnection.
6. Confirm after reboot that the repository, Git branch and worktree, saved T3
   thread, settings, and provider configuration remain available.
7. Confirm that the selected connection route recovers without laptop action.
8. Inspect the service status and logs for restart loops, authentication
   failures, or accidental execution as root.

The lifecycle fails acceptance if T3 does not start automatically, a laptop or
interactive SSH session is required to restore access, durable state is lost,
or the phone cannot reconnect after the documented recovery interval. A failed
gate requires a corrective decision before Phase 1 is considered available.

The test report must distinguish durable state from interrupted processes. It
must not describe an in-flight terminal command or unsupported agent turn as
recovered unless that exact behavior was observed.

## Operational controls

- Monitor the T3 service and host reachability; "instance running" alone is
  not sufficient evidence that the environment is usable.
- Alert on repeated service restarts, failed boot, disk pressure, and failed
  remote connection registration.
- Schedule disruptive maintenance rather than applying a reboot in the middle
  of active work.
- Preserve persistent state and a restorable snapshot before destructive host
  maintenance.
- Keep AWS account recovery available independently of the Rivet host.
- Retain the USD 30 budget alerts required by ADR-0001; availability does not
  override the spending limit.

## Consequences

### Positive

- The workspace is ready from a phone without first waking another machine.
- Agent processes can continue while all clients are disconnected, subject to
  each agent provider's own behavior.
- T3 Code can restart automatically after an ordinary host reboot.
- The operating model is simple and matches Lightsail's stopped-instance
  billing.
- Phase 1 does not expose AWS lifecycle credentials through a new Rivet control
  plane.

### Negative

- The host consumes its normal monthly allocation even when no developer is
  connected.
- A single host remains a single point of failure; always on is not highly
  available.
- Planned reboots and T3 updates can interrupt agents, terminals, and clients.
- Host compromise would have a longer exposure window than an environment that
  exists only during active work.
- Cost cannot be reduced through routine stop and start on the selected
  Lightsail product.

## Alternatives considered

### Stop the instance when idle and start it manually

This preserves the disk but does not reduce Lightsail charges. It also makes
the environment unavailable until someone with AWS access starts it. The
option adds friction and downtime without meeting either the availability or
cost objective, so it is rejected.

### Delete the instance and recreate it from a snapshot

This can stop compute charges between sessions, but it is reprovisioning rather
than suspend and resume. The replacement is a new resource, custom firewall
rules are not restored, and endpoint and readiness handling must be repeated.
It also requires a protected phone-accessible AWS control path when no laptop
is available. This is reserved for recovery or explicit teardown in Phase 1.

### Add a Rivet wake and resume control plane

A separate always-available service could authenticate a phone request and
recreate or start the workspace. That service would need its own hosting,
identity, narrowly scoped AWS permissions, audit log, abuse protection,
failure handling, and cost model. It is disproportionate before the basic
single-host workflow is proven and is deferred.

### Scheduled shutdown outside normal hours

Travel and mobile work do not have reliable office hours. A schedule could
interrupt an agent or make the host unavailable exactly when the user needs
it, while a stopped Lightsail instance would continue accruing charges. It is
rejected for Phase 1.

## Revisit this decision when

- the selected provider introduces a true suspend mode that materially reduces
  cost while preserving the instance;
- a measured usage history shows enough idle time to justify a secure resume
  control plane;
- the monthly service-cost forecast exceeds USD 30;
- Rivet supports multiple users or workspaces whose combined idle cost changes
  the economics;
- Phase 1 requires high availability rather than single-host recovery;
- the threat model requires ephemeral hosts or shorter credential exposure;
- T3 Code gains a documented remote wake capability; or
- resume can be completed and verified from the phone without broad cloud
  credentials or laptop involvement.

Any replacement decision must define authentication, authorization, endpoint
discovery, state durability, recovery time, failed-resume behavior, and the
cost of the control plane itself.

## Sources

- [Lightsail billing and account management](https://docs.aws.amazon.com/en_en/lightsail/latest/userguide/amazon-lightsail-frequently-asked-questions-faq-billing-and-account-management.html)
- [Delete a Lightsail instance](https://docs.aws.amazon.com/lightsail/latest/userguide/delete-an-amazon-lightsail-instance.html)
- [Create a Lightsail instance from a snapshot](https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-how-to-create-instance-from-snapshot.html)
- [Lightsail snapshot behavior](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-snapshots-in-amazon-lightsail.html)
- [T3 Code remote access](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)
- [T3 Code background service](https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md)
- [T3 Code updating and restart behavior](https://github.com/pingdotgg/t3code/blob/main/docs/user/updating.md)
- [T3 Code connection runtime](https://github.com/pingdotgg/t3code/blob/main/docs/internals/connection-runtime.md)
