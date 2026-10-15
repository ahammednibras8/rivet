# Issue #13 backup-restoration verification

Verification date: 2026-10-15

This record contains only redacted results. It excludes host, environment,
project, thread, turn, operation, account, and credential identifiers; IP
addresses; repository contents; prompts beyond the non-secret marker contract;
private logs; and credential fingerprints.

## Continuous backup

OpenTofu enabled the Lightsail `AutoSnapshot` add-on on `rivet-workspace` at
`20:00` UTC. AWS reported it `Enabled`, and the first scheduled recovery point
reported `Success`. Lightsail retains the latest seven daily automatic
snapshots.

The selected 80 GiB disk has a maximum USD 4.00 monthly snapshot-storage
footprint if the full disk capacity were billable at USD 0.05 per GB-month.
AWS bills actual stored data and only changed data for successive snapshots,
so this is a conservative ceiling rather than an observed charge. It fits
inside the ADR-0001 USD 6 snapshot headroom but still requires monthly review.

## Protected baseline

The T3 service was stopped but left enabled. SQLite WAL checkpoint and
integrity verification succeeded before the manual drill snapshot. The
protected baseline recorded:

```json
{
  "capturedAtUtc": "2026-10-14T17:14:43Z",
  "service": {
    "activeState": "inactive",
    "unitFileState": "enabled",
    "sqliteIntegrity": "ok"
  },
  "environmentIdentityRecorded": true,
  "markerRecorded": true,
  "contextRecorded": true,
  "thread": {
    "identityRecorded": true,
    "projectIdentityRecorded": true,
    "branch": "feature/13-backup-restoration",
    "messageCount": 3,
    "runtimeMode": "approval-required",
    "provider": "codex"
  },
  "repository": {
    "branch": "feature/13-backup-restoration",
    "worktreeCount": 2,
    "allWorktreesClean": true
  },
  "integrity": {
    "sqlite": "ok",
    "fingerprintsRecorded": true,
    "secretFileCount": 359
  }
}
```

The durable inventory covered `/home/rivet/.t3/userdata`,
`/home/rivet/.t3/worktrees`, `/home/rivet/workspaces`, and
`/home/rivet/.config/gh`. Every root was owned by `rivet:rivet`; the protected
fingerprints remained only in the mode-`0600` baseline.

## Failure path

An intentionally unavailable recovery-point name returned
`NotFoundException`. AWS reported zero restore-drill instances afterward. The
source remained running, proving the preflight fails before cutover or paid
resource creation.

## Replacement restore

A short-lived manual snapshot was tagged `ManagedBy=Rivet`, `Project=Rivet`,
and `Purpose=RestoreDrill`. AWS reported `available` with a nominal size of
80 GiB. After the source reached `stopped`, AWS created one replacement using
the accepted Ubuntu 24.04 image, `medium_3_1` bundle, IPv4 mode, operator key,
and restore tags.

The replacement's default Lightsail firewall was immediately replaced with
TCP port 22 scoped only to the unroutable `192.0.2.1/32`. Host UFW continued to
allow administrative SSH only through `tailscale0`; T3 remained bound to
`127.0.0.1:3773`.

Lightsail generated a different SSH host key for the replacement. Strict
checking rejected it as designed. The new ED25519 fingerprint was read over
the authenticated Tailscale route and pinned under a separate replacement
alias; the source key was preserved.

The complete Ansible playbook converged without repair or drift:

```text
rivet-workspace : ok=51 changed=0 unreachable=0 failed=0 skipped=2 rescued=0 ignored=0
```

The phone reopened the same marked environment and thread over mobile data
without T3 Connect re-pairing, then returned the remembered context word.

## Automated comparison

The protected verifier passed every enforced invariant:

```json
{
  "baselineCapturedAtUtc": "2026-10-14T17:14:43Z",
  "verifiedAtUtc": "2026-10-15T03:56:51Z",
  "sourceState": "stopped",
  "replacementRunning": true,
  "serviceRecovered": true,
  "environmentPreserved": true,
  "sameThread": true,
  "contextResponseRecorded": true,
  "repositoryPreserved": true,
  "worktreeCount": 2,
  "durablePermissionsPreserved": true,
  "credentialsProtected": true,
  "credentialRotationObserved": true,
  "githubConfigurationPreserved": true,
  "providerConfigurationPreserved": true,
  "loopbackOnly": true,
  "sqliteIntegrity": "ok",
  "recoverySeconds": 675
}
```

The secret store contained fewer files after startup because expired entries
were cleaned up. Every remaining secret file used mode `0600`; GitHub
authentication, T3 Connect, the restored Codex provider, and the
context-dependent agent response all succeeded. Credential usability and
protection were therefore verified without requiring mutable token bytes or
obsolete entries to remain unchanged.

OpenTofu refreshed the canonical remote state after restoration and reported:

```text
No changes. Your infrastructure matches the configuration.
detailed_exit_code=0
```

## Cost and cleanup

The replacement existed for approximately 13 minutes. At the ADR-0001 USD 24
monthly bundle price, its conservative one-hour ceiling was approximately USD
0.033. The 80 GiB manual snapshot existed for approximately 10 hours 46
minutes; its full-capacity prorated ceiling was approximately USD 0.059. The
combined drill ceiling was therefore below USD 0.10, excluding tax and any
provider rounding.

AWS reported successful deletion of the tagged replacement and tagged manual
snapshot. The original instance returned to `running`, its supervised T3
service returned active and enabled, and the phone reopened the original
thread without re-pairing. AWS then reported one successful automatic snapshot
and no remaining restore-drill instance or manual drill snapshot.

## Explicit limitations

- Automatic snapshots are tied to the source instance and are deleted with it
  unless one is first retained as a manual snapshot.
- This drill proved single-region replacement, not regional failover or high
  availability.
- The source and replacement must never run concurrently with cloned Tailscale
  and T3 Connect identities.
- Writes created only on the temporary replacement are not replicated back to
  the original disk during rollback. In a real disaster, the replacement must
  become authoritative.
- The 675-second measurement includes operator execution and phone validation;
  it is evidence from this drill, not an availability guarantee.

