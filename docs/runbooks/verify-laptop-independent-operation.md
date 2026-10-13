# Verify laptop-independent operation

This runbook proves that the Rivet host, T3 Code service, managed relay,
repository, provider runtime, and thread remain usable while the developer's
laptop is fully powered off. It uses one protected before/after record on the
cloud host and one real T3 action from Android over mobile data.

This procedure does not test host reboot recovery, mobile network recovery,
source changes, pull-request creation, or deployment.

## Security boundaries

- Use the official T3 mobile app and the existing T3 Connect environment.
- Do not open public inbound ports or add another access route.
- Keep the verification thread in **Supervised** mode.
- Permit only read-only inspection commands.
- Never publish host, environment, project, thread, turn, process, session, or
  relay identifiers.
- Do not publish prompts, responses, IP addresses, repository contents,
  authorization material, or provider credentials.
- Keep the protected snapshots under the `rivet` account with mode `0600`.

The verifier stores SHA-256 fingerprints for stable identifiers. Fingerprints
allow equality checks without copying the underlying values into evidence.
Process records contain only PID relationships, Unix user, and executable
name; command arguments and environment variables are never captured.

## Prerequisites

Issues #3, #4, and #6 must be complete. Confirm that:

- the cloud workspace is running;
- T3 Code is active and enabled as the non-root `rivet` user;
- T3 Connect is authenticated and linked;
- the Rivet checkout is clean;
- managed Codex is connected; and
- Android can open the intended cloud environment.

The operator terminal must have `RIVET_WORKSPACE_IP`,
`RIVET_WORKSPACE_PUBLIC_IP`, and `RIVET_OPERATOR_SSH_PRIVATE_KEY` exported as
documented in the [cloud-foundation runbook](provision-cloud-foundation.md).

## Create the verification thread

From Android, select the cloud environment and the **Rivet** project. Start a
task using **Current checkout**, `ChatGPT Personal`, and **Supervised** mode.
Use a read-only baseline prompt and prohibit file changes, branches, commits,
and pushes. Wait for the first turn to complete.

Keep this exact thread available for the laptop-off action. Do not create a
replacement thread between the before and after captures.

## Capture the protected baseline

From the operator terminal, run:

```bash
tests/capture-laptop-independent-baseline.sh
```

The script records these values in
`/home/rivet/.local/state/rivet-verification/issue-7-before.json`:

- machine and current boot fingerprints plus uptime;
- T3 systemd user-service state, main process, and start identity;
- T3 environment fingerprint and filtered T3 Connect state;
- project, thread, latest-turn, and provider-runtime identity;
- repository path, branch, revision, and clean-tree state; and
- the `rivet`-owned T3, managed-relay, and Codex process set.

Require every printed identity check to be `true`, the service to be active
and enabled, T3 Connect to be authenticated and linked with an available relay
client, runtime mode `approval-required`, and a clean repository. The terminal
output is redacted; do not print the protected snapshot.

## Perform the laptop-off action

1. On Android, disable Wi-Fi and confirm that mobile data is active.
2. Fully shut down the laptop. Closing its lid or allowing sleep is not valid.
3. Keep the laptop off for the complete mobile verification interval.
4. Open the same cloud environment, project, and verification thread.
5. Send one read-only request for UTC time, host uptime, T3 service state,
   repository path, branch and clean-tree state, and the count of established
   SSH connections whose local port is 22.
6. Approve only the read-only command and wait for the provider turn to finish.
7. Record any connection failure or noticeable reconnection delay honestly.
8. Power the laptop on only after the T3 response completes.

The test fails if Android uses Wi-Fi, the laptop merely sleeps, a remote
desktop or SSH route is used from another device, T3 requires relinking, or an
operator repairs the host during the interval.

## Compare the cloud state

After the laptop starts, restore the operator variables and run:

```bash
tests/verify-laptop-independent-operation.sh
```

The comparator creates a second protected `0600` snapshot and requires:

- increasing host uptime with the same machine and boot fingerprints;
- the same continuously running T3 service process and start identity;
- the same T3 environment and ready T3 Connect state;
- the same project and thread with a different latest-turn fingerprint;
- managed Codex in supervised mode;
- the same clean repository path, branch, and revision; and
- cloud-owned `node-MainThread`, `cloudflared`, and `codex` processes.

The different latest-turn fingerprint, later thread update time, managed Codex
provider, and unchanged thread fingerprint jointly prove that an authenticated
action completed in the existing cloud thread. The unchanged boot and service
process identities prove that neither the host nor T3 restarted during the
interval.

The `cloudflared` process is the approved cloud-host T3 Connect relay client.
It is evidence of the intended outbound route, not a laptop relay. A laptop
that remained physically powered off cannot have supplied a process, tunnel,
relay, or wake-up path.

If the mobile response omits the requested SSH-session count, record that as
missing evidence rather than claiming it was zero. The physical power state,
mobile-data route, continuous cloud identities, new cloud turn, and cloud-only
process set remain separate evidence for laptop independence.

## Interpret failures

| Failure | Meaning | Response |
| --- | --- | --- |
| Host or boot fingerprint changed | The test crossed a different host or reboot | Stop; investigate before repeating the complete test. |
| T3 service process changed | The supervised service restarted | Record the interruption; do not claim uninterrupted operation. |
| Environment or thread changed | Android reached a different target | Select the intended cloud environment and repeat from a new baseline. |
| Latest turn did not change | No post-baseline authenticated action was recorded | Repeat the complete laptop-off action in the same thread. |
| Repository changed or became dirty | The read-only boundary was violated | Inspect and resolve the cloud checkout before repeating. |
| Relay or provider process missing | Required cloud execution path is incomplete | Diagnose the cloud service; do not add a public endpoint. |

## Remove protected snapshots

After the pull request contains redacted evidence and receives human review,
remove only these two cloud-host files:

```text
/home/rivet/.local/state/rivet-verification/issue-7-before.json
/home/rivet/.local/state/rivet-verification/issue-7-after.json
```

Do not remove the parent directory or any T3 state. Snapshot removal does not
remove the verification thread or its history.
