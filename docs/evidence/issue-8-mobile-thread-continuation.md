# Issue #8 mobile thread-continuation verification

Verification date: 2026-10-13

This record contains only redacted results. It excludes the unique marker,
context phrase, host, environment, project, thread, turn, session, and account
identifiers; prompts and responses; repository contents; authorization data;
and credentials.

## Verified scenario

- Issues #4, #6, and #7 were complete and registered as native blockers.
- A trusted desktop client created one read-only existing-checkout thread in
  the cloud **Rivet** project.
- The thread used managed Codex in supervised mode and contained one unique
  non-secret marker plus a separate non-secret context phrase.
- A protected baseline was stored on the cloud host before disconnecting the
  original client.
- Android used mobile data to reopen the existing thread rather than creating
  a new task.
- Its prior history, workspace, branch, and current-checkout state were
  visible.
- A phone follow-up recovered the earlier context without restating it or
  searching the repository.
- Backgrounding and reopening Android preserved the thread and response.

The cloud checkout intentionally remained on the same existing branch used at
baseline. This issue verifies continuity of the selected execution context; it
does not update or rebase that checkout.

## Protected baseline

The baseline was captured at `2026-10-13T15:21:48Z`. Exact identities and
message content remained only in a cloud-host file owned by `rivet` with mode
`0600`. Its redacted output recorded:

```json
{
  "uniqueThread": true,
  "markerRecorded": true,
  "contextRecorded": true,
  "identityRecorded": true,
  "projectIdentityRecorded": true,
  "latestTurnRecorded": true,
  "historyDigestRecorded": true,
  "messageCount": 3,
  "userMessageCount": 1,
  "assistantMessageCount": 2,
  "hasWorktree": false,
  "runtimeMode": "approval-required",
  "runtimeStatus": "running",
  "provider": "codex",
  "repositoryClean": true
}
```

## Stored-thread comparison

After the mobile follow-up and app reopen, the protected comparator passed
every enforced invariant:

```json
{
  "baselineCapturedAtUtc": "2026-10-13T15:21:48Z",
  "afterCapturedAtUtc": "2026-10-13T15:44:58Z",
  "inputsMatchBaseline": true,
  "sameThread": true,
  "sameProject": true,
  "sameWorkspace": true,
  "historyPreserved": true,
  "latestTurnAdvanced": true,
  "contextDependentResponseRecorded": true,
  "supervisedMode": true,
  "sameRepository": true,
  "repositoryClean": true,
  "messages": {
    "before": 3,
    "after": 6,
    "userDelta": 1,
    "assistantDelta": 2
  },
  "hasWorktree": false,
  "runtimeMode": "approval-required",
  "runtimeStatus": "running",
  "provider": "codex"
}
```

The comparator required the original ordered three-message history to retain
the same digest. It also required the same exact thread and project identities,
workspace path, branch, null worktree, repository revision, and clean-tree
state. The advanced latest turn, increased message counts, and later assistant
response containing the remembered context jointly distinguish continuation
from merely reopening a static transcript.

## Manual mobile and authorization verification

| Invariant | Result |
| --- | --- |
| Original client disconnected | The desktop client was fully quit before Android continued the thread; the cloud service remained running. |
| Mobile route | Android Wi-Fi was disabled and the official T3 client used mobile data. |
| Thread selection | Android reopened the existing marked thread; it did not create a new task. |
| Prior state | Earlier history, repository, branch, current-checkout state, and pending context were present. |
| Context continuation | The phone supplied one context-dependent follow-up and received the correct remembered value in the same thread. |
| App reopen | Backgrounding and reopening Android preserved the same thread and response without an error. |
| Phone revocation | The Android account session was revoked from another trusted client. Android was signed out and denied both environment and thread access. |
| Reauthorization | Android signed in again, selected the existing environment, and recovered the same thread and history without relinking the host. |

Server-session revocation was not used as the lost-phone proof. Prior verified
behavior showed that an account-authorized client can replace a revoked server
credential automatically. Revoking the Android account session produced the
required access denial.

## Conclusion

Android continued the original cloud-hosted thread without recreating it,
copying its context, or changing its workspace. Stored state proved that the
baseline history remained intact and the context-dependent response was added
to the same thread. Revocation removed subsequent phone access, while a fresh
phone authorization restored the original environment and thread without host
relinking.

This verification does not claim host reboot recovery, preservation of an
in-flight command during disconnection, source modification, pull-request
creation from Android, multiple-user isolation, or deployment.
