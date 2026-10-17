# Issue #35 organization repository onboarding evidence

Verification date: 2026-10-18

This public record is intentionally redacted. It excludes the organization
and repository identity, immutable repository ID, approval reference, source
tree, toolchain details, exact private commands, thread messages, credentials,
host addresses, and T3 identifiers.

## Scope and authorization

- Tracking issue: [#35](https://github.com/ahammednibras8/rivet/issues/35)
- Dependency Issue #34 installed one approved credential and one private
  allowlist entry before any organization source was cloned.
- Every lifecycle operation derived its target from that installed allowlist;
  no repository-list endpoint or caller-provided repository target was used.
- Organization source remained exclusively on the cloud host and was not
  copied into public Rivet artifacts.

## Guarded checkout and registration

The root-owned `rivet-repository` command verified the live approval before
cloning. It used a protected staging directory, selected the approved default
branch, activated the checkout beneath the dedicated organization workspace,
and returned only generic success output.

Checkout verification confirmed the approved remote and branch, clean state,
service-account ownership, and protected real-file permissions. Eight symlinks
initially exposed a portability error in the permission check: Linux displays
symlinks with writable mode placeholders even though it does not enforce those
bits. The corrected check ignores symlinks while continuing to reject writable
real files and directories.

One Git metadata file was later recreated with mode `0664` during a diagnostic
outside the guarded command. No source file was affected. The T3 systemd
service now enforces `UMask=0027`; existing Git metadata was normalized once,
and the final permission verification passed.

T3 registration found one existing active project for the exact checkout and
did not create a duplicate. Automated fixtures also prove first registration,
idempotent re-registration, duplicate rejection, invalid-checkout rejection,
and generic output.

## Supervised discovery

The initial discovery attempt used the correct read-only prompt but the wrong
runtime mode. Automated verification detected that mismatch while separately
confirming a clean checkout and secure permissions. The operator removed that
failed thread and created a new thread with `approval-required` selected before
the first message.

The accepted thread inspected tracked configuration only. It documented the
real runtimes, package managers, workspace layout, service dependencies, and
exact lint, type-check, test, and build commands inside private cloud T3 state.
It did not install dependencies, execute builds or tests, access secrets, make
network requests, create a branch, or modify repository files. None of its
private findings are reproduced here.

## Redacted verification result

The final automated verification returned:

```json
{
  "repositoryVerified": true,
  "projectRegistered": true,
  "activeProjectCount": 1,
  "uniqueDiscoveryThread": true,
  "threadMatchesApprovedProject": true,
  "supervisedReadOnlyThread": true,
  "repositoryClean": true,
  "securePermissions": true,
  "serviceUmask": true
}
```

The result contains no private repository metadata, message content, or
credential material.
