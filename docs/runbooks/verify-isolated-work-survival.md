# Verify isolated work survives a mobile disconnect

This runbook proves that agent-generated repository work and command results
remain on the cloud host when the mobile client disconnects. It covers both a
successful repository check and a failing command while protecting `main` and
every unrelated worktree.

This procedure does not test host reboot recovery, pull-request creation,
multiple concurrent agents, or deployment.

## Security boundaries

- Start from the reviewed `main` commit and a clean cloud checkout.
- Use either a T3-managed worktree or an issue-specific non-`main` branch.
- Keep all mutations inside the selected Rivet checkout.
- Review the exact change and commands before using **Full access**.
- Do not commit, push, merge, clean, delete, or escalate privileges during the
  disconnect test.
- Never publish prompts, repository contents, thread or project identifiers,
  credentials, host addresses, or raw T3 state.
- Store exact verification state under the `rivet` account with mode `0600`.

## Prerequisites

Issues #6 and #8 must be complete. Confirm that the cloud checkout is clean,
`main` matches `origin/main`, T3 Connect is linked, managed Codex is available,
and Android can reopen an existing cloud thread.

The operator terminal must have `RIVET_WORKSPACE_IP`,
`RIVET_WORKSPACE_PUBLIC_IP`, `RIVET_OPERATOR_SSH_PRIVATE_KEY`, and a unique
non-secret `RIVET_ISSUE9_MARKER` exported.

## Establish isolation

Create a new T3 task for the **Rivet** cloud project. Prefer **New worktree**.
If the client records no worktree, create an issue-specific branch from the
reviewed `main` commit before changing a file. Never work directly on `main`.

In the first read-only turn, record the checkout path, branch, HEAD, status,
and `git worktree list --porcelain`. Include the unique non-secret marker so
the verifier can locate exactly one thread without publishing its identifier.

## Generate the deterministic change

Ask the configured agent to create executable fixture
`tests/fixtures/issue-9/command-state.sh` with the reviewed content committed
in this repository. Do not let the agent commit or push. Run:

```bash
bash -n tests/fixtures/issue-9/command-state.sh
shellcheck tests/fixtures/issue-9/command-state.sh
tests/fixtures/issue-9/command-state.sh success
```

The success invocation must return `0` and produce one deterministic line on
both stdout and stderr.

## Disconnect during real checks

Start the repository's real suite:

```bash
tests/verify-cloud-foundation.sh
```

After the command starts, force-close the Android client. Keep it disconnected
long enough for the host-side command to finish, then reopen the exact thread.
Confirm that the thread, working diff, command completion state, stdout, and
stderr remain visible. Do not create a replacement thread or rerun the command
before inspecting its stored result.

## Exercise the failing path

Run the fixture in failure mode as one command and disconnect while it is
active:

```bash
sleep 15; tests/fixtures/issue-9/command-state.sh failure
```

After reconnecting to the same thread, require exit status `23` plus the
expected stdout and stderr. Record a different observed failure honestly; do
not rewrite it as the planned result or silently retry it.

## Verify repository isolation

Run from the operator terminal:

```bash
tests/verify-isolated-worktree-state.sh
```

The verifier accepts either a separate T3 worktree or an issue-specific branch
and requires:

- exactly one active marked thread;
- the intended cloud project and managed Codex provider;
- a non-`main` branch based on the reviewed starting commit;
- the exact executable deterministic fixture and a dirty isolated checkout;
- unchanged local and remote `main` references; and
- no unrelated registered worktrees.

It writes exact identifiers only to
`/home/rivet/.local/state/rivet-verification/issue-9-isolated-worktree.json`
with mode `0600`. Terminal output contains only booleans, counts, runtime
policy, runtime status, and provider name.

## Interpret failures

| Failure | Meaning | Response |
| --- | --- | --- |
| Thread has neither worktree nor non-`main` branch | Work is not isolated | Stop before editing and create an issue-specific branch. |
| Fixture hash differs | Agent output is not the reviewed deterministic change | Inspect the diff and correct it before continuing. |
| `main` reference changes | The protected default branch was modified | Stop and investigate; do not force-reset or clean. |
| Unrelated worktrees exist | This run cannot prove they were untouched without a baseline | Record their state before repeating the test. |
| Reconnected thread lacks the command result | T3 did not preserve the execution record | Record the failure; do not claim disconnect survival. |
| Failing command returns an unexpected status | The command failed differently than designed | Preserve the actual status and stderr, diagnose, then rerun only if needed. |

## Cleanup after review

After the pull request receives human review, remove only the protected Issue
#9 evidence file from the cloud host. The cloud issue branch and its dirty
fixture may then be discarded explicitly; never use a broad worktree cleanup
or destructive Git reset.
