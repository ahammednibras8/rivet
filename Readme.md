# Rivet

Rivet gives T3 Code a durable home in the cloud so AI-assisted development can
continue from a phone without depending on a personal laptop.

Instead of relaying through a laptop that may be asleep, powered off, or on an
unreliable network, Rivet runs the T3 Code server, repositories, agent
providers, and development tools on a persistent cloud host. The existing T3
Code mobile app connects to that host, and the developer continues the same
threads, worktrees, tests, diffs, and pull requests from anywhere.

> **Project status:** The AWS cloud foundation, secure T3 Connect access, and
> the first repository and coding-agent provider are provisioned and verified.
> A supervised T3 action has also completed from Android over mobile data while
> the laptop was fully powered off, and a real host reboot restored the same
> environment, repository, and thread without SSH repair or T3 Connect
> re-pairing. A Lightsail snapshot has also restored the durable workspace into
> a clean replacement and passed phone, thread, repository, worktree,
> credential, firewall, and cleanup verification. Health monitoring, updates,
> and intentional workspace destruction remain in later implementation issues.

## The problem

[T3 Code](https://t3.codes/) already provides mobile clients and can connect
them to a remote environment. Its
[remote-access documentation](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)
states that the machine running the T3 Code server must remain running and
reachable.

A personal laptop is a fragile host for work that must remain available while
travelling or away from a desk:

- it may sleep, shut down, lose power, or lose network connectivity;
- repositories and agent sessions become unreachable with it;
- long-running agent tasks stop being useful if their host disappears;
- remote access depends on the condition of a device that is no longer nearby.

Rivet moves that dependency to an intentionally managed cloud environment.

## Product promise

With Rivet, a developer can:

1. create or select a scoped GitHub issue;
2. start the work in T3 Code from a laptop, browser, or phone;
3. leave the laptop powered off;
4. reconnect from the T3 Code mobile app;
5. inspect the same thread, repository, branch, worktree, command output, and
   agent progress;
6. answer questions, steer the agent, run checks, and review the diff;
7. create or review a pull request; and
8. leave the final merge decision to a human.

The phone is a control surface. Source code, tools, credentials, and agent
processes stay on the cloud host.

## What Rivet is

Rivet is the provisioning and operations layer for a personal, cloud-hosted T3
Code environment. It is responsible for making that environment reproducible,
reachable, persistent, observable, and safe to operate without a laptop.

Rivet will manage:

- creation and configuration of the cloud compute environment;
- installation and supervised startup of the T3 Code server;
- secure connection of the official T3 Code mobile, web, and desktop clients;
- GitHub repository access and workspace initialization;
- installation of approved coding-agent providers and development tools;
- durable storage for T3 data, repositories, worktrees, and session state;
- health checks, restart behavior, updates, backups, and recovery;
- lifecycle operations such as provision, suspend, resume, and destroy.

## What Rivet is not

Rivet is not:

- a replacement or fork of the T3 Code mobile app;
- a new coding-agent harness;
- a remote-desktop stream from a personal laptop;
- a CI, Sentry, or production-alert remediation daemon;
- an autonomous deployment system;
- an autonomous pull-request merger;
- a service that resells model access or stores model credentials in Git.

Rivet uses T3 Code as the agent control plane and supplies the reliable cloud
environment beneath it.

## How it works

### 1. Provision a cloud workspace

Rivet creates a supported Linux host with persistent storage. The host is the
development machine; the user's laptop is not part of the runtime path.

Phase 1 uses one always-on Amazon Lightsail instance in the Mumbai
(`ap-south-1`) region. The accepted host is Ubuntu Server 24.04 LTS on x86-64,
using the General Purpose plan with 2 vCPUs, 4 GB RAM, and an 80 GB SSD. Phase
1 has a USD 30 monthly service-cost limit before tax.

### 2. Bootstrap T3 Code and development tools

Rivet installs the T3 Code command-line server, Git, the selected agent
provider CLI, and the repository's required toolchain. T3 Code and Rivet
services run under supervision and restart after a host reboot.

Provider authentication and source-control authentication are configured on
the cloud host because that is where T3 Code and the agents execute.

### 3. Connect a phone securely

Phase 1 uses T3 Connect rather than inventing a new remote-control protocol or
operating multiple access routes. The Lightsail and host firewalls must not
expose T3 Code, HTTP, or HTTPS listeners to the public internet.

Host administration is a separate path: hardened OpenSSH runs over a private
Tailscale network. Tailscale SSH, Serve, and Funnel are not enabled. A scoped
public `/32` exists only during initial bootstrap or an approved rebuild;
routine operation uses an unroutable firewall sentinel and private-only UFW.

The selected route must:

- authenticate every client;
- encrypt traffic in transit;
- expose no unauthenticated T3 endpoint to the public internet;
- support revoking a lost or replaced phone;
- use the narrowest T3 client scopes that still permit the intended workflow.

### 4. Keep work durable

Repositories, T3 state, active worktrees, and run metadata live on persistent
cloud storage. A phone disconnect must not stop an agent or discard its output.
A host reboot must restore the T3 service and make existing work reachable
again.

Rivet does not promise survival after the host and its storage are both
destroyed. Phase 1 therefore keeps the latest seven daily Lightsail automatic
snapshots and has verified a controlled replacement restore. Automatic
snapshots remain coupled to the source instance, so an irreplaceable recovery
point must be retained manually before deleting that source.

### 5. Deliver through GitHub

Every implementation issue follows the same delivery workflow:

1. Select exactly one open, unblocked milestone issue. Do not create branches
   for later issues in advance.
2. Create `feature/<issue-number>-<short-name>` from the latest `main`, or use
   an equivalent issue-specific worktree.
3. Implement only the issue's declared scope. Record any necessary scope
   change in the issue before expanding the implementation.
4. Run the automated checks named by the issue and record the exact commands
   and results.
5. Perform the issue's manual verification and retain redacted evidence. Never
   publish credentials, authorization links, private logs, prompts, or
   unrelated repository content.
6. Open a focused pull request using `Related: #<issue-number>`. Do not use an
   automatic-closing keyword unless a human explicitly requests it.
7. Leave the pull request open for human review and merge. Rivet must not
   approve, auto-merge, merge, or deploy it.
8. After the merge, confirm the required evidence is present and then close
   the issue manually.

The pull request template carries this evidence contract into each future
change. A blocked issue does not start until its direct blockers are complete.

GitHub organizes and delivers the work. It does not replace the live T3 thread
that carries the investigation and implementation context.

## System boundaries

### Mobile client

The official T3 Code mobile app displays threads and sends developer actions.
It does not hold the authoritative repository or execute build commands.

### T3 Code server

T3 Code owns agent orchestration, threads, worktrees, previews, terminal
sessions, diffs, and pull-request interactions. Rivet installs and operates it
but should not duplicate those features.

### Rivet control layer

Rivet owns cloud provisioning, host configuration, service lifecycle, health,
storage, backup, recovery, and the minimum integration needed to present a
ready T3 environment.

### Cloud workspace

The workspace contains the checked-out repositories, T3 data, approved agent
providers, language toolchains, and isolated worktrees. It is the only machine
that must remain available while mobile work continues.

### GitHub

GitHub remains the source of repositories, issues, branches, and pull
requests. Credentials must be limited to the repositories and operations the
developer explicitly authorizes.

## Security and safety contract

Moving development into the cloud increases availability and also moves source
code and credentials onto an internet-connected host. Phase 1 is not complete
until these boundaries are enforced and tested:

- no dependency on the user's laptop for availability or authentication;
- no unauthenticated public T3 Code endpoint;
- encrypted client-to-host transport;
- key-based administrative access with password login disabled;
- least-privilege GitHub and agent-provider credentials;
- secrets stored outside repositories, command history, logs, and pull
  requests;
- encrypted persistent storage where the selected provider supports it;
- explicit device pairing and session revocation;
- automatic security updates or a documented patching procedure;
- service restart after host reboot;
- bounded logs that do not capture prompts, credentials, or repository content
  unnecessarily;
- recoverable backups with a tested restore procedure;
- no direct pushes to a protected default branch;
- no autonomous merge or deployment;
- human review before every generated pull request is merged.

Destructive lifecycle actions must name the exact cloud host and storage
affected. Destroying a workspace or backup requires explicit human
confirmation.

## Availability model

Rivet removes the laptop as a single point of failure; it does not eliminate
all failure.

The Phase 1 availability target is:

- the cloud host can run while every personal device is offline;
- T3 Code restarts automatically after a host reboot;
- a dropped mobile connection can reconnect to the existing environment;
- agent work may continue while no client is connected;
- repositories and session state live on persistent storage;
- health and storage failures are visible before work is lost;
- a documented restore recreates the environment from backup.

Cloud-provider outages, expired provider credentials, exhausted model quotas,
repository-host outages, and accidental destruction remain external failure
modes and must be reported clearly.

## Phase 1 scope

Phase 1 will prove one complete personal workflow:

- one developer;
- AWS Lightsail in the Mumbai (`ap-south-1`) region;
- one always-on Ubuntu Server 24.04 LTS x86-64 host with persistent storage;
- one GitHub account and explicitly selected repositories;
- T3 Code running as a supervised service;
- T3 Connect as the only supported remote-access route;
- the official T3 Code mobile app connected to the cloud environment;
- at least one approved coding-agent provider;
- restart-safe T3 and repository state;
- health, backup, restore, and destroy procedures;
- an issue-driven branch and pull request completed while the laptop is off.

## Phase 1 acceptance criteria

Phase 1 is complete only when all of the following are demonstrated:

- a fresh cloud workspace can be provisioned from documented configuration;
- the T3 Code mobile app can pair with it without opening an unauthenticated
  public endpoint;
- a repository can be cloned and an agent thread started from the cloud host;
- the laptop can be powered off without interrupting the workflow;
- the same thread can be continued from a phone;
- an agent can edit an isolated branch, run repository checks, and preserve its
  output across a mobile disconnect;
- the host can reboot and restore access to the existing repository and T3
  state;
- a pull request can be created with verification evidence;
- Rivet cannot merge that pull request automatically;
- a backup can restore the environment or its documented durable state;
- the workspace and its storage can be intentionally destroyed without
  affecting any unselected resource.

## Accepted Phase 1 decisions

The architecture decision records are the authoritative technical records.
This summary makes their accepted constraints visible without replacing their
rationale, security controls, acceptance gates, or review triggers.

| Area | Accepted decision | Record |
| --- | --- | --- |
| Cloud foundation | AWS Lightsail in Mumbai (`ap-south-1`); Ubuntu Server 24.04 LTS on x86-64; General Purpose 2 vCPU, 4 GB RAM, 80 GB SSD plan; USD 30 monthly service-cost limit before tax | [ADR-0001](docs/adr/0001-phase-1-cloud-foundation.md) |
| Host lifecycle | Keep the Phase 1 host always on; do not implement routine suspend/resume | [ADR-0002](docs/adr/0002-keep-the-phase-1-host-always-on.md) |
| Remote access | Use T3 Connect as the only Phase 1 route; expose no public T3, HTTP, or HTTPS listener | [ADR-0003](docs/adr/0003-use-t3-connect-for-phase-1-remote-access.md) |
| Automation | Use OpenTofu with the official AWS provider for cloud resources, a private versioned and encrypted S3 backend in `ap-south-1`, minimal cloud-init for first boot, and Ansible Core for host configuration | [ADR-0004](docs/adr/0004-use-opentofu-and-ansible-for-phase-1-automation.md) |

The [cloud-foundation provisioning runbook](docs/runbooks/provision-cloud-foundation.md)
is the operator entry point for the reviewed backend, plan, apply, convergence,
and verification workflow.

The [T3 Connect operations runbook](docs/runbooks/operate-t3-connect.md) covers
the reviewed headless authorization, mobile connection, device revocation,
environment deregistration, recovery, and failure-isolation workflow.

The [GitHub and Codex onboarding runbook](docs/runbooks/onboard-github-and-codex.md)
covers the approved repository boundary, read-only GitHub credential,
cloud-owned checkout, managed Codex provider, supervised mobile thread, and
credential rotation workflow.

The [laptop-independent operation runbook](docs/runbooks/verify-laptop-independent-operation.md)
records and compares protected cloud identities around a real laptop-off,
mobile-data verification without publishing host, environment, thread, or
process identifiers.

The [mobile thread-continuation runbook](docs/runbooks/verify-mobile-thread-continuation.md)
proves that Android can reopen and continue the exact cloud-hosted thread,
preserve its prior context, deny access after phone-session revocation, and
recover after fresh authorization without relinking the host.

The [isolated-work survival runbook](docs/runbooks/verify-isolated-work-survival.md)
verifies that an agent-generated diff plus successful and failed command state
survive a mobile disconnect without changing `main` or unrelated worktrees.

The [reboot-recovery runbook](docs/runbooks/verify-reboot-recovery.md) proves
that the actual Lightsail host restores T3, T3 Connect, the repository,
worktrees, thread history, settings, and provider access without repair or
re-pairing, while explicitly recording that an ordinary in-flight process is
interrupted.

The [evidence-backed pull-request runbook](docs/runbooks/deliver-evidence-backed-pr.md)
defines the protected default-branch, repository-scoped cloud credential,
branch publication, exact-diff verification, secret scanning, T3 linking, and
mandatory human-review workflow for a real pull request.

The [human merge-boundary runbook](docs/runbooks/verify-human-merge-boundary.md)
verifies that Rivet stops at an open pull request, cannot update the protected
default branch directly, and cannot merge or deploy after a disconnect or T3
service restart.

The [backup-restoration runbook](docs/runbooks/restore-workspace-backup.md)
defines the durable-state inventory, daily seven-point snapshot policy,
least-privilege restore cutover, clean replacement verification, mobile-access
gate, cost boundary, rollback limitation, and tagged cleanup procedure.

Implementation issues must still resolve these choices with security and test
evidence:

- the T3 Code update and rollback policy; and
- the health-monitoring and notification path.

Changing an accepted decision requires a superseding ADR. The remaining
choices must not silently weaken the accepted cost, access, automation, or
human-approval boundaries.

## Relationship to T3 Code

Rivet is an independent project built around T3 Code's documented remote-host
capabilities. T3 Code remains the user interface and coding-agent control
plane. Rivet focuses on the cloud environment required to keep that control
plane available when a personal laptop is not.

## License

License terms have not yet been selected.
