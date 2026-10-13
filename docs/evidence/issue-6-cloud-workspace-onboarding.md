# Issue #6 cloud workspace onboarding verification

Verification date: 2026-10-13

Implementation commit before evidence documentation: `38e8641`

This record contains only redacted results. It intentionally excludes account
identifiers beyond the public repository owner, token values, authentication
callbacks, provider credentials, T3 project and thread identifiers, prompts,
responses, host addresses, SSH material, and unrelated logs.

## Delivered scope

- Pinned and checksum-verified GitHub CLI `2.102.0` for Linux AMD64.
- Private GitHub CLI state owned by the non-root `rivet` service account.
- One fine-grained token restricted to read-only contents access for
  `ahammednibras8/rivet`.
- One cloud-owned checkout at `/home/rivet/workspaces/rivet` with a
  credential-free HTTPS origin.
- One T3 project registered against that checkout.
- T3-managed Codex `0.156.1` connected through `ChatGPT Personal`.
- One real Android-started, supervised, read-only agent thread completed on
  the cloud host.

The issue did not grant repository writes, pushes, pull-request creation,
merges, deployments, additional repositories, or additional agent providers.

## Automated verification

Focused GitHub CLI role tests verified the pinned version and checksum,
checksum-enforced download, package installation, version assertion, private
configuration directory, and site-play inclusion.

The live installed package reported:

```text
gh version 2.102.0
gh 2.102.0
SHA-256 7e54a307f90afdc59796c325ec0c49fb09e6c18537727207a8ac7513584ea5b0
```

The final live Ansible convergence was idempotent:

```text
ok=50 changed=0 unreachable=0 failed=0 skipped=2 rescued=0 ignored=0
```

Repository secret scanning passed after removing a local ignored credential
copy. The credential remains persisted only in the cloud GitHub CLI store.

## Manual verification

| Invariant | Result |
| --- | --- |
| GitHub identity | The cloud `rivet` account authenticated as the intended GitHub user. |
| Repository boundary | The approved public repository query succeeded. |
| Write denial | An intentionally incomplete contents request returned HTTP `403` with `Resource not accessible by personal access token`. |
| Git credential helper | Git delegates GitHub HTTPS credentials to `/usr/bin/gh auth git-credential`; no token appears in the remote URL. |
| Checkout | `/home/rivet/workspaces/rivet` tracks `origin/main` and was clean immediately after cloning. |
| T3 project | The existing checkout was registered as `Rivet`; no duplicate worktree was created. |
| Provider | T3 installed managed Codex `0.156.1` and displayed `ChatGPT Personal` for the cloud environment. |
| Mobile thread | Android started a real read-only thread against `Rivet`; its last turn completed. |
| Runtime policy | Thread metadata reported `approval-required`, the intended issue branch, and no separate worktree. |
| Cloud ownership | GitHub state, T3 secrets, project state, managed provider, checkout, and thread state were verified under `/home/rivet`. |

The redacted final thread inspection reported:

```text
project=Rivet
workspace=/home/rivet/workspaces/rivet
provider=codex
permissionMode=approval-required
branch=feature/6-cloud-workspace-onboarding
worktreePath=null
lastTurnState=completed
```

## Filesystem and credential controls

```text
rivet:rivet 0700 /home/rivet/.config/gh
rivet:rivet 0600 /home/rivet/.config/gh/hosts.yml
rivet:rivet 0700 /home/rivet/.t3/userdata/secrets
T3 secret file modes: 0600 only
```

- No token was committed or retained in the local repository.
- The checkout origin contains no embedded credential.
- T3 provider secret contents were never read, copied, hashed, or published.
- The first thread used supervised permissions and a read-only prompt.
- Human review remains required before every generated pull request is merged.
