# Verify the organization access boundary

This runbook measures the effective GitHub boundary for the single repository
selected by the private approval manifest. It never accepts an organization,
repository, branch, or remote from the caller, and its public output contains
only booleans, counts, and timestamps.

Repository identity, immutable ID, approval metadata, checkout paths, branch
names, source, credentials, API responses, and GitHub remote output remain
private. Do not paste `git push` remote messages into Rivet issues, pull
requests, evidence, or chat.

## Known server-side limitation

The pilot repository has neither a ruleset nor legacy default-branch
protection. Changing organization-owned repository settings is outside
Rivet's authority. The approved token's Contents write and Pull requests write
permissions permit issue-branch publication, but GitHub also uses those
permissions for merge and review APIs.

Consequently, Rivet cannot prove that a default-branch push, merge, or review
would be rejected. Do not exercise those state-changing operations merely to
test denial. Keep organization agents in `approval-required` mode, require the
operator to inspect every publication request, and record this as residual
risk rather than claiming a hard human-merge boundary.

## Capture the private baseline

Start from the approved default branch with a clean checkout, then run:

```bash
tests/capture-organization-access-baseline.sh
```

The script performs an authenticated fetch, verifies the immutable repository
identity and approved metadata, records the remote default commit, and stores
only protected fingerprints under the service account. The public result does
not reveal the repository or default-branch name.

GitHub's repository `permissions.admin` field describes the authenticated
account's repository role; it is not the fine-grained token's Administration
permission. The baseline therefore requires sufficient pull and push access,
while later permission-category probes test token denials independently.

## Prove disposable branch publication

Run:

```bash
tests/verify-organization-branch-lifecycle.sh
```

The verifier creates an unreachable same-tree commit object without checking
out or editing source, publishes it to a unique `rivet-verification/issue-36-`
branch, observes that branch remotely, and deletes it. It then requires the
remote default commit and local checkout to remain unchanged.

All push stdout and stderr are suppressed because GitHub may print a private
repository URL even with `git push --quiet`. A failure emits only a generic
message; diagnose it through redacted comparisons.

## Probe only safe denials

Run:

```bash
tests/verify-organization-safe-denials.sh
```

The verifier first proves that caller-supplied repository input is rejected.
It then sends only authenticated `GET` requests to permission-specific
workflow, Actions-administration, secrets, webhook-administration, and
deployment endpoints. Each request must be denied.

The checkout may contain legitimate active work by this point. The verifier
therefore fingerprints the current branch, HEAD, and complete porcelain status
before the probes and requires exact equality afterward. It also requires the
approved remote, service-account ownership, secure real-entry permissions, and
the baseline default commit to remain unchanged.

The static policy test rejects POST, PUT, PATCH, DELETE, push, merge, and review
commands from this verifier. A network or authentication failure is not enough
to establish the result: the approved repository metadata preflight must
succeed before denied endpoints are evaluated.

## Interpret results

| Result | Meaning | Response |
| --- | --- | --- |
| Baseline identity or default commit differs | Approval or repository state changed | Stop and renew the private approval before continuing. |
| Disposable branch remains present | Cleanup did not complete | Remove only the exact verification branch through a supervised recovery. |
| A read-only prohibited endpoint succeeds | The token is broader than recorded | Stop organization work and reduce or revoke the credential. |
| Branch, HEAD, status, or default commit changes during safe probes | Concurrent or unexpected mutation occurred | Preserve state and investigate; do not reset or clean. |
| Group- or world-writable real entry appears | Checkout permission drift occurred | Identify the entry privately and correct only its mode without changing content. |
| Default push, merge, or approval is requested as a test | The operation could alter company state | Refuse the test and retain the documented residual risk. |

## Public evidence boundary

Publish only the redacted JSON results and the explicit limitation. If a
private identity or path is accidentally published, remove it from the visible
artifact immediately, report that edit history or caches may retain it, and
treat the identity as disclosed. Never claim that editing the visible text
guarantees historical erasure.
