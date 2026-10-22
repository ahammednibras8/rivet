# ADR-0007: Use an Ansible-owned standalone Codex CLI with T3 Code

- Status: Accepted
- Date: 2026-10-22
- Decision owners: Project maintainers
- Review trigger: T3 compatibility-policy change, Codex credential-storage
  change, or unavailable official release artifacts
- Replaces: The managed-Codex-only provider decision recorded by Issue #6

## Context

Rivet originally used only T3 Code's managed Codex runtime and plan-sharing
credential. That kept installation and authentication inside T3, but a stale
managed access token can stop otherwise healthy long-lived threads after the
token expires. Restarting T3 can make the existing connection usable again,
but a service restart is not an acceptable credential-refresh mechanism for an
always-on workspace.

T3 Code `0.1.0` also supports an installed Codex CLI with its existing login.
Its provider documentation directs the operator to install Codex and run
`codex login` on the environment machine. Its installation documentation
requires the provider CLI to be on the server's `PATH`, or to have an explicit
binary path in provider settings. The bundled T3 compatibility policy marks
Codex `>=0.156.0` supported and recommends `>=0.159.0`.

OpenAI publishes standalone Codex binaries for Linux. The latest stable,
non-prerelease release reviewed on 2026-10-22 was `0.163.0`. Its official
Linux x86-64 musl archive is
`codex-x86_64-unknown-linux-musl.tar.gz`. The release API publishes SHA-256
`beb339e8ecd9ba057a6bb2dc81ad8ca474812edfbf0fc5056ca818797648dde4`;
an independent download produced the same digest, contained one executable,
and reported `codex-cli 0.163.0`.

## Decision

Ansible will own a standalone Codex CLI installation for the Phase 1 x86-64
host. The accepted release is:

| Field | Selection |
| --- | --- |
| Version | `0.163.0` |
| Upstream tag | `rust-v0.163.0` |
| Artifact | `codex-x86_64-unknown-linux-musl.tar.gz` |
| SHA-256 | `beb339e8ecd9ba057a6bb2dc81ad8ca474812edfbf0fc5056ca818797648dde4` |
| Versioned executable | `/opt/rivet/codex-cli/0.163.0/codex-x86_64-unknown-linux-musl` |
| Stable command | `/usr/local/bin/codex` |
| Codex home | `/home/rivet/.codex` |

The versioned installation, cached archive, executable, and stable link are
root-owned. The executable is world-readable and executable but not writable
by `rivet`. `/usr/local/bin` is explicitly present in the T3 systemd user
service's non-interactive `PATH`.

Ansible prepares only `/home/rivet/.codex`, owned by `rivet:rivet` with mode
`0700`. It does not authenticate Codex and does not create, read, copy, print,
hash, template, or mock `auth.json` or any other credential. A human performs
the later login as `rivet` using OpenAI's interactive device authorization.

The headless host will use Codex's file credential mode so authentication can
survive T3 service restarts and host reboots without depending on a desktop
keyring. The human creates a private, non-secret `config.toml` selecting
`cli_auth_credentials_store = "file"` immediately before login. Codex then
owns the credential file it creates. That file is treated as a password: it
must remain outside Git, Ansible variables, shell history, logs, screenshots,
issues, pull requests, evidence, and backups that are not explicitly approved
to contain provider credentials.

T3 will use a separate Codex provider instance configured with:

- existing-CLI mode;
- binary path `/usr/local/bin/codex`;
- `CODEX_HOME` path `/home/rivet/.codex`; and
- no shadow home.

The operator must select that instance from the thread's model picker. The
previous managed provider remains connected during cutover so rollback is a
provider-selection change rather than an authentication emergency. New
verified work uses the standalone instance; T3 must not inject or share its
managed provider token with that process.

This ADR authorizes installation and documents the later human cutover. It
does not authorize this repository change to run `codex login`, inspect any
existing authentication file, disconnect or reconfigure the active provider,
apply Ansible to the live host, or start an acceptance thread against the live
environment.

## Credential and evidence boundary

- Run login only as the non-root `rivet` account with `HOME=/home/rivet` and
  `CODEX_HOME=/home/rivet/.codex`.
- Prefer `codex login --device-auth` for the headless host.
- Never record the authorization address, one-time code, browser callback,
  account identifier, token, or credential-file contents.
- Verify authentication only through the exit status of `codex login status`;
  suppress its ordinary output in published evidence.
- Verify credential ownership and modes with metadata only. Never read, copy,
  hash, or print credential contents.
- T3 receives the home and executable paths, not copied credentials or tokens.
- Logout must use `codex logout`; do not manually edit an authentication file.

## Upgrade and rollback

Every upgrade requires another stable, non-prerelease release that is inside
the pinned T3 release's supported range. The exact artifact URL, archive
layout, upstream digest, independently computed digest, and `codex --version`
output must be reviewed before changing the pin. Floating `latest` URLs,
installer pipes, npm global state, and unverified archives are prohibited.

If the standalone provider fails during cutover, stop new work on it and
select the retained managed provider for a new supervised thread. Do not copy
credentials between the two modes. If the standalone installation is being
retired, first run `codex logout` as `rivet`, disable and remove only the
standalone T3 provider instance, and then remove the reviewed stable link,
versioned installation, and archive through the documented rollback procedure.
Existing thread history is retained.

## Acceptance gate

The decision is accepted operationally only after a human completes the
runbook and records redacted evidence that:

1. two Ansible convergences pass and the second reports `changed=0`;
2. `/usr/local/bin/codex --version` reports `codex-cli 0.163.0` as `rivet`;
3. the versioned executable and stable link are root-owned and not writable by
   `rivet`;
4. `/home/rivet/.codex` is `rivet:rivet` mode `0700`, and credential files
   have private modes without their contents being accessed;
5. `codex login status` succeeds as `rivet` with output suppressed;
6. T3 reports the standalone provider as using the installed CLI and the
   expected version;
7. a supervised thread explicitly using the standalone provider completes,
   remains usable beyond the one-hour access-token boundary, and does not fall
   back to the managed provider;
8. a T3 service restart preserves authenticated operation without a new login;
9. a host reboot preserves authenticated operation without a new login; and
10. Git history and worktree secret scans contain no credential or
    authorization material.

## Consequences

- Codex installation, version selection, integrity verification, and PATH
  availability become reproducible Ansible responsibilities.
- Codex refresh behavior belongs to the official CLI login rather than T3's
  managed-token sharing path.
- Login remains deliberately interactive and outside configuration
  management.
- A file-based credential is present on the cloud host and must be protected,
  revoked, and excluded from evidence and unapproved backups.
- T3 can roll back by selecting the retained managed provider during the
  migration window.
- Codex upgrades require explicit compatibility and checksum review.

## Alternatives considered

### Continue using only T3-managed Codex

This preserves the smallest installation surface but leaves the observed
stale managed-token failure in the runtime path. It is replaced by this
decision.

### Install Codex with the upstream installer or npm

Those are supported interactive installation methods, but they select mutable
inputs and do not fit Rivet's pinned, checksum-verified, root-owned Ansible
convention. The official release archive provides the required immutable
artifact.

### Copy an existing Codex authentication cache

OpenAI documents cache copying as a headless fallback, but Rivet can use device
authorization directly. Copying a live cache creates another credential
transfer and evidence risk, so it is prohibited for this workflow.

### Authenticate Codex automatically from Ansible

Authentication would place secrets or authorization output in an automation
path and break the human credential boundary. It is prohibited.

## References

- [OpenAI Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [OpenAI Codex authentication and credential storage](https://learn.chatgpt.com/docs/auth)
- [OpenAI Codex `rust-v0.163.0` release](https://github.com/openai/codex/releases/tag/rust-v0.163.0)
- [T3 Code 0.1.0 Codex provider](https://github.com/pingdotgg/t3code/blob/v0.1.0/docs/user/providers-codex.md)
- [T3 Code 0.1.0 provider installation](https://github.com/pingdotgg/t3code/blob/v0.1.0/docs/user/install.md#providers)
- [T3 Code 0.1.0 compatibility policy](https://github.com/pingdotgg/t3code/blob/v0.1.0/apps/server/src/provider/model-manifest.json)
