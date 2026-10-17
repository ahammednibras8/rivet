# Provision the Rivet cloud foundation

This runbook provisions the AWS resources and Ubuntu baseline tracked by
Issue #3. Run it from the repository root on a trusted control node. It does
not install T3 Code, configure GitHub or agent credentials, create backups, or
destroy resources.

Provisioning creates paid AWS resources. A human must review every plan and
explicitly approve each apply. Never run these commands from automation.

## Required access and tools

Use a short-lived AWS session for an assumed IAM role that is authorized to
manage the in-scope Lightsail resources, the Rivet state bucket, and the
account budget. IAM users, the root user, and long-lived access keys are
rejected by the bootstrap scripts.

The supported control-node toolchain is:

- OpenTofu 1.13.1;
- AWS CLI v2;
- Python 3 with `venv` support;
- `jq`, ShellCheck, Gitleaks, Git, OpenSSH, `curl`, and the Tailscale client;
- Ansible Core 2.21.3; and
- `community.general` 13.4.0.

Create an isolated Python environment and install the pinned Ansible
dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install --requirement ansible/requirements.txt
ansible-galaxy collection install --requirements-file ansible/requirements.yml
```

Verify every required executable before using AWS:

```bash
tofu version
aws --version
jq --version
shellcheck --version
gitleaks version
ansible --version
ansible-galaxy collection list community.general
```

Stop unless OpenTofu reports `1.13.1`, the AWS CLI reports major version 2,
Ansible Core reports `2.21.3`, and `community.general` reports `13.4.0`.

## Start a temporary AWS session

Authenticate using the account's approved identity-provider or role workflow.
For the Rivet AWS Login profile backed by existing console access, use:

```bash
export AWS_PROFILE="rivet-developer"
aws login --profile "$AWS_PROFILE"
aws sts get-caller-identity --region ap-south-1
```

AWS Login credentials must be exported through `credential_process` before
OpenTofu's AWS SDK can consume them. Configure the SDK bridge and make the
operator role source that bridge:

```bash
aws configure set credential_process \
  'aws configure export-credentials --profile rivet-developer' \
  --profile rivet-developer-sdk
aws configure set region ap-south-1 --profile rivet-developer-sdk
aws configure set source_profile rivet-developer-sdk --profile rivet-operator
```

Verify both ends of the chain:

```bash
aws sts get-caller-identity --profile rivet-developer-sdk
aws sts get-caller-identity --profile rivet-operator
```

The first ARN must identify the `rivet-developer` IAM user. The second must
identify the `rivet-operator` assumed role. Use `rivet-operator` for all
OpenTofu commands.

```bash
export AWS_PROFILE="rivet-operator"
```

For an AWS IAM Identity Center profile, use:

```bash
export AWS_PROFILE="YOUR_APPROVED_PROFILE"
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity --region ap-south-1
```

The operator profile's returned ARN must contain `:assumed-role/`. An AWS Login
profile can issue temporary credentials while still identifying its principal
as an IAM user; that is not sufficient for infrastructure operations. Do not
continue with a root or IAM-user ARN. The bootstrap scripts repeat this check
and stop on failure.

## Inspect the scoped AWS resources

Never use the AWS root identity for routine resource inspection. The
`rivet-operator` role can list the account's bucket names and access only the
Rivet state objects authorized by its state policy. After switching to
`rivet-operator`, the S3 console can display that bucket.

The Lightsail console is not a supported operator interface. AWS documents
that the console expects unrestricted `lightsail:*` permission and does not
function reliably with a narrower policy. Rivet does not grant destructive
Lightsail access merely to satisfy that console. Inspect the workspace through
the scoped CLI instead:

```bash
AWS_PROFILE=rivet-operator aws lightsail get-instances \
  --region ap-south-1 \
  --query 'instances[].{Name:name,State:state.name,Image:blueprintId,Plan:bundleId}' \
  --output table
```

The result must contain only the expected `rivet-workspace` instance. Use
OpenTofu for plans and changes; reserve the root bootstrap identity for the
documented IAM bootstrap procedure.

## Prepare runtime inputs

Use an existing RSA SSH key dedicated to Rivet, or create one outside the
repository:

```bash
ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/rivet_operator_rsa" -C rivet-operator
chmod 600 "$HOME/.ssh/rivet_operator_rsa"
```

Set the runtime values in the current shell. The private key itself is never
passed to OpenTofu, Ansible, or Git.

```bash
export RIVET_OPERATOR_SSH_PRIVATE_KEY="$HOME/.ssh/rivet_operator_rsa"
export RIVET_OPERATOR_SSH_PUBLIC_KEY="$(<"${RIVET_OPERATOR_SSH_PRIVATE_KEY}.pub")"
export RIVET_BOOTSTRAP_IPV4_CIDR="$(curl --fail --silent --show-error https://checkip.amazonaws.com | tr -d '[:space:]')/32"
printf 'Budget notification email: '
IFS= read -r RIVET_BUDGET_NOTIFICATION_EMAIL

export TF_VAR_operator_ssh_public_key="$RIVET_OPERATOR_SSH_PUBLIC_KEY"
export TF_VAR_bootstrap_ipv4_cidr="$RIVET_BOOTSTRAP_IPV4_CIDR"
export TF_VAR_budget_notification_email="$RIVET_BUDGET_NOTIFICATION_EMAIL"
unset RIVET_BUDGET_NOTIFICATION_EMAIL
```

Confirm that the bootstrap CIDR is the control node's current public IPv4
address with a `/32` suffix. It is temporary: it permits only the initial SSH
bootstrap and is replaced with the reserved, unroutable `192.0.2.1/32`
sentinel after Tailscale access succeeds. Routine administration never depends
on the control node's rotating public address.

Do not place these values in a committed `.tfvars` file. The budget email and
all identifiers in later command output must be redacted before publishing
verification evidence.

## Bootstrap the protected state backend

Preview the deterministic bucket target. This command is read-only:

```bash
infra/bootstrap/state-backend.sh plan
```

Review the operator-role ARN, region, and bucket name in the output. If all
three are correct, run the apply command and type the exact bucket name when
prompted:

```bash
infra/bootstrap/state-backend.sh apply
```

This is the first human approval gate. The script creates or converges only
the account-regional state bucket, then verifies ownership, region, encryption,
versioning, public-access blocking, lifecycle retention, tags, TLS enforcement,
and its role-scoped policy.

Re-run the read-only verification and initialize OpenTofu:

```bash
infra/bootstrap/state-backend.sh verify
infra/bootstrap/init-tofu-backend.sh
```

If initialization reports local state, stop. Review and migrate that state;
never delete it merely to make initialization pass.

## Run static verification

Run the complete local gate before planning any paid resource:

```bash
tests/verify-cloud-foundation.sh
```

It must finish with `Cloud foundation static verification passed.` The gate
formats and validates both OpenTofu configurations, runs their tests, checks
all shell and Ansible policies, and scans Git history and the worktree for
secrets and prohibited files.

## Create and review a saved plan

Create a saved plan from the exact commit being reviewed:

```bash
git status --short
git rev-parse HEAD
tofu -chdir=infra/tofu plan -input=false -out=tfplan
tofu -chdir=infra/tofu show -no-color tfplan
```

The working tree must contain no unexpected file. The plan must contain only:

- one Lightsail key pair named `rivet-operator`;
- one Ubuntu 24.04 x86-64 `medium_3_1` instance named `rivet-workspace` in
  `ap-south-1a`;
- one attached static IPv4 address named `rivet-workspace-ip`;
- one Lightsail firewall policy replacing AWS defaults with TCP port 22 only
  from `RIVET_BOOTSTRAP_IPV4_CIDR`, with no IPv6, HTTP, HTTPS, or T3 listener;
- one account-wide USD 30 monthly budget with the accepted notifications; and
- the tags `ManagedBy=OpenTofu`, `Project=Rivet`, and `Workspace=primary`.

The saved `tfplan` file is ignored by Git but may contain private identifiers.
Do not commit or publish it. Delete it later using the operating system's
recoverable trash facility.

## Apply the reviewed plan

Stop here until a human has inspected the complete saved-plan output and
confirmed that it contains only the actions above. Then apply that exact saved
plan; do not create a new implicit plan:

```bash
tofu -chdir=infra/tofu apply -input=false tfplan
```

This is the second human approval gate and begins paid AWS usage.

Export the resulting connection values without copying them into a file:

```bash
export RIVET_WORKSPACE_IP="$(tofu -chdir=infra/tofu output -raw workspace_ipv4_address)"
test "$(tofu -chdir=infra/tofu output -raw workspace_instance_name)" = rivet-workspace
test "$(tofu -chdir=infra/tofu output -raw workspace_ssh_user)" = rivet-admin
```

## Verify AWS resource state

Verify the backend again, then inspect the instance, firewall, static address,
and budget through read-only AWS APIs:

```bash
infra/bootstrap/state-backend.sh verify

aws lightsail get-instance \
  --region ap-south-1 \
  --instance-name rivet-workspace \
  --query 'instance.{state:state.name,zone:location.availabilityZone,blueprint:blueprintId,bundle:bundleId,hardware:hardware,staticIp:isStaticIp,ipType:ipAddressType,tags:tags}'

aws lightsail get-instance-port-states \
  --region ap-south-1 \
  --instance-name rivet-workspace

aws lightsail get-static-ip \
  --region ap-south-1 \
  --static-ip-name rivet-workspace-ip \
  --query 'staticIp.{attachedTo:attachedTo,isAttached:isAttached,ipAddress:ipAddress}'

aws budgets describe-budget \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget-name rivet-monthly-cost

aws budgets describe-notifications-for-budget \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget-name rivet-monthly-cost

tofu -chdir=infra/tofu state list
```

Confirm the values match the reviewed plan and that the only Lightsail
firewall entry is TCP port 22 from `RIVET_BOOTSTRAP_IPV4_CIDR`. AWS documents
public SSH and HTTP as defaults for a new Ubuntu Lightsail instance, so their
absence must be verified rather than inferred from omitted configuration.

## Trust the SSH host key

Obtain the ED25519 fingerprint witnessed by the authenticated Lightsail API,
then compare it with the key presented over the network. Filter
`ssh-keyscan` output because it can emit banner lines before the key:

```bash
expected_host_fingerprint="$(
  aws lightsail get-instance-access-details \
    --region ap-south-1 \
    --instance-name rivet-workspace \
    --protocol ssh \
    --query "accessDetails.hostKeys[?algorithm=='ssh-ed25519'].fingerprintSHA256 | [0]" \
    --output text
)"

host_key_line="$(
  ssh-keyscan -T 10 -t ed25519 "$RIVET_WORKSPACE_IP" 2>/dev/null |
    awk 'NF == 3 && $2 == "ssh-ed25519" { print; exit }'
)"
observed_host_fingerprint="$(
  printf '%s\n' "$host_key_line" | ssh-keygen -E sha256 -lf - | awk '{print $2}'
)"

printf 'AWS-witnessed: %s\nNetwork-presented: %s\n' \
  "$expected_host_fingerprint" \
  "$observed_host_fingerprint"
test -n "$expected_host_fingerprint"
test -n "$observed_host_fingerprint"
test "$expected_host_fingerprint" = "$observed_host_fingerprint"
```

Do not continue if the comparison fails or either value is empty. If the
Lightsail API has not populated `hostKeys`, stop and explicitly approve a
trust-on-first-use bootstrap only while the replacement host contains no
credentials or organization data. Require three successful scans with one
unique ED25519 fingerprint, pin that key, and compare it with the host key
after the first strict connection.

After either approved verification path, replace the obsolete key for the
reprovisioned static IP and add the verified key to the control node:

```bash
install -d -m 700 "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
ssh-keygen -R "$RIVET_WORKSPACE_IP" -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1 || true
printf '%s\n' "$host_key_line" >>"$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/known_hosts"
```

## Install Tailscale without closing bootstrap access

First confirm the cloud-init bridge completed over the temporary, scoped
public SSH route:

```bash
ssh \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  -o StrictHostKeyChecking=yes \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  'cloud-init status --wait --long'
```

Preview the Ansible convergence. Check mode skips the enrollment assertion but
must still show no unsafe firewall policy:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --check \
  --diff \
  ansible/site.yml
```

After human review, perform the real convergence:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --diff \
  ansible/site.yml
```

On a new host, this first real run installs and starts the pinned Tailscale
client, then intentionally stops at `Require private administrative
connectivity`. The host firewall role must not run. Any earlier failure is not
an accepted enrollment checkpoint and must be diagnosed before continuing.

## Enroll the private administrative route

From the still-authorized bootstrap SSH connection, start interactive
Tailscale enrollment without enabling Tailscale SSH or DNS management:

```bash
ssh \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  'sudo tailscale up --hostname=rivet-workspace --accept-dns=false'
```

Open the one-time URL locally, authenticate to the approved tailnet, and never
publish that URL. In the Tailscale Machines console, find `rivet-workspace`
and disable key expiry for that server only. Tailscale documents key-expiry
disablement as appropriate for trusted servers that would otherwise require
interactive reauthentication.

Confirm the control node is signed into the same tailnet, then verify a direct
or relayed WireGuard path:

```bash
tailscale ping rivet-workspace
export RIVET_WORKSPACE_TAILSCALE_IP="$(
  tailscale status --json |
    jq -r '.Peer | to_entries[]
      | select(.value.HostName == "rivet-workspace" and .value.Online == true)
      | .value.TailscaleIPs[]
      | select(test("^[0-9]+\\."))' |
    head -n 1
)"
test -n "$RIVET_WORKSPACE_TAILSCALE_IP"
```

Preserve the AWS-witnessed host-key identity while connecting to the private
address:

```bash
export RIVET_WORKSPACE_PUBLIC_IP="$RIVET_WORKSPACE_IP"
ssh \
  -o "HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP" \
  -o StrictHostKeyChecking=yes \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_TAILSCALE_IP}" \
  'sudo -n true'
```

Do not continue unless this private SSH command succeeds.

## Converge the private-only Ubuntu baseline

Point the Ansible inventory at the verified Tailscale address and preserve the
same host-key alias:

```bash
export RIVET_WORKSPACE_IP="$RIVET_WORKSPACE_TAILSCALE_IP"
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --ssh-common-args \
    "-o HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP -o StrictHostKeyChecking=yes" \
  --diff \
  ansible/site.yml
```

This run must pass the enrollment guard before UFW allows SSH on `tailscale0`,
removes unrestricted host-level SSH, and enables its deny-by-default inbound
policy.

Run the same command again without `--diff`. The second play recap must report
`changed=0`, `unreachable=0`, and `failed=0`:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --ssh-common-args \
    "-o HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP -o StrictHostKeyChecking=yes" \
  ansible/site.yml
```

## Lock the Lightsail edge to the fail-closed sentinel

Remove the temporary bootstrap override and create a new saved plan:

```bash
unset TF_VAR_bootstrap_ipv4_cidr RIVET_BOOTSTRAP_IPV4_CIDR
tofu -chdir=infra/tofu plan \
  -input=false \
  -out=tfplan-sentinel-firewall
tofu -chdir=infra/tofu show -no-color tfplan-sentinel-firewall
```

The only action must replace the public-port policy's source with
`192.0.2.1/32`; the instance and static address must be unchanged. After human
review, apply that exact plan:

```bash
tofu -chdir=infra/tofu apply -input=false tfplan-sentinel-firewall
```

Use `aws lightsail get-instance-port-states` to confirm there is exactly one
TCP/22 rule, its IPv4 source is `192.0.2.1/32`, and it has no IPv6 CIDR or
Lightsail alias. Confirm public TCP/22 is unreachable and private SSH still
succeeds before continuing.

## Verify no infrastructure drift

Run a fresh plan without saving it and preserve OpenTofu's detailed exit code:

```bash
set +e
tofu -chdir=infra/tofu plan -input=false -detailed-exitcode
drift_exit_code=$?
set -e
test "$drift_exit_code" -eq 0
```

Exit code `0` means no drift. Exit code `2` means OpenTofu found changes; do
not apply them until their cause is understood and a new saved plan receives
human approval. Any other nonzero value is an execution failure.

## Record redacted evidence

Attach a concise summary to the implementation pull request containing:

- the reviewed Git commit and OpenTofu plan resource counts;
- successful backend verification;
- the instance's region, image, bundle, disk, and running state;
- the sentinel-only Lightsail rule and private-only UFW rule shapes, with
  addresses redacted;
- successful private SSH and failed public TCP/22 probes;
- confirmation that all three budget notifications exist;
- the first Ansible recap and the second run's `changed=0` recap;
- the no-drift plan's exit code `0`; and
- the paid-resource inventory and expected monthly base cost.

Never publish account IDs, ARNs, email addresses, public or private IP
addresses, SSH keys, state, saved plans, environment values, or unredacted
logs.

## Recover an interrupted run

Do not destroy or recreate resources to recover from an interruption. Restore
the temporary AWS session and runtime environment variables, then run:

```bash
infra/bootstrap/state-backend.sh verify
infra/bootstrap/init-tofu-backend.sh
tests/verify-cloud-foundation.sh
tofu -chdir=infra/tofu plan -input=false
```

If OpenTofu reports no unintended change, restore the Tailscale client session,
re-establish the verified SSH host key, and rerun Ansible over the private
address. Do not widen the sentinel firewall rule as a routine recovery step.
Both the backend bootstrap and Ansible baseline are idempotent. Resource
destruction requires a separate reviewed procedure and explicit approval; it
is intentionally absent from this runbook.

## Authoritative references

- [ADR-0001: AWS Lightsail cloud foundation](../adr/0001-phase-1-cloud-foundation.md)
- [ADR-0004: OpenTofu and Ansible automation](../adr/0004-use-opentofu-and-ansible-for-phase-1-automation.md)
- [ADR-0005: Tailscale private administration](../adr/0005-use-tailscale-for-private-administration.md)
- [AWS Lightsail default firewall rules](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-firewall-and-port-mappings-in-amazon-lightsail.html#default-firewall-rules)
- [AWS Lightsail SSH key and connection behavior](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-ssh-in-amazon-lightsail.html)
- [AWS Lightsail least-privilege and console behavior](https://docs.aws.amazon.com/lightsail/latest/userguide/security_iam_id-based-policy-examples.html)
- [AWS CLI `get-instance-access-details`](https://docs.aws.amazon.com/cli/latest/reference/lightsail/get-instance-access-details.html)
- [AWS CLI Login temporary credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [AWS CLI role profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html)
- [OpenTofu plan command](https://opentofu.org/docs/cli/commands/plan/)
- [Ansible check and diff mode](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_checkmode.html)
- [Tailscale key expiry](https://tailscale.com/docs/features/access-control/key-expiry)
