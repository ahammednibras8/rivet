# Verify cloud-host reboot recovery

This runbook proves that the actual Lightsail host can reboot and recover the
existing T3 environment without SSH repair, T3 Connect re-pairing, or replacing
the active thread. It also records the explicit limit that an ordinary
in-flight process does not survive a host reboot.

This procedure does not test backup restoration, instance replacement,
regional failure, or high availability.

## Security boundaries

- Use a unique non-secret marker and context word; never place credentials or
  repository content in either value.
- Keep exact machine, environment, project, thread, turn, and credential
  fingerprints only under the `rivet` account with mode `0600`.
- Publish only redacted booleans, counts, branch names, and recovery durations.
- Keep T3 bound to loopback and use the already-authorized T3 Connect route.
- Do not repair SSH, relink the environment, or reauthorize the phone during
  the recovery observation.
- Never claim that an interrupted terminal or agent process survived unless
  its actual process and output prove that behavior.

## Prerequisites

Issues #3, #4, and #6 must be complete. The cloud checkout must be clean and
on an issue-specific branch. T3 Code must be an enabled non-root user service,
T3 Connect must report linked and available, and the approved Codex and GitHub
credentials must already work on the cloud host.

Export `RIVET_WORKSPACE_IP`, `RIVET_WORKSPACE_PUBLIC_IP`,
`RIVET_OPERATOR_SSH_PRIVATE_KEY`, `RIVET_REBOOT_MARKER`, and
`RIVET_REBOOT_CONTEXT` in the operator terminal.

## Establish the recovery thread

Create one T3 task in the cloud **Rivet** project using **Current checkout**,
managed Codex, and approval-required mode. Include the unique marker and ask
the agent to remember the non-secret context word. Require a completed reply
before capturing the baseline.

T3 may initially retain a cached branch label from an earlier current-checkout
thread. Git is authoritative: the capture requires the actual checkout to be
on `verification/10-reboot-recovery`. The post-reboot verifier requires T3's
thread label to reconcile to that real branch while retaining the exact thread
and project identities.

## Capture the protected baseline

Run:

```bash
tests/capture-reboot-recovery-baseline.sh
```

The capture requires a clean repository and clean registered worktrees. It
records fingerprints for the machine, boot, service, T3 Connect environment,
marked thread history, branch references, worktrees, settings, Codex
installation, GitHub configuration, and provider secret store. Raw secrets
and identifiers are not printed.

The protected baseline is
`/home/rivet/.local/state/rivet-verification/issue-10-before.json`, owned by
`rivet` with mode `0600`.

## Reboot with an in-flight process

Immediately before reboot, start one harmless ten-minute process as `rivet`.
Record its PID and the reboot-request epoch in the protected state directory,
then run `systemctl reboot` as the administrator. The operator command must
verify the process is running before requesting the reboot.

The SSH connection should close. Do not use that disconnect alone as proof of
a reboot; the post-reboot verifier requires a new kernel boot identity and a
later boot epoch on the same machine.

## Reconnect from the phone

Make the laptop unavailable and use the already-authorized phone connection.
Wait for the existing environment to return, reopen the marked thread, and ask
for the context word without restating it. Require the exact remembered word.
Do not open SSH, repair the service, re-pair T3 Connect, or create another
thread before this succeeds.

## Verify recovered state

From the operator checkout, without first changing the cloud repository, run:

```bash
tests/verify-reboot-recovery.sh
```

The verifier requires:

- the same machine with a different boot identity and reset uptime;
- a newly started, enabled T3 service owned by `rivet`, with no error-level
  current-boot journal entries or restart loop;
- the same linked T3 Connect environment in an available state;
- the same thread, project, workspace, worktree selection, and preserved
  baseline history plus the context-dependent phone response;
- the same repository revision, real branch, branch-reference digest,
  worktrees, and clean status;
- unchanged settings, Codex installation, and GitHub configuration;
- protected provider secret files plus working GitHub, T3 Connect, and Codex
  authentication after any legitimate credential rotation;
- an absent completion marker for the interrupted process; and
- non-negative host, service, and mobile-thread recovery durations derived
  from host and stored-message timestamps.

The protected result is
`/home/rivet/.local/state/rivet-verification/issue-10-after.json` with mode
`0600`.

## Interpret failures

| Failure | Meaning | Response |
| --- | --- | --- |
| Boot identity is unchanged | The host did not reboot | Stop; do not claim recovery. |
| T3 or T3 Connect is unavailable | Automatic recovery failed | Inspect current-boot service logs before changing configuration. |
| Thread identity or history differs | The phone opened different state | Select the original thread; do not substitute a new thread. |
| Repository or worktree fingerprint differs | Persistent Git state changed | Inspect the exact diff and reference change; never reset broadly. |
| Credential bytes differ but authenticated checks pass | A provider rotated mutable authorization material | Record the rotation; validate permissions and usability rather than requiring frozen token bytes. |
| In-flight completion marker is absent | The ordinary process was interrupted by reboot | Record this as unsupported in-flight survival, not data recovery. |

## Cleanup after review

After human review and merge, remove only the Issue #10 protected baseline,
result, PID, log, completion marker if present, and reboot timestamp. Do not
remove shared T3 state, credentials, repositories, branches, or worktrees.
