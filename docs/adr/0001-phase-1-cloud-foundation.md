# ADR-0001: Use AWS Lightsail in Mumbai for the Phase 1 host

- Status: Accepted
- Date: 2026-10-07
- Decision owners: Project maintainers
- Review trigger: Phase 1 capacity test, pricing change, or region availability

## Context

Rivet needs one cloud machine that can keep a T3 Code environment reachable
when the developer's laptop is off. Phase 1 needs predictable cost, an Indian
region, a supported Linux host, persistent storage, snapshots, and enough
capacity for one developer working in one repository with one active coding
agent.

T3 Code supports a command-line server on Linux. Its remote-host documentation
requires the host to remain running and reachable, and its Linux background
service uses a systemd user service with lingering so it can survive logout and
start at boot. T3 does not publish a minimum memory requirement, so machine
capacity cannot be treated as proven until it is measured with the Phase 1
workflow.

The pricing and product facts in this record were checked on 2026-10-07.
Provider pricing and available images can change and must be checked again
before provisioning.

## Decision

Phase 1 will use this cloud foundation:

| Field | Selection |
| --- | --- |
| Provider | Amazon Web Services, Amazon Lightsail |
| Region | Asia Pacific (Mumbai), `ap-south-1` |
| Operating system | Ubuntu Server 24.04 LTS |
| Architecture | x86-64 |
| Instance plan | General Purpose, 2 vCPU, 4 GB RAM, 80 GB SSD |
| Network plan | Public IPv4 bundle; exposure policy is decided separately |
| Base instance price | USD 24 per month before tax |
| Phase 1 spending limit | USD 30 per month before tax |

Only one Phase 1 instance is authorized by this decision. Additional
instances, block-storage disks, load balancers, databases, object-storage
buckets, or other paid AWS resources require a separate accepted decision.

This record selects the host foundation only. It does not decide whether the
host is always on, which T3 connection route is used, or which
infrastructure-management tools provision it.

## Why this option

### Region

Lightsail is available in `ap-south-1`. Mumbai keeps the Phase 1 host in India
and avoids selecting a more distant region before any latency measurements
exist. Proximity is the selection rationale, not a claim of measured latency;
the mobile acceptance test must measure the real connection from the networks
the developer uses.

### Operating system and architecture

Lightsail documents an Ubuntu 24 blueprint, and Ubuntu 24.04 LTS receives
standard security maintenance through 2029. The x86-64 architecture is chosen
for the broadest compatibility with T3 Code, coding-agent providers, browser
dependencies, and repository toolchains. ARM may be evaluated later only after
the complete toolchain is verified on it.

Ubuntu 26.04 LTS is newer, but Phase 1 values the explicitly documented
Lightsail image and the more established package ecosystem over the longer
remaining support window.

### Initial machine size

The 4 GB plan is the smallest Lightsail plan that leaves reasonable headroom
for the operating system, T3 Code, one coding-agent provider, Git, a language
toolchain, and a focused test run. The workload is remote-agent orchestration
and development; it does not include local model inference.

This is a cost-bounded starting hypothesis, not a vendor-backed T3 sizing
recommendation. T3 publishes no minimum RAM figure. Recent upstream bug reports
also show that unusual histories or tool payloads can drive memory far beyond
normal idle use, including reports on an approximately 8 GB host. Those reports
are treated as failure modes to test, not as evidence that every T3 host needs
more than 4 GB.

The 4 GB plan must not be declared production-ready until it passes the
capacity gate below. If it fails, the decision must be amended before resizing;
the current budget does not authorize the 8 GB plan.

## Cost envelope

The selected instance bundle currently costs USD 24 per month and includes 2
vCPUs, 4 GB RAM, an 80 GB SSD, and a nominal 4 TB transfer allowance. Lightsail
documents that Mumbai receives half the standard transfer allowance, so the
effective included allowance is 2 TB. Excess outbound transfer in Mumbai is
currently USD 0.13 per GB.

Lightsail snapshots cost USD 0.05 per stored GB-month. The remaining USD 6 in
the Phase 1 limit therefore accommodates at most 120 GB-month of billable
snapshot data if there are no other charges. Automatic snapshots keep the
latest seven daily recovery points, but actual cost depends on stored and
changed data and is not guaranteed to remain below USD 6.

The following controls are required when the host is provisioned:

- create an AWS monthly cost budget of USD 30;
- notify at 80 percent actual spend;
- notify at 100 percent forecasted spend;
- notify at 100 percent actual spend;
- tag every Rivet resource for cost attribution;
- keep the paid-resource inventory limited to this decision;
- review snapshot storage and transfer usage at least monthly.

The USD 30 value is a governance limit, not a hard billing cap. AWS states that
budget data is updated only up to three times per day and that costs can
continue after a threshold notification. AWS Budget actions can restrict new
provisioning, but they do not provide a reliable hard cutoff for an existing
Lightsail instance.

Lightsail also charges for an instance while it is stopped and stops charging
only when the instance is deleted. The later always-on versus suspend/resume
decision must account for this: stopping this Lightsail instance is not a cost
optimization.

Taxes, currency-conversion fees, and unrelated AWS-account charges are outside
the USD 30 service-cost figure. The budget should include taxes if the AWS
account exposes them consistently.

## Capacity acceptance gate

Before Phase 1 accepts the 4 GB plan, the actual cloud host must complete one
representative end-to-end run containing:

1. T3 Code running as its Linux background service.
2. One authenticated coding-agent provider.
3. One representative repository dependency installation.
4. One active agent thread and worktree.
5. The repository's focused test, lint, type-check, and build commands where
   applicable.
6. One T3 browser or preview session if that is part of the intended mobile
   workflow.
7. A mobile disconnect and reconnect while the environment remains active.

During the run, capture CPU, memory, swap, disk, and OOM-killer evidence. The
plan passes only if:

- the kernel records no out-of-memory kill;
- the T3 server and agent do not crash or restart unexpectedly;
- peak used memory remains below 90 percent of physical RAM;
- sustained used memory remains below 80 percent of physical RAM;
- swap, if configured later, does not show sustained thrashing;
- the focused verification commands complete without resource failure;
- disk use remains below 70 percent of the included 80 GB;
- phone interaction remains usable under the measured network conditions.

Any OOM event, repeated memory pressure, unusable build time, or inability to
keep 30 percent disk headroom rejects this size. The next candidate is the
Lightsail 8 GB plan, but its current USD 44 base price requires a new spending
decision.

## Consequences

### Positive

- The monthly base price is predictable and fits below the Phase 1 limit.
- Mumbai is a documented Lightsail region.
- Compute, boot storage, public addressing, basic metrics, and firewall
  controls are available in one product.
- Ubuntu 24.04 LTS has a long remaining maintenance window.
- The instance can be recreated from a snapshot if the recovery procedure is
  verified.
- Lightsail can later export supported snapshots toward EC2 if Phase 1 outgrows
  the simplified product.

### Negative

- Two shared vCPUs and 4 GB RAM may be insufficient for large builds, multiple
  agents, browser-heavy work, or memory regressions.
- Stopping the instance does not stop its compute charge.
- The budget is alerting and governance, not a hard cap.
- Mumbai's transfer allowance is half the standard Lightsail allowance.
- A single instance and region provide no host or regional high availability.
- Snapshot storage and transfer overage can push the bill above USD 30.

## Alternatives considered

### DigitalOcean Basic Droplet in Bangalore

DigitalOcean currently offers a Basic Droplet with 2 vCPUs, 4 GiB RAM, 80 GiB
SSD, and 4,000 GiB transfer for USD 24 per month, and documents `blr1` as its
Bangalore region. It is a credible fallback and has more included transfer in
India.

It was not selected for Phase 1 because it does not provide a material base
price advantage, while the chosen Lightsail path provides the AWS budget
controls and daily incremental snapshot model used by this decision. This is
not a performance rejection; no comparative benchmark has been run.

### Hetzner Cloud in Singapore

Hetzner's CPX22 provides 2 shared AMD vCPUs, 4 GB RAM, and 80 GB NVMe. Current
Singapore pricing after the June 2026 adjustment is higher than the Phase 1
Lightsail base price, excludes IPv4 from the listed server price, and includes
less regional transfer. Singapore is also farther from the primary user than
the selected Indian region. It is not selected.

### Amazon EC2

EC2 offers substantially more instance, storage, networking, and lifecycle
control. Phase 1 does not need that flexibility, and its separate compute,
storage, IP, and transfer pricing would make the initial cost envelope harder
to understand. Lightsail is selected as the simpler AWS entry point.

### Lightsail 8 GB plan

The 8 GB plan reduces memory risk but currently costs USD 44 per month before
snapshot storage and tax. It violates the accepted Phase 1 spending limit. It
is the first resize candidate if the capacity gate rejects 4 GB.

### Ubuntu 26.04 LTS

Ubuntu 26.04 LTS has a longer support window, but Ubuntu 24 is the currently
documented Lightsail blueprint and has sufficient support for Phase 1. The
project will prefer the established image until the complete Rivet and T3
toolchain is tested on 26.04.

## Revisit this decision when

- the capacity gate fails;
- T3 Code publishes an official minimum above this plan;
- the workload needs more than one concurrent agent or repository build;
- disk use reaches 70 percent;
- forecasted monthly AWS cost reaches USD 30;
- AWS removes the selected plan, image, or Mumbai availability;
- pricing changes materially;
- measured mobile latency makes another Indian region or provider preferable;
- Phase 1 requires high availability or a true suspend-to-save-cost model.

## Sources

- [T3 Code remote access](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)
- [T3 Code background service](https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md)
- [T3 Code installation](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md)
- [Lightsail regions](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-regions-and-availability-zones-in-amazon-lightsail.html)
- [Lightsail plans and pricing](https://aws.amazon.com/lightsail/pricing/)
- [Lightsail instance bundles](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-bundles.html)
- [Lightsail data transfer](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-faq-data-transfer-allowance.html)
- [Lightsail billing behavior](https://docs.aws.amazon.com/en_en/lightsail/latest/userguide/amazon-lightsail-frequently-asked-questions-faq-billing-and-account-management.html)
- [Lightsail images](https://docs.aws.amazon.com/lightsail/latest/userguide/compare-options-choose-lightsail-instance-image.html)
- [Lightsail snapshots](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-faq-snapshots.html)
- [AWS Budgets behavior](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [Ubuntu release lifecycle](https://ubuntu.com/about/release-cycle)
- [DigitalOcean Droplet pricing](https://www.digitalocean.com/pricing/droplets)
- [DigitalOcean regional availability](https://docs.digitalocean.com/platform/regional-availability/)
- [Hetzner CPX plans](https://www.hetzner.com/cloud/regular-performance/)
- [Hetzner June 2026 pricing adjustment](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)
- [T3 long-running memory report](https://github.com/pingdotgg/t3code/issues/4597)
- [T3 large-payload memory report](https://github.com/pingdotgg/t3code/issues/5389)
