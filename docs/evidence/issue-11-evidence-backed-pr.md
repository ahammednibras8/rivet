# Issue #11 evidence-backed pull-request verification

Verification date: 2026-10-14

Pull request: [#24](https://github.com/ahammednibras8/rivet/pull/24)

This record contains only redacted results. It excludes token values,
authorization links, authentication callbacks, private host addresses, SSH
material, prompts, private logs, and unrelated repository content.

## Verified scenario

- Issues #6 and #9 were complete and registered as native blockers.
- The cloud checkout began clean on reviewed `main` commit `622eeae`.
- The cloud host created and initially published
  `feature/11-evidence-backed-pr` at that exact commit.
- GitHub `main` was protected before expanding cloud write access. Pull
  requests are required for administrators, conversation resolution is
  required, and force-push and deletion are disabled.
- A trusted operator opened PR #24 from the cloud-published issue branch to
  `main` using the non-closing relationship `Related: #11`.
- T3 Code registered the same GitHub repository and PR number.
- The PR remained open, non-draft, and without auto-merge for human review.

## Genuine failure and correction

The first cloud push used the read-only token established by Issue #6 and
failed as designed:

```text
remote: Permission to ahammednibras8/rivet.git denied to ahammednibras8.
fatal: unable to access the credential-free HTTPS origin: HTTP 403
```

The correction did not grant broad repository administration. The token was
renamed `rivet-cloud-aws`, remained restricted to only
`ahammednibras8/rivet`, and changed only **Contents** to read and write. Pull
requests and every other configurable permission remained disabled. The
retry pushed the isolated feature branch successfully from the cloud host.

This `403` is retained as genuine failing evidence; it is not described as a
network failure or replaced with a fabricated passing result.

## Branch and default-branch controls

The initial remote branch and verified default branch matched before the
change:

```text
feature/11-evidence-backed-pr = 622eeae4e22ed6441507e0d58685382f672f9009
origin/main                    = 622eeae4e22ed6441507e0d58685382f672f9009
```

The effective `main` protection reported:

```json
{
  "requiredPullRequestApprovals": 0,
  "enforceAdmins": true,
  "conversationResolution": true,
  "forcePushesAllowed": false,
  "deletionsAllowed": false
}
```

Zero platform approvals permits a solo maintainer to complete an explicitly
reviewed PR; it does not remove the pull-request requirement or Rivet's human
review gate. No direct `main` push was attempted.

## Automated verification

Before the PR opened, the complete repository suite passed:

```text
Evidence-backed PR verification is read-only and enforces the human gate.
Repository history, worktree, and prohibited filenames are clean.
Cloud foundation static verification passed.
```

Both Gitleaks passes reported no leaks. The suite also completed OpenTofu
formatting, validation, and tests; Ansible policy tests; ShellCheck; all prior
acceptance-policy checks; Git history scanning; worktree scanning; and diff
hygiene.

The initial live PR comparison returned:

```json
{
  "number": 24,
  "state": "OPEN",
  "isDraft": false,
  "base": "main",
  "head": "feature/11-evidence-backed-pr",
  "repository": "ahammednibras8/rivet",
  "autoMergeConfigured": false,
  "relationshipRecorded": true,
  "requiredSectionsRecorded": true,
  "changedFileCount": 5,
  "commitCount": 1
}
```

The verifier also compared GitHub's file and commit lists byte-for-byte with
the local remote-tracking references and scanned the PR body with Gitleaks.
After this evidence and its documentation policy were added, the final
comparison reported:

```json
{
  "number": 24,
  "state": "OPEN",
  "base": "main",
  "head": "feature/11-evidence-backed-pr",
  "autoMergeConfigured": false,
  "relationshipRecorded": true,
  "requiredSectionsRecorded": true,
  "changedFileCount": 7,
  "commitCount": 3
}
```

The final repository history and worktree scans also reported no leaks. The
cloud checkout and remote branch resolved to the same final commit, and T3
Code listed the same open PR #24 against `main`.

## Human gate

PR #24 intentionally remains open. Rivet has not approved, auto-merged,
merged, deployed, or automatically closed Issue #11. A human must inspect the
base and head branches, commit set, changed files, risks, actual verification
results, and this redacted record before any later merge decision.

This verification does not claim deployment, release automation,
multi-repository access, autonomous review, or autonomous merge.
