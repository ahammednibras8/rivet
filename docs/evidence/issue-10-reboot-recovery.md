# Issue #10 reboot-recovery verification

Verification date: 2026-10-14

This record contains only redacted results. It excludes the marker, context
word, host, environment, project, thread, turn, account, and process
identifiers; prompts and responses; repository contents; IP addresses;
authorization data; and credential fingerprints.

## Verified scenario

- Issues #3, #4, and #6 were complete and registered as native blockers.
- The actual Lightsail host held a clean checkout on the dedicated Issue #10
  verification branch.
- One approval-required managed-Codex thread recorded a unique non-secret
  marker and context word before reboot.
- A protected baseline captured host, service, environment, thread,
  repository, branch, worktree, settings, provider, and credential-store
  fingerprints.
- A harmless ten-minute process was running as `rivet` when the host received
  `systemctl reboot`.
- The phone reopened the existing environment and exact marked thread without
  SSH repair or T3 Connect re-pairing, then received the correct remembered
  context word.
- The protected post-reboot verifier compared the recovered host directly
  against the baseline.

## Protected baseline

The baseline was captured at `2026-10-14T04:15:45Z`. It recorded an active,
enabled T3 service owned by `rivet`, an available linked environment, one
clean worktree, a clean Issue #10 checkout, the approved Codex provider, and
protected persistent-configuration fingerprints.

T3 initially stored the new thread with the stale cached label
`verification/9-agent-disconnection`, while Git correctly reported
`verification/10-reboot-recovery`. The mismatch was preserved rather than
rewritten or hidden.

## Automated recovery comparison

The final protected comparison passed every enforced invariant:

```json
{
  "baselineCapturedAtUtc": "2026-10-14T04:15:45Z",
  "afterCapturedAtUtc": "2026-10-14T10:49:28Z",
  "sameHost": true,
  "rebootOccurred": true,
  "serviceRecovered": true,
  "serviceProcessRecreated": true,
  "restartLoopFree": true,
  "currentBootServiceErrors": 0,
  "sameEnvironment": true,
  "environmentReady": true,
  "sameThread": true,
  "threadBranchReconciled": true,
  "historyPreserved": true,
  "contextResponseRecorded": true,
  "providerRuntimeRecovered": true,
  "repositoryPreserved": true,
  "settingsPreserved": true,
  "providerConfigurationPreserved": true,
  "credentialsAvailable": true,
  "credentialRotationObserved": true,
  "inFlightProcessInterrupted": true,
  "recoverySeconds": {
    "hostSeconds": 11,
    "serviceSeconds": 19,
    "mobileThreadSeconds": 529
  }
}
```

The unchanged machine fingerprint plus changed kernel boot fingerprint and
later boot epoch prove an actual reboot rather than a service-only restart.
T3 became active under the non-root `rivet` account 19 seconds after the
recorded reboot request. The current-boot service journal had no error-level
entries and systemd reported no restart loop.

The complete Ansible playbook then converged against the rebooted host without
repair or configuration drift:

```text
rivet-workspace : ok=51 changed=0 unreachable=0 failed=0 skipped=2 rescued=0 ignored=0
```

## Persistent state and authentication

The repository revision, actual Issue #10 branch, local branch-reference
digest, registered worktree set, and clean status matched the baseline. The
same thread and project identities retained the complete baseline history and
recorded the phone's context-dependent response.

After restart, T3 reconciled its stale cached thread branch label to the actual
Issue #10 Git branch without changing the thread identity. Provider secret
bytes also changed during normal authorization rotation. The verifier did not
mistake mutable token bytes for identity: it required protected secret-file
permissions plus successful GitHub authentication, linked T3 Connect status,
the same Codex configuration, and a completed authenticated Codex response.

## Explicit limitation

The ten-minute process did not create its completion marker after reboot.
Ordinary in-flight terminal or agent processes are therefore not claimed to
survive a host reboot. Durable repository, service, environment, thread,
settings, provider, and credential state recovered; transient process
execution did not.

This verification does not claim backup restoration, instance replacement,
regional failover, high availability, or survival of every in-flight process.
