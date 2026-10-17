# Issue #34 organization-access installation evidence

Verification date: 2026-10-17

This public record contains only generic verification results. It excludes the
GitHub token, organization repository name and ID, approval reference,
approval dates, repository metadata, private manifest contents, host
addresses, Tailscale identity, and organization source code.

## Scope boundary

- Tracking issue: [#34](https://github.com/ahammednibras8/rivet/issues/34)
- Dependency Issue #33 was complete before credential installation began.
- The existing private manifest contained exactly one structurally valid
  approval and used local mode `0600`.
- No repository was cloned, registered with T3, or inspected during this
  issue.
- The active credential remains the operator's individual, organization-
  approved fine-grained token; no organization-owned or shared credential was
  introduced.

## Credential installation

The clean replacement contained no previous GitHub credential. The operator
entered the approved token through a terminal prompt with echo disabled, and
the value traveled only over the existing strict-host-key SSH connection to
`gh auth login --with-token`. It was not placed in Git, a command argument,
the T3 thread, a screenshot, or the public evidence. The local shell variable
was unset and the trusted Mac clipboard was cleared immediately afterward.

GitHub authenticated the cloud host as the expected individual account. The
credential store reported:

```text
credential_directory=rivet:rivet 700
credential_file=rivet:rivet 600
```

## Private allowlist installation

The dedicated Ansible playbook validated the private source manifest locally,
copied it through a protected staging file, performed live GitHub validation
as the `rivet` service account, and activated it only after that validation
succeeded:

```text
rivet-workspace : ok=7 changed=3 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

The active boundary reported only these non-secret results:

```text
allowlist_directory=root:rivet 750
allowlist_file=root:rivet 640
Approved repositories verified.
installed_approval_count=1
repository_checkout=absent
```

The service-account permission probe then reported:

```text
service_account_read=allowed
service_account_write=denied
missing_manifest=rejected
```

The operator therefore controls changes to the active manifest, while T3 and
its agents can read the approval needed for later repository commands.

## Fail-closed verification

The focused schema, remote-metadata, Ansible installation, role, and
documentation tests passed. Their fixture matrix rejects:

- missing or malformed manifests;
- expired approvals;
- repository ID, owner, or name changes;
- default-branch or visibility changes;
- archived repositories;
- insufficient effective repository permissions; and
- duplicate repository IDs.

Live verification resolved only the exact private manifest entry and printed
no repository metadata. It did not call a repository-listing endpoint.

## Explicit limitation

This issue installs and validates the private authorization inputs. It does
not yet implement the repository lifecycle command or clone organization
source. Issue #35 must continue to require the active allowlist before it can
verify, clone, register, report, or otherwise operate on a repository.
