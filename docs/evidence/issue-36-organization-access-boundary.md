# Issue #36 organization access-boundary evidence

Verification date: 2026-10-18

This public record is intentionally redacted. It excludes the organization
and repository identity, immutable repository ID, approval record, source,
checkout and branch names, credentials, host addresses, API bodies, GitHub
remote output, and protected fingerprints.

## Scope and corrected acceptance boundary

- Tracking issue: [#36](https://github.com/ahammednibras8/rivet/issues/36)
- Dependency Issue #35 completed guarded onboarding before these tests.
- The organization repository exposes no ruleset or legacy default-branch
  protection, and Rivet was not authorized to change company-owned settings.
- Contents write and Pull requests write also authorize GitHub merge and review
  endpoints. The issue was corrected to prohibit unsafe state-changing denial
  tests and to record default-branch, merge, and approval capability as
  residual risk.
- T3 organization work remains subject to `approval-required` supervision and
  human review. This evidence does not claim a hard server-side human-merge
  boundary.

## Authentication and baseline

The first fetch exposed a rebuilt-host configuration gap: GitHub CLI was
authenticated, but plain Git had not been configured to call
`gh auth git-credential`. The operator restored that credential helper without
copying the token or embedding it in the remote. The onboarding runbook now
records the durable step.

The corrected baseline then passed:

```json
{
  "approvedRepositoryVerified": true,
  "fetchSucceeded": true,
  "repositoryIdentityRecorded": true,
  "defaultBranchIdentityRecorded": true,
  "defaultHeadRecorded": true,
  "defaultHeadMatchesGitHub": true,
  "checkoutClean": true,
  "pullAllowed": true,
  "issueBranchPushExpected": true,
  "accountRoleSufficient": true
}
```

GitHub reported the individual account's repository role separately from the
fine-grained token permissions. The test no longer misrepresents that account
role as proof of token-level Administration access.

## Disposable branch lifecycle

The verifier created a same-tree commit without modifying or checking out
source, published one uniquely named non-default verification branch, observed
it remotely, and deleted it:

```json
{
  "approvedRepositoryVerified": true,
  "disposableBranchCreated": true,
  "disposableBranchObservedRemotely": true,
  "disposableBranchDeleted": true,
  "defaultBranchUnchanged": true,
  "checkoutClean": true
}
```

GitHub printed the private remote in its push advice despite quiet mode. The
verifier now suppresses both push output streams, and that private terminal
line is excluded from this evidence.

## Safe permission denials

After branch verification, legitimate active work existed on a non-default
branch. One real file also had mode `0666`; the operator changed only that
filesystem mode to `0644`, leaving Git content untouched. The safe-denial
verifier was corrected to preserve and compare the active branch, HEAD, and
worktree state instead of requiring a destructive return to a clean default
checkout.

The final safe, read-only probe passed:

```json
{
  "callerSuppliedRepositoryRejected": true,
  "workflowReadDenied": true,
  "actionsAdministrationReadDenied": true,
  "secretsMetadataReadDenied": true,
  "webhookAdministrationReadDenied": true,
  "deploymentReadDenied": true,
  "defaultBranchUnchanged": true,
  "checkoutStateUnchanged": true,
  "unsafeStateChangingTestsSkipped": true,
  "residualDefaultMergeApprovalRisk": true
}
```

The approved-repository metadata preflight succeeded immediately before these
denials, so the result was not caused by general authentication or network
failure. Static policy rejects mutating HTTP methods, Git pushes, merges, and
reviews from the safe-denial verifier.

## Public metadata correction

A stacked Rivet pull-request description briefly included the exact private
checkout identity while reporting an SSH verification. Its visible body was
redacted immediately. No credential or source content appeared there, but
GitHub edit history or caches may retain the earlier text; the identity is
therefore treated as disclosed rather than claimed erased.

Future public evidence must use only generic phrases such as “approved
organization workspace.” Private paths, repository names, remote URLs, and
terminal push advice are prohibited.

## Conclusion

The measured token boundary supports authenticated fetch and temporary issue-
branch publication while denying the safely probed workflow, Actions-
administration, secrets, webhook-administration, and deployment reads. The
default branch remained unchanged throughout every executed test.

Because company-owned server settings remain unchanged, this is a policy-
limited pilot rather than a technically enforced default-branch or merge
boundary. That limitation must remain visible in every later organization PR
and cannot be represented as completed hardening.
