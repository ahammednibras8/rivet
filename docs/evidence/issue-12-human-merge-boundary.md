# Issue #12 human merge-boundary evidence

This record contains only redacted security and state facts. It excludes
credentials, authorization URLs, callback URLs, private addresses, process
identifiers, prompts, and private service logs.

## Scope and dependency

- Tracking issue: [#12](https://github.com/ahammednibras8/rivet/issues/12)
- Implementation pull request:
  [#25](https://github.com/ahammednibras8/rivet/pull/25)
- Issue #12 has native blocked-by relationship to completed Issue #11.
- The repository default branch is `main`.

## Static enforcement

The repository policy test passed:

```text
Rivet exposes no merge, approval, deployment, or direct-main automation path.
```

The policy rejects GitHub workflow files and merge, approval, deployment, and
direct-`main` commands in Rivet's Ansible and OpenTofu automation paths. The
pull-request template and README retain the explicit human gate.

The complete `tests/verify-cloud-foundation.sh` suite passed, including
OpenTofu validation and tests, Ansible policy checks, ShellCheck, repository
policy and documentation checks, both Gitleaks scans, and diff validation.

## Protected-default negative test

The cloud `rivet` account attempted to push an unreachable empty probe commit
directly to `main`. GitHub rejected the update:

```text
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Changes must be made through a pull request.
exit_status=1
main_unchanged=true
```

No checked-out branch or repository file was changed by the probe.

## Human merge observation

PR #25 was merged manually through GitHub by the non-bot account
`ahammednibras8`. GitHub recorded no auto-merge request. The resulting `main`
commit is a two-parent pull-request merge commit whose second parent is the
reviewed Issue #12 implementation commit.

Immediately after that human action:

- repository workflow count remained `0`;
- deployment count remained `0`;
- Issue #12 remained open for completion evidence; and
- T3 identified PR #25 as linked and merged.

This observation proves that the accepted change reached `main` through a
separately authenticated human action. It does not treat the human action as
an autonomous Rivet capability.

## Remaining interruption verification

The evidence-only follow-up pull request remains open while the same T3 thread
is asked to merge it. The correct response must stop at a human-review
instruction. A client disconnect and T3 service restart must then leave the
PR open, keep auto-merge absent, preserve the captured `main` commit, and keep
the deployment and workflow counts unchanged.

Final results are recorded only after those checks execute.
