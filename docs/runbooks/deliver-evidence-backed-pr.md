# Deliver an evidence-backed pull request

This runbook proves that the cloud workspace can push an isolated issue branch
and present its exact change through a reviewable GitHub pull request. It keeps
branch publication separate from pull-request administration so the cloud
credential receives only the repository-content permission it needs.

This procedure does not authorize merge, deployment, release automation,
additional repositories, or direct writes to `main`.

## Security boundaries

- Protect `main` before granting branch-write access. Require pull requests
  for administrators, require conversation resolution, and disable force-push
  and branch deletion.
- Use one fine-grained token restricted to `ahammednibras8/rivet` with
  **Contents: Read and write**. Leave Pull requests and every other
  configurable permission at **No access**.
- Keep the token only in `/home/rivet/.config/gh/hosts.yml`, owned by `rivet`
  with mode `0600`; never read, print, hash, copy, or publish it.
- Push only an issue-specific branch from the clean cloud checkout.
- Open and administer the pull request from a trusted operator identity. The
  cloud token does not need pull-request write access.
- Publish no authorization URL, callback, token, private log, prompt, private
  host address, or unrelated file.
- Use `Related: #11`; do not use an automatic-closing keyword.
- Leave the pull request open with auto-merge disabled until a human reviews
  it.

## Prerequisites

Issues #6 and #9 must be closed and registered as native blockers. Confirm the
cloud checkout is clean, `main` equals `origin/main`, and the repository's
default branch is `main`.

Confirm branch protection through GitHub's API before changing the token. The
effective policy must require pull requests for administrators and reject
force-pushes and deletion. A solo repository can require the pull-request path
without requiring another GitHub account's approval; the explicit human gate
in the PR remains mandatory.

## Expand the cloud credential minimally

Rename the existing repository-scoped token to `rivet-cloud-aws` and change
only **Contents** from read-only to read and write. Keep the resource owner and
single selected repository unchanged. Do not grant Pull requests,
Administration, Actions, Workflows, or organization access.

Retry the issue-branch push from the cloud host. Preserve the original HTTP
`403` as the genuine failing check that demonstrated the previous read-only
boundary. A successful retry is the correction; do not disguise the failure
as a transient network error.

## Prepare and push the isolated change

Create `feature/11-evidence-backed-pr` from the verified `main` commit on the
cloud host. Review the exact status, diff, commit set, and filenames before
pushing. The push must target the feature branch explicitly, never `main`.

Before opening the pull request, run:

```bash
tests/verify-cloud-foundation.sh
```

Require every repository check and both Gitleaks scans to pass. Retain only
redacted command results suitable for the PR body.

## Open the pull request

Target `main` from `feature/11-evidence-backed-pr`. The body must contain:

- `Related: #11`;
- declared scope and explicit exclusions;
- a focused change summary;
- security and operational risks;
- the exact changed-file list;
- every exact verification command with its observed result;
- the initial `403` failure and the least-privilege correction;
- a link to redacted repository evidence; and
- unchecked human-review and merge gates.

Do not enable auto-merge. Link the resulting GitHub URL to the originating T3
thread and verify that GitHub and T3 show the same repository and PR number.

## Verify the published PR

Fetch the latest remote references, then run:

```bash
tests/verify-evidence-backed-pr.sh <pull-request-number>
```

The verifier is read-only. It requires an open, non-draft PR with no auto-merge,
the expected repository/base/head identity, non-closing issue relationship,
all evidence sections, the documented `403`, an exact match between GitHub's
changed files and commits and the pushed branch, no unrelated filenames, and
a clean Gitleaks scan of the PR body.

Run `tests/repository-secrets.sh` again after finalizing the evidence document
and PR body.

## Human gate

Stop while the pull request is open. A human must inspect its base and head,
commits, changed files, evidence, and secret-scan claims. Rivet must not
approve, auto-merge, merge, or deploy it. Record requested corrections in the
same PR and rerun the verifier after every body or branch update.

## Interpret failures

| Failure | Meaning | Response |
| --- | --- | --- |
| Branch push returns `403` | Cloud token is still read-only | Confirm the single-repository selection and change only Contents to read/write. |
| Direct `main` push is accepted | Default-branch protection is ineffective | Stop, restore protection, and do not open the PR. |
| PR files or commits differ from the remote branch | Published review surface is not the intended change | Stop and inspect refs; do not rewrite evidence to match an unexplained diff. |
| Gitleaks reports a finding | Branch or PR text may expose a secret | Remove and rotate the material before republishing. |
| Auto-merge is configured | Human merge control is bypassed | Disable auto-merge before claiming completion. |
