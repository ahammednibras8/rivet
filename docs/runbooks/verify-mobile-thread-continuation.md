# Verify mobile thread continuation

This runbook proves that Android can reopen and continue one existing
cloud-hosted T3 thread without copying its context, creating a duplicate
thread, or depending on the original client. It also verifies that revoking
the phone's account session prevents access and that a fresh authorization
restores the same thread without relinking the host.

This procedure does not test host reboot recovery, preservation of an
in-flight command during a disconnect, source changes, pull-request creation,
multiple users, or deployment.

## Security boundaries

- Use the official T3 clients and the existing T3 Connect environment.
- Use a unique non-secret marker and a separate non-secret context phrase.
- Keep the thread in **Supervised** mode and make the verification read-only.
- Do not copy prompts, responses, or thread contents through another service.
- Never publish the marker, context phrase, host, environment, project,
  thread, turn, session, or account identifiers.
- Do not publish repository contents, authorization material, or provider
  credentials.
- Keep exact before and after records on the cloud host under the `rivet`
  account with mode `0600`.
- Revoke the phone's account session, not the environment's server session.
- Do not deregister or relink the cloud environment during this test.

## Prerequisites

Issues #4, #6, and #7 must be complete. Confirm that:

- T3 Code is active on the cloud host;
- T3 Connect is authenticated and linked;
- the approved repository is clean;
- managed Codex is available;
- a trusted non-mobile T3 client and Android are independently authorized;
  and
- Android can reach the existing cloud environment over mobile data.

The operator terminal must have `RIVET_WORKSPACE_IP`,
`RIVET_WORKSPACE_PUBLIC_IP`, and `RIVET_OPERATOR_SSH_PRIVATE_KEY` exported as
documented in the [cloud-foundation runbook](provision-cloud-foundation.md).

## Create the marked thread

From the trusted non-mobile client, explicitly select the existing cloud
environment and **Rivet** project. Start a task using **Current checkout**,
`ChatGPT Personal`, and **Supervised** mode.

In one read-only prompt, provide a unique non-secret marker and a separate
non-secret context phrase. Ask the agent to remember both, inspect only the
repository path, branch, clean-tree state, and current-checkout state, and
make no changes. Wait for the turn to complete.

Do not reuse this marker in another thread. A marker found in multiple active
threads invalidates the test.

Set the same values in the operator terminal as
`RIVET_CONTINUITY_MARKER` and `RIVET_CONTINUITY_CONTEXT`. Keep them in the
current shell only; do not add them to a repository file, shell profile, or
published evidence. Each value must contain 12-128 letters, numbers, periods,
underscores, colons, or hyphens.

## Capture the protected baseline

Run:

```bash
tests/capture-mobile-thread-continuation-baseline.sh
```

The script finds exactly one active thread containing the verification marker
and writes
`/home/rivet/.local/state/rivet-verification/issue-8-before.json`. The protected
record contains exact cloud identities, workspace state, message counts, and a
SHA-256 digest of the ordered message history. Terminal output exposes only
booleans, counts, branch, runtime policy, and repository state.

Require a unique thread, recorded identities, recorded history digest,
`approval-required` runtime mode, managed Codex, no separate worktree, and a
clean repository.

## Continue from Android

1. Quit the original desktop client completely without stopping the cloud
   service or signing out of the cloud account.
2. Disable Android Wi-Fi and use mobile data.
3. Select the existing cloud environment and **Rivet** project.
4. Reopen the existing marked thread. Do not select **New task**.
5. Confirm its prior history, workspace, branch, and current-checkout state.
6. Ask for the earlier context phrase without repeating it and prohibit
   repository searches or modifications.
7. Confirm the response returns the correct phrase in the original thread.
8. Background the Android app for at least 30 seconds, reopen it, and confirm
   that the same thread and response remain available.
9. Reopen the trusted desktop client only after the mobile turn completes.

The test fails if the user repeats the context phrase in the follow-up,
creates another task, copies context through another service, uses a different
workspace, or repairs or relinks the environment.

## Compare the stored thread

Run:

```bash
tests/verify-mobile-thread-continuation.sh
```

The comparator creates the protected
`/home/rivet/.local/state/rivet-verification/issue-8-after.json` record and
requires:

- exactly one active thread containing the marker;
- marker and context fingerprints matching the protected baseline;
- the same thread, project, workspace, branch, and worktree state;
- the complete baseline message prefix with an identical history digest;
- a different latest turn and later message timestamp;
- increased user and assistant message counts;
- an assistant response after the baseline containing the remembered context;
- the same clean repository path, revision, and branch; and
- managed Codex in `approval-required` mode.

The verifier prints no identifiers, marker, context phrase, prompts, responses,
or repository contents.

## Verify revocation and recovery

Use a different trusted T3 client:

1. Open the T3 account profile.
2. Open **Security → Active sessions**.
3. Identify Android from its device details and recent activity.
4. Revoke only that Android account session.
5. Force-close and reopen T3 Code on Android.
6. Confirm Android is signed out and cannot access either the environment or
   the marked thread.

Do not use environment-session revocation for this gate. A still-authorized
client can automatically replace that server credential, so it does not prove
lost-phone access has been removed.

After recording denial, sign in again on Android with the approved account,
select the existing environment, and reopen the exact thread. Require its
history and context-dependent response to remain present. Do not relink the
host; the new phone authorization must reuse the existing environment link.

## Interpret failures

| Failure | Meaning | Response |
| --- | --- | --- |
| Marker matches zero or multiple threads | The target is missing or ambiguous | Create a new unique marker and repeat from a fresh baseline. |
| Thread, project, workspace, branch, or worktree differs | Android opened a different execution context | Stop and select the original thread; do not claim continuity. |
| History digest differs | Earlier messages changed or the ordered prefix was not preserved | Preserve the protected files and investigate before repeating. |
| Latest turn or message counts do not advance | The phone did not complete a new turn in the stored thread | Repeat the mobile follow-up in the existing thread. |
| Context-dependent response is absent | The response did not use the earlier thread context | Do not repeat the phrase; diagnose thread selection and repeat from a new baseline. |
| Revoked Android still has access | The wrong session was revoked or account-session invalidation failed | Keep the phone isolated and investigate the active-session list. |
| Reauthorization requires host relinking | Environment authorization was changed instead of only the phone session | Stop and investigate before changing host state. |

## Remove protected snapshots

After the pull request contains redacted evidence and receives human review,
remove only these cloud-host files:

```text
/home/rivet/.local/state/rivet-verification/issue-8-before.json
/home/rivet/.local/state/rivet-verification/issue-8-after.json
```

Do not remove their parent directory or any T3 state. Snapshot removal does
not delete the verification thread or its history.
