# Deploy without the operator Mac

This runbook applies reviewed Rivet host and AWS changes from the cloud
workspace through an already-authorized T3 client. It preserves explicit human
plan and apply gates. No automatic apply occurs after a merge.

The commands run only from an exact `main` commit copied into a root-owned
release. Do not bypass the commands by running privileged Ansible from a
development checkout.

## One-time bootstrap from the current control node

The first installation is the last convergence that requires the existing
operator Mac. Complete it only after the implementation pull request is merged
to `main`:

```bash
git switch main
git pull --ff-only origin main

export RIVET_WORKSPACE_IP=100.110.244.80
export RIVET_WORKSPACE_PUBLIC_IP=13.207.157.224
export RIVET_OPERATOR_SSH_PRIVATE_KEY="$HOME/.ssh/rivet_operator_rsa"
export RIVET_OPERATOR_SSH_PUBLIC_KEY="$(<"${RIVET_OPERATOR_SSH_PRIVATE_KEY}.pub")"

ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --ssh-common-args \
    "-o HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP -o StrictHostKeyChecking=yes" \
  --diff \
  ansible/site.yml
```

Run the same playbook again without `--diff`. Require `changed=0`,
`unreachable=0`, and `failed=0`.

Before considering the Mac removable, store the operator private key in an
approved encrypted password manager or hardware-encrypted offline backup,
enroll a second trusted device in the same tailnet, and test strict-host-key
SSH from that device. Never paste the private key into T3, chat, a shell
command, GitHub, or repository files.

## Plan a host deployment from T3

After a human merges a reviewed Rivet pull request, open a terminal in the
cloud environment and run:

```bash
sudo /usr/local/bin/rivet-deploy-plan
```

The command fails closed unless all of the following are true:

- the approved repository path and GitHub origin match;
- the Git remote and GitHub API identify the same `main` commit;
- the complete repository verification suite passes;
- a clean root-owned snapshot exists for that commit; and
- Ansible check mode succeeds.

Review the complete check-mode diff. A plan reporting changes is expected when
the merged commit changes host configuration. Do not apply an unexplained
change.

## Apply the reviewed host deployment

If the plan is correct, run:

```bash
sudo /usr/local/bin/rivet-deploy-apply
```

The command rejects the apply if `main` changed after planning. After the real
convergence it runs Ansible again and refuses success unless the second recap
is unchanged and failure-free. The accepted commit is recorded in
`/var/lib/rivet/deployment/deployed-commit`; the second-convergence log is
root-owned under `/var/log/rivet/`.

If a T3 package or service change restarts the current session, reconnect from
the client and inspect the deployment marker and log. Do not start a second
apply while the first command may still be active; the deployment lock rejects
concurrent runs.

## Start a temporary AWS session from T3

Run this only in a private T3 terminal:

```bash
rivet-aws-session login
```

AWS prints a private browser authorization URL and later requests the returned
authorization code. Complete the flow on any trusted browser-enabled device.
Do not paste the authorization URL or code into chat, a T3 prompt, evidence,
logs, or shell history.

The command accepts only the `rivet-developer` identity and verifies that it
can assume `rivet-operator`. AWS documents that this login uses temporary
credentials, refreshes them during the console session, supports headless
cross-device authorization with `--remote`, and lasts no longer than the
configured session duration (up to 12 hours).

Check the session at any time without printing credentials:

```bash
rivet-aws-session verify
```

## Plan and apply AWS infrastructure

The infrastructure command uses the host-verified deployed release, protected
S3 state, and existing least-privilege role:

```bash
rivet-infrastructure plan
```

Inspect the entire printed plan. To inspect the unchanged saved plan again:

```bash
rivet-infrastructure show
```

Apply only after human review:

```bash
rivet-infrastructure apply
```

Apply consumes that exact binary plan. It then runs a fresh detailed-exit-code
plan and accepts only exit code `0`, meaning no remaining drift. Destruction
continues to require the separate destruction runbook and credentials.

Remove the temporary browser session when the operation is complete:

```bash
rivet-aws-session logout
```

## Recovery and rollback

| Failure | Required response |
| --- | --- |
| Git and GitHub API disagree | Stop. Verify the configured origin and GitHub status; do not bypass the comparison. |
| `main` changes after host planning | Run `rivet-deploy-plan` again and review the new diff. |
| Static verification fails | Correct the failure through a reviewed pull request. Never edit the root-owned release. |
| First Ansible convergence fails | Preserve the output, repair through a reviewed change, and plan again. The previous deployed marker remains authoritative. |
| Second convergence reports a change | Treat the deployment as non-idempotent and failed even if services appear healthy. |
| AWS login expires | Run `rivet-aws-session login` again privately; never add a permanent key. |
| OpenTofu plan changes unexpectedly | Do not apply. Reconcile the commit, state, and real AWS resources first. |
| A deployed change must be reversed | Revert it through a reviewed pull request, merge the revert, and repeat host plan/apply. |
| The Mac is lost | Use an already-paired T3 client for normal deployment and the encrypted operator-key backup plus a trusted Tailscale device for SSH recovery. Revoke the lost Mac in Tailscale and other account sessions. |

This procedure removes the Mac from routine deployment execution. It does not
make GitHub, T3 Connect, Tailscale, AWS authentication, protected state, or the
off-device SSH recovery key optional.
