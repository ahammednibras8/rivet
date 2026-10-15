# Destroy the Rivet workspace safely

This runbook removes only the OpenTofu-managed Rivet workspace after retaining
a recoverable manual snapshot. It preserves the encrypted, versioned S3 state
backend, an unrelated S3 canary, IAM identities, repositories hosted outside
AWS, and every resource outside the reviewed six-address plan.

Destruction is intentionally terminal for the active T3 environment. T3 Code
and T3 Connect remain unavailable until the retained snapshot is restored or a
new workspace is provisioned.

## Destruction boundary

The only selectable addresses are:

```text
aws_budgets_budget.workspace
aws_lightsail_instance.workspace
aws_lightsail_instance_public_ports.workspace
aws_lightsail_key_pair.operator
aws_lightsail_static_ip.workspace
aws_lightsail_static_ip_attachment.workspace
```

The workflow refuses any state containing a different address set. It also
refuses a plan unless it contains exactly six delete-only actions.

The retained boundary is:

- one manual Lightsail snapshot tagged `ManagedBy=Rivet`, `Project=Rivet`,
  `Purpose=RetainedBackup`, and `Workspace=primary`;
- `canary/issue-14.json` in the protected state bucket;
- the versioned, AES256-encrypted S3 backend and every state version;
- the `rivet-developer` IAM identity and `rivet-operator` role; and
- GitHub repositories, branches, pull requests, and issues.

The temporary IAM policy cannot delete snapshots, S3 objects or buckets, IAM
identities, or resources outside the selected workspace tags and exact static
IP and budget identities.

## Prepare and review

1. Run the static destruction-policy, canary, snapshot, plan, apply, and
   verification-policy tests.
2. Run `infra/tofu/destroy-workspace.sh preflight` with `rivet-operator`.
3. As the separately authenticated IAM bootstrap operator, run
   `infra/bootstrap/workspace-destroy-role.sh plan`, review its exact boundary,
   then run `apply`. Type the requested
   `AUTHORIZE rivet-workspace DESTROY POLICY` confirmation.
4. Run `infra/tofu/destroy-workspace.sh prepare`. This creates and verifies the
   encrypted canary, gracefully stops the instance, creates the retained
   snapshot, restarts the instance, and waits for the snapshot to become
   `available`. Protected local records remain under ignored `temp/issue-14/`
   with mode `0600` inside a mode-`0700` directory.
5. Run `infra/tofu/destroy-workspace.sh plan`. The command creates a temporary
   ignored override for only the instance and static-IP `prevent_destroy`
   guards, saves the plan, asserts the six delete-only actions, records its
   SHA-256 digest plus state lineage and serial, and removes the override.
6. Review the addresses, actions, retained resources, plan digest, and current
   Git commit. A code or state change invalidates the plan and requires a new
   review.

Saved plans and their JSON representation can contain sensitive state values.
Never commit, publish, or paste them into an issue or pull request.

## Apply

Run `infra/tofu/destroy-workspace.sh apply` only after human plan approval. The
command revalidates the Git commit, plan and evidence digests, state lineage
and serial, canary, retained snapshot, and exact six-address action set before
displaying the final prompt.

Type the complete requested confirmation naming the instance, static IP, key
pair, and budget. The script applies only the saved plan; it never invokes
`tofu destroy`, uses `--auto-approve`, removes state manually, or calls direct
AWS deletion commands.

## Verify and revoke

Run:

```bash
AWS_PROFILE=rivet-operator tests/verify-workspace-destruction.sh
```

The verifier requires:

- an empty retained OpenTofu state with the same lineage and a newer serial;
- absence of the selected instance, static IP, key pair, and budget;
- byte-identical canary content plus unchanged version, ETag, encryption, and
  tags;
- the tagged 80 GiB retained snapshot in `available` state; and
- the state bucket still using versioning and AES256 encryption.

Finally run `infra/bootstrap/workspace-destroy-role.sh revoke` with the IAM
bootstrap profile and type the requested
`REVOKE rivet-workspace DESTROY POLICY` confirmation. Confirm the inline policy
is absent. Do not leave
destructive permission installed after verification.

## Retained cost and recovery

The retained 80 GiB snapshot has a conservative USD 4 monthly ceiling at USD
0.05 per stored GB-month. Actual Lightsail snapshot billing is based on stored
data and changed blocks. The small versioned canary and OpenTofu state objects
also continue to incur normal S3 storage charges.

Review the snapshot monthly. Deleting it is a separate destructive operation
outside this runbook and requires its own recovery decision and human
confirmation.

To recover the same T3 environment, follow the
[backup-restoration runbook](restore-workspace-backup.md) and create a
replacement from the retained snapshot. A normal OpenTofu apply creates a
fresh workspace; it does not restore T3 threads, credentials, repositories,
or the existing T3 Connect environment from the snapshot.
