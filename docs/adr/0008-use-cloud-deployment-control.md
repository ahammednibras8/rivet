# ADR-0008: Use human-triggered cloud deployment control

- Status: Accepted
- Date: 2026-10-22
- Decision owners: Project maintainers
- Amends: [ADR-0004](0004-use-opentofu-and-ansible-for-phase-1-automation.md)
- Review trigger: Multiple operators, unattended apply requirement, loss of the
  protected-default-branch boundary, or replacement of T3 Connect

## Context

ADR-0004 selected OpenTofu and Ansible, protected remote state, reviewed saved
plans, and manual apply. Its original control node remained the operator Mac.
That machine is not in the T3 runtime path, but it is still required to apply a
merged host correction or obtain the AWS session used for infrastructure work.

The Mac is therefore a recovery and deployment bottleneck. Losing it does not
immediately stop T3, but it prevents a reviewed repository correction from
taking effect and makes later failures harder to repair. ADR-0004 explicitly
requires review when manual apply becomes an availability bottleneck or a
secured remote execution service is required.

Automatically applying every merge would replace one availability problem
with a privileged CI identity and an unattended root path. Rivet needs remote
execution, not autonomous deployment.

## Decision

Rivet will keep OpenTofu and Ansible and add human-triggered remote execution
on the existing cloud workspace.

No push, merge, timer, or webhook starts an apply.

### Host configuration

The cloud host installs a pinned Ansible virtual environment and collection.
Two argument-free commands are the only new sudo permissions granted to the
`rivet` account:

- `rivet-deploy-plan`; and
- `rivet-deploy-apply`.

The privileged implementation fetches the configured default branch through
the existing repository-scoped GitHub identity. It requires the Git remote and
GitHub API to agree on the same 40-character commit identifier. It then copies
that exact commit into a root-owned snapshot. Privileged Ansible never executes
from the writable development checkout or an agent worktree.

Planning runs the complete repository gate and Ansible check mode with a diff.
Apply is allowed only while `origin/main` still equals the planned commit. It
runs the reviewed configuration, immediately converges it a second time, and
accepts the deployment only when the recap reports `changed=0`,
`unreachable=0`, and `failed=0`.

The `rivet` account receives no general-purpose sudo access. Its ability to run
the two fixed commands is safe only while GitHub protects `main`, agents cannot
merge, and humans review every merged change. A malicious merged Ansible change
is privileged code; repository review remains part of the root trust boundary.

### AWS infrastructure

The cloud host installs a checksum-pinned AWS CLI v2 release. The operator uses
AWS's cross-device `aws login --remote` flow to obtain a short-lived browser login
login for the existing `rivet-developer` IAM identity. The CLI exposes that
session through a process-credential profile, which then assumes the existing
least-privilege `rivet-operator` role.

No permanent AWS access key is copied to the host. The login cache is private
to `rivet`, expires with the console session, and is explicitly removable with
`rivet-aws-session logout`.

Infrastructure commands operate only from the root-owned release last accepted
by host convergence. `plan` saves a binary OpenTofu plan for that commit and
prints it for review. `apply` consumes that exact saved plan and requires a
clean post-apply drift check. Existing lifecycle protection and AWS role
denials continue to guard ordinary workspace destruction.

## Security and operational consequences

- T3 on any already-authorized client can initiate reviewed deployment while
  the Mac is unavailable.
- A compromise of the `rivet` account can invoke the fixed host commands, but
  cannot choose a branch, path, commit, playbook, sudo argument, or arbitrary
  root command.
- A compromise during an active AWS login can use the bounded operator role
  until the temporary session expires or is logged out.
- GitHub default-branch protection and human merge review are now part of the
  privileged host deployment boundary.
- The first installation still requires one final convergence from the old
  control node. Every later convergence can originate from the cloud host.
- This path does not replace independent SSH recovery. The operator key must be
  recoverable from encrypted off-device storage and tested from another
  Tailscale-enrolled device.

## Rejected alternatives

### Apply automatically after merge

This removes the explicit plan/apply decision and gives GitHub events a direct
root and AWS mutation path. It is not required for laptop independence.

### GitHub-hosted Actions runner

It can reach AWS with OIDC but cannot reach the private Tailscale-only SSH
service without adding another network bridge. It also creates a second
deployment system when the trusted cloud host already exists.

### Self-hosted Actions runner

A runner executing repository workflows on the workspace would turn workflow
changes into privileged host code and broaden the repository token and runner
attack surface.

### Store the Mac's AWS keys on the server

Long-lived access keys would survive unattended and contradict the existing
credential boundary. Browser-issued temporary credentials provide recovery
without creating that secret.

## Verification

The decision is accepted only while tests and a live drill prove:

1. the deployment runtime and AWS CLI match reviewed version and checksum pins;
2. sudo permits only the two argument-free host commands;
3. a branch, dirty worktree, changed upstream commit, or Git/API disagreement
   cannot be applied;
4. the release executed as root is owned by root and names the accepted main
   commit;
5. the second Ansible convergence is unchanged and successful;
6. AWS login uses the approved developer identity and assumes only
   `rivet-operator`;
7. OpenTofu apply consumes the saved plan for the active release and ends with
   no drift; and
8. logout removes the active AWS session without a permanent AWS credential.

## References

- [AWS CLI browser-based temporary login](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [AWS CLI `login` command](https://docs.aws.amazon.com/cli/latest/reference/login/)
- [ADR-0004: OpenTofu and Ansible automation](0004-use-opentofu-and-ansible-for-phase-1-automation.md)
- [ADR-0005: Tailscale private administration](0005-use-tailscale-for-private-administration.md)
