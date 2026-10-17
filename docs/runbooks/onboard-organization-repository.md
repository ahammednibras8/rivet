# Onboard one organization repository

This runbook onboards exactly one repository selected by the active private
approval manifest. It does not accept a repository name, owner, URL, branch,
or alternate manifest from an agent or caller.

The exact organization, repository identity, approval record, source tree,
toolchain inventory, thread content, and command output remain private. They
must not be copied into Rivet commits, issues, pull requests, logs, or public
verification evidence.

## Preconditions

- The cloud workspace, T3 Connect, and Codex provider are operational.
- The individual organization-approved GitHub credential is installed only on
  the cloud host.
- `/home/rivet/.config/rivet/repositories.json` contains exactly one current
  approval and is `root:rivet` with mode `0640`.
- `/usr/local/bin/rivet-repository` and its validator are root-owned and not
  writable by the `rivet` service account.
- The T3 user service applies `UMask=0027` so Git metadata and agent-created
  files do not inherit group-write or world access.

## Guarded lifecycle

Run each operation as the `rivet` service account with `HOME=/home/rivet`:

```text
rivet-repository verify
rivet-repository clone
rivet-repository status
rivet-repository register
```

`verify` resolves only the manifest entry and compares its immutable GitHub ID
and approved metadata with the live repository. `clone` derives the HTTPS
target and default branch from that verified entry, uses a protected staging
directory, applies private modes, and atomically activates the checkout under
the dedicated organization workspace.

`status` rejects a missing or linked checkout, a changed remote or branch,
tracked or untracked changes, unexpected ownership, and group-writable or
world-writable real files and directories. Symlink permission placeholders are
ignored because Linux does not enforce their displayed mode bits.

`register` requires `status` to pass. It accepts one existing active T3 project
for the exact checkout, creates one through the pinned T3 CLI when absent, and
rejects duplicate active projects. It reads T3's projection database only for
idempotence; project creation remains a T3 CLI operation.

## Private toolchain discovery

Create a new thread inside the registered organization project and select
`approval-required` before sending the first prompt. The prompt must prohibit
source changes, branch creation, dependency installation, builds, tests,
secret access, and network calls.

The thread may inspect tracked configuration to identify runtimes, lockfiles,
workspace structure, required local services, and the repository's exact
lint, type-check, test, and build commands. Those exact findings remain private
documentation inside the cloud-hosted T3 thread. Public Rivet evidence
records only that discovery completed and that the repository stayed clean.

If a thread starts in another runtime mode, retain the failed attempt in the
audit narrative, confirm that it made no changes, and create a correctly
supervised thread. Do not describe the failed attempt as supervised.

## Redacted verification

Set a unique, non-secret marker that appears only in the accepted supervised
thread, then run:

```text
RIVET_ORGANIZATION_DISCOVERY_MARKER=<non-secret-marker> \
  tests/verify-organization-repository-onboarding.sh
```

The verifier derives the checkout from the private manifest, emits only booleans and counts,
and requires one active matching T3 project, one active
marked thread, the exact approved workspace and default branch, no worktree,
Codex in `approval-required` mode, a clean checkout, secure permissions, and
the service `UMask=0027`.

Stop immediately if any assertion is false. Never diagnose a failure by
printing the manifest, repository URL, source paths, messages, tokens, or T3
database rows into public evidence.
