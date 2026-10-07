# Rivet

Rivet is a headless, autonomous SRE remediation daemon. It receives failure
webhooks from production and CI/CD systems, diagnoses the fault inside an
isolated Git worktree, creates and verifies a test-driven fix, and opens a pull
request for human review.

> **Project status:** Phase 1 bootstrap. The architecture below describes the
> initial implementation target; application code has not been scaffolded yet.

## How Rivet works

1. A supported service sends a failure webhook to Rivet.
2. Rivet authenticates and normalizes the event into an incident record.
3. An ephemeral worktree is created from the failing commit.
4. The remediation agent identifies the likely fault location from the stack
   trace and surrounding source code.
5. The agent writes a regression test, applies the smallest viable patch, and
   runs the repository's test suite.
6. A verified fix is pushed to an incident-specific branch and submitted as a
   pull request with diagnostic and verification details.

## Architecture

### Ingress daemon

`src/index.ts` will expose the following initial endpoints:

- `GET /health` — lightweight process health check.
- `POST /api/v1/incidents` — authenticated incident ingestion.

Incoming GitHub HMAC signatures and Sentry tokens will be verified before the
payload is accepted. Provider-specific events will be converted into a common
`IncidentRecord` containing the repository, failing commit, branch, error
message, stack trace, and source metadata.

### Ephemeral sandbox engine

`src/sandbox/` will manage detached Git worktrees beneath
`/tmp/rivet/<incident-id>`. Every remediation run will operate on the exact
failing commit and will clean up its worktree when complete. Rivet will never
apply autonomous changes directly to a repository's primary working tree.

### Diagnostic and patch agent

`src/agent/` will:

- Parse stack traces to locate relevant files and line numbers.
- Inspect narrowly scoped source context around the failure.
- Add a failing reproduction test before changing implementation code.
- Generate a minimal patch.
- Run the detected test command inside the isolated worktree.
- Reject delivery when verification fails.

### Git operations and delivery

`src/git/` will create branches named `rivet/fix-<incident-id>` and use the
GitHub API to open pull requests containing:

- A root-cause summary.
- An explanation of the defect and proposed fix.
- Details of the regression test.
- Captured verification output.

### Persistence

Supabase will store normalized incidents, remediation attempts, execution
history, verification results, and delivery status for auditability.

## Planned project structure

```text
rivet/
├── src/
│   ├── agent/
│   ├── git/
│   ├── sandbox/
│   │   └── worktree.ts
│   ├── types/
│   │   └── incident.ts
│   └── index.ts
├── tests/
├── .env.example
├── package.json
└── tsconfig.json
```

## Technology

- Node.js 22 or newer
- TypeScript with strict type checking and ES modules
- Octokit for GitHub operations
- Supabase for incident persistence and run history
- `tsx` for local TypeScript execution
- Deterministic subprocess execution via `execFile` or `spawn`

## Security and safety principles

- Authenticate every incident before performing work.
- Treat webhook data, stack traces, and repository contents as untrusted input.
- Use argument-based process APIs rather than shell interpolation.
- Restrict all mutation to disposable worktrees.
- Base remediation on an explicit commit SHA for reproducibility.
- Require a passing regression test and test suite before delivery.
- Keep credentials out of logs, patches, commits, and pull-request bodies.
- Preserve execution evidence for review and auditing.

## Phase 1 scope

The bootstrap milestone will establish:

- A strict TypeScript project configuration and initial directory structure.
- Typed incident and provider models.
- Health and incident-ingestion HTTP endpoints.
- GitHub and Sentry webhook authentication.
- Safe worktree creation and cleanup primitives.

Later phases will add autonomous diagnosis, test generation, patching,
verification, persistence, and pull-request delivery.

## License

License terms have not yet been selected.
