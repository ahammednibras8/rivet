# ADR-0004: Use OpenTofu and Ansible for Phase 1 automation

- Status: Accepted
- Date: 2026-10-07
- Decision owners: Project maintainers
- Review trigger: Second cloud provider, automated apply requirement, or tool
  support change

## Context

Rivet needs two different kinds of reproducible automation:

1. infrastructure provisioning for AWS resources such as the Lightsail
   instance, network policy, snapshots, budget controls, and addressing; and
2. host configuration for Ubuntu packages, users, security settings, T3 Code,
   and systemd services.

One tool should not blur those ownership boundaries. Infrastructure state must
survive the loss of an operator's computer, while host configuration must be
safe to run repeatedly and report drift without rebuilding the instance.

The first supported provider is AWS, but the README describes it as the Phase
1 provider rather than a permanent AWS-only product boundary. The provisioning
language should therefore permit future provider-specific implementations
without replacing the workflow or state model.

The tool behavior and service documentation in this record were checked on
2026-10-07. Exact executable and provider versions must be selected and locked
when their configuration is first added to the repository.

## Decision

Phase 1 will use this automation toolchain:

| Responsibility | Selection |
| --- | --- |
| Cloud resource provisioning | OpenTofu |
| AWS integration | Official `hashicorp/aws` provider |
| Infrastructure language | HCL |
| Infrastructure state | Private Amazon S3 backend in `ap-south-1` |
| State locking | Native S3 lockfile with `use_lockfile = true` |
| Backend bootstrap | AWS CLI v2 through a reviewed, idempotent procedure |
| First-boot bridge | Minimal cloud-init passed as Lightsail user data |
| Ubuntu configuration | Ansible Core |
| Host transport | SSH from an authorized control node |
| Apply model | Manual plan, human approval, manual apply |

OpenTofu owns AWS resources. Ansible owns operating-system state. Cloud-init
does only the minimum needed to make a fresh instance safely manageable by
Ansible; it must not become a second configuration-management system.

Phase 1 will not use Terraform CLI, Pulumi, AWS CDK, a general CloudFormation
stack, Chef, Puppet, Salt, or OpenTofu `remote-exec` provisioners. A new ADR is
required before adding another infrastructure or configuration-management
system.

## Repository contract

When implementation begins, the repository will contain:

- an OpenTofu root configuration for the Phase 1 AWS environment;
- explicit OpenTofu and AWS-provider version constraints;
- a committed OpenTofu dependency lock file with verified checksums for every
  supported operator platform;
- backend configuration that contains bucket location and state key but no
  credentials;
- a minimal cloud-init template owned by the infrastructure configuration;
- a pinned Ansible Core dependency and any explicitly approved collections;
- an inventory structure containing host identifiers but no credentials;
- Ansible roles or playbooks for each durable host responsibility; and
- documented `fmt`, validation, check, plan, apply, and recovery commands.

Generated OpenTofu state, saved plans, crash logs, Ansible retry files, local
inventories containing private addresses, downloaded providers, and all secret
variable files must be ignored by Git.

The dependency lock file is not generated output to ignore. It must be
committed and reviewed because OpenTofu uses it to select provider versions and
verify provider package checksums.

## Infrastructure state backend

ADR-0001 required a separate accepted decision before creating an
object-storage bucket. This ADR authorizes exactly one general-purpose S3
bucket for OpenTofu administrative state. It does not authorize application
storage, repository backups, build artifacts, or public file hosting.

The state bucket must:

- reside in `ap-south-1`;
- have all four S3 Block Public Access controls enabled;
- reject non-TLS requests through bucket policy;
- use S3-managed server-side encryption, SSE-S3;
- have versioning enabled for state recovery;
- use an explicit lifecycle rule to limit old state and lockfile versions;
- deny deletion to ordinary plan and apply credentials;
- grant state-object access only to the infrastructure operator role;
- record the state under a stable, project-specific object key; and
- participate in the AWS budget and resource inventory from ADR-0001.

The backend will use OpenTofu's native S3 conditional lockfile. No DynamoDB
table is authorized. State locking must not be disabled to bypass a failed or
contended operation. Force-unlock is permitted only after proving that no
other writer is active and recording the lock identifier.

S3 storage and requests are metered and count toward the USD 30 monthly Phase
1 service-cost limit. The state is expected to be small, but this decision does
not pretend the bucket is free. Its actual storage, version count, and request
cost must be checked with the other monthly AWS costs.

### Backend bootstrap

The S3 backend cannot create the bucket in which its initial state must already
be stored. A small, reviewed AWS CLI v2 procedure will therefore create and
verify the administrative bucket before the first `tofu init`.

That procedure must be idempotent: it must distinguish an existing correctly
owned bucket from a naming collision or unsafe configuration. It must verify
region, ownership, public-access blocks, encryption, versioning, lifecycle,
and policy after creation. It must not print credentials or state contents.

The state bucket remains outside the ordinary Rivet OpenTofu root module so
`tofu destroy` cannot remove its own backend. Deleting that bucket is a
separate destructive operation requiring its exact name, an empty-state
verification, a recoverable export, and explicit human confirmation.

## Credential boundary

OpenTofu and the backend bootstrap will run from a trusted control node using
short-lived AWS credentials. Long-lived AWS access keys must not appear in
HCL, backend configuration, shell history, `.env` files, repository secrets,
OpenTofu state, Ansible variables, or the Rivet host.

The Lightsail host does not need infrastructure-administration credentials to
run T3 Code. A compromise of the development host must not automatically grant
permission to create, replace, or destroy AWS resources or read OpenTofu state.

The control node is an administrative dependency for provisioning and
reconfiguration, not a runtime dependency for T3 Code. Once configured, the
always-on host and T3 Connect route continue operating while that control node
is offline.

## OpenTofu operating rules

- Pin the OpenTofu CLI and every provider to reviewed versions.
- Commit the provider lock file and checksums for supported operating systems
  and architectures.
- Format and validate configuration before planning.
- Refresh real resource state as part of each plan.
- Save a reviewed plan before an apply that changes infrastructure.
- Require a human to inspect the resource actions and approve the apply.
- Never apply automatically because a pull request was opened or merged.
- Never apply an unreviewed plan generated from a different commit.
- Do not place secrets in resource arguments when a service-side reference or
  post-provision authentication flow is available.
- Use lifecycle protection for resources whose accidental replacement would
  destroy state, but do not treat lifecycle rules as a substitute for backups.
- Import manually created in-scope AWS resources before managing them; do not
  create duplicate resources to avoid import work.

The plan output is operational evidence and may contain resource identifiers
or sensitive values. It may be summarized in a pull request, but the binary
plan file and unredacted output must not be committed or published.

## Cloud-init boundary

Cloud-init is limited to the first-boot bridge required before Ansible can take
ownership. Its responsibilities may include creating the intended
administrative account, installing the minimum Python and transport
prerequisites, and applying the initial SSH baseline.

Cloud-init must not:

- install or authenticate coding-agent providers;
- contain GitHub, T3 Connect, AWS, or model-provider credentials;
- clone private repositories using an embedded credential;
- contain the complete long-term host configuration;
- perform an unpinned network download and execute it as root; or
- hide failures behind an unconditional successful exit.

A first-boot failure must remain observable through cloud-init status and logs.
Ansible must be able to converge the host after the bootstrap without deleting
and recreating the instance.

## Ansible operating rules

Ansible Core will run agentlessly over SSH from an authorized control node.
The managed Ubuntu host needs Python and an SSH account but does not run a
permanent Ansible server or agent.

Ansible will own durable host configuration including:

- operating-system packages and security updates;
- administrative and T3 service users;
- SSH daemon hardening and host firewall rules;
- directories, ownership, and bounded log configuration;
- T3 Code installation and selected-version updates;
- T3's non-root systemd user service and lingering state;
- health-check and backup prerequisites; and
- verification that prohibited public listeners are absent.

Playbooks must use idempotent modules instead of shell commands where an
appropriate module exists. Each change must pass syntax checking and the
supported check-mode path before a real apply. Running the playbook twice
against an unchanged host must produce no second-run changes except tasks whose
non-idempotence is explicitly justified and tested.

SSH must use keys and host-key verification. Port 22 must not remain open to
all IPv4 or IPv6 addresses merely to simplify Ansible. The exact
administrative-access and recovery policy requires its own verified
implementation before provisioning.

## Acceptance gate

The automation decision passes only when the implemented toolchain can prove:

1. A fresh operator environment installs the pinned OpenTofu and Ansible
   versions from documented inputs.
2. The backend bootstrap creates or verifies only the named S3 state bucket.
3. The bucket passes encryption, versioning, public-access, TLS, lifecycle, and
   IAM checks.
4. Two concurrent state writers cannot both acquire the S3 lock.
5. `tofu fmt -check` and `tofu validate` succeed.
6. A reviewed plan creates only resources authorized by accepted ADRs.
7. Applying the plan provisions the selected Lightsail host without storing
   AWS credentials on it.
8. Cloud-init completes its limited bootstrap and exposes a useful failure if
   deliberately given an invalid prerequisite.
9. Ansible check mode reports the expected first convergence.
10. The real Ansible run configures the host and starts T3 Code as the non-root
    service user.
11. A second Ansible run against the unchanged host reports no unintended
    changes.
12. Manual host drift is detected and corrected by the next Ansible run.
13. An unapproved public T3, HTTP, HTTPS, or unrestricted SSH listener is
    rejected by verification.
14. Loss of the original control node does not lose infrastructure state; a
    newly authorized control node can initialize from S3 and produce a no-op
    plan.
15. A previous state object version can be identified and recovered through a
    documented, non-destructive exercise.

Any test that could create, replace, or delete a paid AWS resource must show
the plan and name the exact resource before human approval.

## Consequences

### Positive

- Infrastructure and operating-system configuration have clear owners.
- AWS resources can be reviewed as a plan before mutation.
- Remote, versioned state does not depend on one laptop disk.
- Native S3 locking prevents ordinary concurrent state writes without a
  DynamoDB table.
- Ansible can reconcile drift and be tested for idempotence.
- The provider-oriented provisioning model can add another cloud through a
  separate implementation later.
- No permanent configuration-management agent or AWS administration
  credential is required on the Rivet host.

### Negative

- The toolchain adds OpenTofu, the AWS provider, AWS CLI, cloud-init, Ansible,
  SSH, and an S3 administrative resource.
- The S3 backend introduces a small but non-zero cost and an additional
  recovery dependency.
- A separate bootstrap path is required for the state bucket.
- Operators must understand which tool owns a setting before changing it.
- Ansible needs a controlled administrative SSH path distinct from T3 Connect.
- Provider and Ansible upgrades require deliberate lock-file and compatibility
  review.

## Alternatives considered

### AWS CloudFormation and Ansible

CloudFormation supports Lightsail resource types, AWS-managed stack state, and
drift detection for supported resources. It would avoid the OpenTofu backend
bootstrap and is a credible AWS-only solution.

It was not selected because it would make AWS's template and stack model the
top-level Rivet provisioning interface. The product explicitly selects AWS for
Phase 1 rather than committing to AWS permanently. OpenTofu retains a
consistent workflow while allowing later provider-specific modules.

### Terraform and Ansible

Terraform has the mature AWS provider used by this decision, and ordinary
internal use remains available. Its core CLI releases moved to the Business
Source License, while OpenTofu is stewarded as the open-source continuation
under the Linux Foundation. OpenTofu is selected to avoid making Rivet's
future distribution model depend on Terraform's product-license boundary.

The AWS provider remains separately licensed and must still be version-pinned
and reviewed.

### OpenTofu with shell provisioning

Shell scripts are useful for small orchestration wrappers but provide weak
resource modeling, check mode, and idempotence for an evolving Ubuntu host.
They also encourage unrelated installation, authentication, and service logic
to accumulate in one privileged script. Shell is not selected as the host
configuration system.

### Cloud-init only

Cloud-init is appropriate for first boot but does not provide the desired
long-lived reconciliation workflow. Treating every change as a reason to
replace the host would increase recovery risk and make stateful T3 validation
harder. It is retained only as the bootstrap bridge.

### Packer and immutable images

Prebuilt machine images can reduce first-boot work and improve fleet
consistency. Phase 1 has one host, no established image pipeline, and several
authentication steps that must remain outside images. Packer is deferred until
measured provisioning time or fleet size justifies an image lifecycle.

### Automated applies from GitHub

An automated plan can be useful later, but automatic apply would introduce a
privileged CI identity, approval policy, secret boundary, and recovery path
before the manual workflow is proven. Phase 1 keeps infrastructure mutation
human-triggered and human-approved.

## Revisit this decision when

- Rivet implements a second cloud provider;
- more than one operator needs routine infrastructure access;
- manual plans and applies become an availability bottleneck;
- a secured remote execution service is required for phone-only recovery;
- the S3 backend or native lockfile no longer meets integrity requirements;
- OpenTofu or the selected AWS provider changes support or licensing
  materially;
- host count makes SSH-based Ansible operation impractical;
- immutable-image provisioning becomes faster or safer than reconciliation;
  or
- the control-node and administrative SSH threat model changes.

Any replacement ADR must preserve reviewed plans, protected remote state,
least-privilege credentials, repeatable host configuration, drift detection,
human approval for destructive changes, and recovery without the original
operator computer.

## Sources

- [OpenTofu providers](https://opentofu.org/docs/language/providers/)
- [OpenTofu dependency lock file](https://opentofu.org/docs/language/files/dependency-lock/)
- [OpenTofu state storage and locking](https://opentofu.org/docs/language/state/backends/)
- [OpenTofu S3 backend](https://opentofu.org/docs/language/settings/backends/s3/)
- [OpenTofu state locking](https://opentofu.org/docs/language/state/locking/)
- [OpenTofu sensitive state](https://opentofu.org/docs/language/state/sensitive-data/)
- [AWS provider Lightsail instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lightsail_instance)
- [AWS provider Lightsail public ports](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lightsail_instance_public_ports)
- [Ansible installation and managed-node model](https://docs.ansible.com/projects/ansible/latest/installation_guide/intro_installation.html)
- [Ansible systemd service module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/systemd_service_module.html)
- [Ansible APT module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/apt_module.html)
- [AWS CloudFormation support for Lightsail](https://docs.aws.amazon.com/lightsail/latest/userguide/creating-resources-with-cloudformation.html)
- [S3 Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)
- [S3 encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
- [S3 pricing](https://aws.amazon.com/s3/pricing/)
- [OpenTofu manifesto](https://opentofu.org/manifesto/)
- [HashiCorp licensing FAQ](https://www.hashicorp.com/en/blog/hashicorp-updates-licensing-faq-based-on-community-questions)
