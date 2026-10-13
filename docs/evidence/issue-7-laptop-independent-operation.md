# Issue #7 laptop-independent operation verification

Verification date: 2026-10-13

This record contains only redacted results. It excludes host, environment,
project, thread, turn, process, session, relay, and account identifiers; IP
addresses; prompts and responses; repository contents; authorization data;
and credentials.

## Verified scenario

- Issues #3, #4, and #6 were complete and registered as native blockers.
- A dedicated existing-checkout thread used managed Codex in supervised mode.
- A protected baseline was recorded on the cloud host.
- The laptop was fully powered off for the complete action interval.
- Android Wi-Fi was disabled and the official T3 client used mobile data.
- The same cloud thread completed a read-only authenticated T3 action.
- Mobile reconnection worked normally without manual host repair.
- The laptop was powered on only after the mobile turn completed.

The mobile response did not report the requested established-SSH-session
count. This record therefore makes no claim that the observed count was zero.

## Before state

The redacted baseline reported:

```json
{
  "hostIdentityRecorded": true,
  "bootIdentityRecorded": true,
  "serviceActive": true,
  "serviceEnabled": true,
  "serviceProcessRecorded": true,
  "environmentIdentityRecorded": true,
  "t3ConnectAuthenticated": true,
  "t3ConnectLinked": true,
  "relayClientStatus": "available",
  "threadIdentityRecorded": true,
  "runtimeMode": "approval-required",
  "provider": "codex",
  "repositoryClean": true,
  "processCommands": ["cloudflared", "codex", "node-MainThread"]
}
```

Exact identities and process relationships remained only in a cloud-host file
owned by `rivet` with mode `0600`.

## Automated verification

`tests/verify-cloud-foundation.sh` passed with OpenTofu validation and tests,
Ansible syntax and policy checks, ShellCheck, documentation assertions,
repository diff checks, and history/worktree secret scanning. The system
baseline now provisions `sqlite3`, which the protected comparator uses to read
only the minimum T3 projection fields required for identity comparison.

Live Ansible check mode confirmed that the committed host policy already
matched the running workspace:

```text
ok=36 changed=0 unreachable=0 failed=0 skipped=17 rescued=0 ignored=0
```

## After comparison

The protected before/after comparison covered 421.62 seconds of increasing
host uptime and passed every enforced invariant:

```json
{
  "sameHost": true,
  "sameBoot": true,
  "sameServiceProcess": true,
  "serviceActiveAndEnabled": true,
  "sameEnvironment": true,
  "environmentReady": true,
  "sameThread": true,
  "authenticatedTurnRecorded": true,
  "supervisedMode": true,
  "sameRepository": true,
  "repositoryClean": true,
  "processCommands": ["cloudflared", "codex", "node-MainThread"]
}
```

The comparator required the same machine, boot, systemd service process,
service-start identity, T3 environment, project, thread, repository path,
branch, and revision. It also required a changed latest-turn fingerprint and a
later thread timestamp for the managed Codex provider.

## Laptop-independence conclusion

The laptop was physically powered off while Android connected over mobile
data and completed the new authenticated cloud turn. The unchanged cloud boot,
service process, environment, thread, repository, and cloud-owned process set
show that execution remained on the Lightsail host throughout the interval.

The observed `cloudflared` process was the approved outbound T3 Connect relay
client running as the cloud `rivet` account. No laptop process, laptop tunnel,
laptop relay, remote desktop, wake-up, relinking, or manual repair participated
in the successful action.

This verification does not claim host reboot recovery, mobile-network failure
recovery, source modification, pull-request creation from mobile, or
application deployment.
