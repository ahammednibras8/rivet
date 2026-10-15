# Restore the Rivet workspace from backup

This runbook restores the single Phase 1 workspace into a replacement Amazon
Lightsail instance and proves that its durable T3, GitHub, repository, and
worktree state remains usable from the phone. It uses a controlled cutover:
the source instance is stopped before the replacement starts, so two machines
never use the same Tailscale or T3 Connect identity concurrently.

This is disaster recovery, not high availability. Rivet does not replicate
writes between the source and replacement disks, and recovery requires an AWS
operator terminal.

## Backup policy

OpenTofu enables the `AutoSnapshot` add-on for `rivet-workspace` at `20:00`
UTC. Lightsail creates one recovery point each day and retains the latest seven
automatic snapshots. Automatic snapshots remain coupled to the source: AWS
deletes them if that source instance is deleted. Preserve an irreplaceable
automatic recovery point as a manual snapshot before deleting a failed source.

AWS documents that Lightsail snapshots cost USD 0.05 per stored GB-month and
that successive snapshots are charged for changed data. The 80 GiB system
disk therefore has a USD 4.00 monthly upper bound if one full-capacity snapshot
were billable; actual storage should be lower and must remain inside the USD 30
budget. Review snapshot usage monthly.

Lightsail-managed block storage and disk snapshots are encrypted at rest with
AWS-managed keys. Snapshots contain the cloud-hosted source, repository data,
threads, and credentials and must therefore remain inside the Rivet AWS
account and least-privilege IAM boundary.

AWS references:

- [Manual and automatic snapshots](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-faq-snapshots.html)
- [Configure automatic snapshots](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-configuring-automatic-snapshots.html)
- [Create an instance from a snapshot](https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-how-to-create-instance-from-snapshot.html)
- [Lightsail block-storage encryption](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-faq-block-storage.html)

## Durable-state inventory

The instance snapshot captures the entire system disk. These paths are the
authoritative user-owned durable state that the restore verifier inventories:

| Path | Durable responsibility |
| --- | --- |
| `/home/rivet/.t3/userdata` | T3 database, projects, threads, settings, T3 Connect environment state, attachments, and protected provider credentials |
| `/home/rivet/.t3/worktrees` | T3-managed worktree storage |
| `/home/rivet/workspaces` | Approved repository checkouts, Git branches, and registered worktrees |
| `/home/rivet/.config/gh` | Repository-scoped GitHub CLI authorization and configuration |

The snapshot also contains `/var/lib/tailscale`, installed T3 and provider
runtimes, system packages, and host configuration. Treat Tailscale and T3
identity material as protected credentials. OpenTofu, cloud-init, and Ansible
remain the reproducible authorities for infrastructure and host configuration;
installed binaries and operating-system configuration are not substitutes for
those sources.

Do not publish the protected baseline. It contains hashes and internal
identifiers even though it contains no raw secret values.

## IAM boundary

The `rivet-operator` role can create and inspect snapshots and replacements in
`ap-south-1`. It can start or stop only instances tagged `Project=Rivet`. It
can delete only instances and manual snapshots carrying both `Project=Rivet`
and `Purpose=RestoreDrill`. The role cannot delete automatic snapshots or
export snapshots to EC2.

The root bootstrap profile is used only to converge this reviewed IAM policy.
Routine backup, restore, verification, and cleanup use `rivet-operator`.

## Prepare a recovery point

1. Create a unique non-secret marker and context word in a completed,
   approval-required Codex thread on the Issue #13 branch.
2. Maintain two clean registered worktrees: the issue checkout and one
   dedicated restore fixture.
3. Stop—but do not disable—the `t3code.service` user service.
4. Run `tests/capture-backup-restore-baseline.sh`. It checkpoints the SQLite
   WAL, requires `PRAGMA integrity_check` to return `ok`, and writes the
   protected baseline to
   `/home/rivet/.local/state/rivet-verification/issue-13-before.json` with mode
   `0600`.
5. Flush the filesystem, create a manual snapshot tagged `ManagedBy=Rivet`,
   `Project=Rivet`, and `Purpose=RestoreDrill`, wait for `available`, then
   restart T3.

The manual snapshot is a short-lived drill artifact. Automatic snapshots are
the ongoing backup mechanism.

## Fail before cutover when the recovery point is unavailable

Call `get-instance-snapshot` for the selected snapshot before stopping the
source. A missing recovery point must return `NotFoundException`, no restore
instance may exist, and the procedure must stop. Never substitute a different
snapshot silently.

## Restore into a replacement

1. Record the restore-request epoch.
2. Stop `rivet-workspace` and wait for the `stopped` state. Do not delete it.
3. Create exactly one `medium_3_1`, IPv4 replacement in `ap-south-1a` from the
   selected snapshot, using the `rivet-operator` key pair and the three restore
   tags above.
4. Immediately replace the replacement's Lightsail firewall with TCP port 22
   scoped to `192.0.2.1/32`. AWS does not copy custom source firewall rules to
   snapshot-created instances; host UFW remains the second layer.
5. Wait for the replacement to report `running` and for the restored Tailscale
   identity to become reachable. Keep the source stopped.
6. Retrieve the new SSH host-key fingerprint over the authenticated Tailscale
   route. Pin it under the replacement's public-IP alias; never disable strict
   host-key checking or overwrite the source key.
7. Reapply `ansible/site.yml` to the replacement and require
   `unreachable=0`, `failed=0`, and an explained change count.
8. From the phone, reopen the exact marked thread without re-pairing and request
   the remembered context word.
9. Run `tests/verify-backup-restoration.sh` with the replacement identity and
   restore-request epoch.

The verifier requires the source to remain stopped and checks:

- the replacement image, bundle, tags, and fail-closed Lightsail firewall;
- active, enabled, non-root T3 supervision and loopback-only port 3773;
- the same T3 Connect environment, project, thread, marker, and context;
- the exact repository revision, branches, and two clean registered worktrees;
- the four durable roots, their ownership, and their directory modes;
- SQLite integrity and mode `0600` for every provider secret file;
- working GitHub authentication and installed Codex configuration; and
- recovery duration without printing protected identifiers.

Secret files may rotate or expired entries may be garbage-collected at startup.
Do not require byte-for-byte credential equality. Require protected file modes
and successful authenticated GitHub, T3 Connect, and Codex operations.

## Reconcile configuration

Run the full Ansible playbook against the replacement. From the operator
checkout, run an OpenTofu plan against the canonical remote state and require
`No changes`. The replacement is a temporary recovery drill resource because
the AWS provider does not manage a Lightsail snapshot restoration resource in
the canonical state. OpenTofu remains authoritative for the protected source,
automatic snapshots, firewall, static IP, and budget.

Do not import the drill replacement over the protected source resource and do
not bypass `prevent_destroy`.

## Roll back and clean up

After recording evidence:

1. Stop the replacement and wait for `stopped`.
2. Delete only the replacement tagged `Purpose=RestoreDrill`.
3. Start `rivet-workspace` and wait for `running`.
4. Verify its original pinned SSH identity, T3 service, T3 Connect route, and
   phone access without re-pairing.
5. Delete only the tagged manual drill snapshot.
6. Confirm at least one successful automatic snapshot remains and OpenTofu
   still reports no drift.
7. Remove only the clean restore-fixture worktree, its local verification
   branch, and the protected Issue #13 baseline after the redacted evidence is
   reviewed and recorded.

New messages or repository writes made only on the temporary replacement are
not copied back to the original disk. During a real disaster, the replacement
becomes authoritative instead of rolling back. During a drill, keep replacement
writes disposable and record this limitation explicitly.

## Failure handling

| Failure | Response |
| --- | --- |
| Selected snapshot is missing or not `available` | Leave the source running and stop the procedure. |
| Source cannot reach `stopped` | Do not create a replacement; investigate the AWS operation. |
| Replacement firewall is broader than the sentinel `/32` | Stop the replacement and correct the Lightsail firewall before connecting. |
| Tailscale route does not return | Keep the source stopped; inspect instance console and boot state without starting both identities. |
| SSH host key differs | Verify and pin the replacement key over the authenticated private route; never turn off checking. |
| T3, repository, thread, or credential checks fail | Preserve both resources, keep only one running, and investigate before cleanup. |
| Source fails to restart after drill cleanup | Keep the replacement stopped but undeleted so the recovery point remains available. |
