# Issue #9 isolated-work disconnect verification

Verification date: 2026-10-14

This record contains only redacted results. It excludes the marker, host,
project, thread, turn, and account identifiers; prompts and responses;
repository contents; IP addresses; authorization data; and credentials.

## Verified scenario

- Issues #6 and #8 were complete and registered as native blockers.
- The cloud checkout began clean on reviewed `main` commit `1a0bba0`.
- T3 recorded no managed worktree for the marked thread, so the allowed
  issue-specific branch isolation path was used instead.
- Managed Codex generated the reviewed deterministic command-state fixture on
  `verification/9-agent-disconnection` without committing or pushing it.
- The agent ran focused syntax, ShellCheck, deterministic-success, and full
  repository checks from the cloud checkout.
- Android disconnected while the host-side successful operation was active,
  then reopened the same thread with its diff and command result retained.
- A second disconnect preserved an actual failed-command result and stderr.

## Automated isolation evidence

The protected cloud verifier reported:

```json
{
  "capturedAtUtc": "2026-10-14T03:07:22Z",
  "uniqueThread": true,
  "isolationMode": "branch",
  "workspaceMatches": true,
  "separateWorktree": false,
  "issueSpecificBranch": true,
  "branchMatchesThread": true,
  "baseCommitMatches": true,
  "deterministicChangePresent": true,
  "deterministicChangeMatches": true,
  "deterministicChangeExecutable": true,
  "isolatedWorktreeDirty": true,
  "defaultBranchUntouched": true,
  "registeredWorktreeCount": 1,
  "unrelatedWorktreeCount": 0,
  "thread": {
    "identityRecorded": true,
    "projectIdentityRecorded": true,
    "latestTurnRecorded": true,
    "messageCount": 17,
    "runtimeMode": "full-access",
    "runtimeStatus": "stopped",
    "provider": "codex"
  }
}
```

The verifier matched the generated fixture byte-for-byte against the reviewed
content and confirmed it was executable. The issue branch and `main` both
pointed at the reviewed starting commit, so only the issue checkout carried the
uncommitted diff. Local and remote `main` references were unchanged. Git
reported only one registered worktree, leaving no unrelated worktree that
could have been modified.

## Disconnect observations

| Scenario | Preserved result |
| --- | --- |
| Successful operation | Reconnecting to the original thread retained the agent-generated diff and completed command result after Android was force-closed during execution. |
| Successful fixture | The deterministic success path returned `0` with its reviewed stdout and stderr lines. |
| Failed operation | Reconnecting retained exit status `127` and `/bin/bash` stderr showing that the relative fixture path was unavailable to that command invocation. Stdout was empty. |
| Corrected fixture | The same branch then contained the exact executable fixture and its focused success checks passed. |

The planned failure status was `23`; the disconnected invocation instead
returned `127`. This evidence intentionally preserves that discrepancy rather than
claiming the designed failure result. Repository automation separately
verifies that the committed fixture's intentional failure mode returns `23`
and produces deterministic stdout and stderr.

## Isolation conclusion

The cloud-hosted branch, dirty diff, thread, and command records survived the
mobile disconnect. The observed successful and failed command states remained
inspectable after reconnection. The default branch stayed at its reviewed
commit, and no unrelated worktree existed.

This verification does not claim host reboot survival, pull-request creation
from mobile, multiple concurrent agent isolation, or deployment.
