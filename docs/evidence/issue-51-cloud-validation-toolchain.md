# Issue #51 cloud validation toolchain evidence

Verification date: 2026-10-21

This record contains only public release metadata, archive structure,
installation policy, and redacted test results. It excludes credentials,
private endpoints, host identities, and unrelated operating details.

## Reviewed releases

The three official Linux AMD64 release archives were downloaded into an
isolated temporary directory and verified before their contents were
inspected or executed.

| Tool | Release archive | SHA-256 |
| --- | --- | --- |
| OpenTofu 1.13.1 | `tofu_1.13.1_linux_amd64.zip` | `8ccbc6f8ee21d2827715f3c6e08a9b3e0209b1e62057c05067ef117e047c1a80` |
| ShellCheck 0.11.0 | `shellcheck-v0.11.0.linux.x86_64.tar.xz` | `8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198` |
| Gitleaks 8.30.1 | `gitleaks_8.30.1_linux_x64.tar.gz` | `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb` |

Every pinned digest matched. The verified temporary executables reported
OpenTofu 1.13.1, ShellCheck 0.11.0, and Gitleaks 8.30.1.

## Verified archive layouts

- The OpenTofu ZIP contains the `tofu` executable at its root alongside
  release documentation.
- The ShellCheck XZ-compressed tar archive contains `shellcheck` beneath the
  single `shellcheck-v0.11.0/` top-level directory.
- The Gitleaks gzip-compressed tar archive contains the `gitleaks` executable
  at its root alongside release documentation.

The Ansible extraction policy selects only the reviewed executables and strips
ShellCheck's one release-directory component.

## Installation and security design

Ubuntu receives only `unzip` and `xz-utils` as new archive prerequisites.
Archives are cached below `/var/cache/rivet/validation-tools`, and releases are
installed in root-owned, versioned directories below
`/opt/rivet/validation-tools`. Downloads use the pinned SHA-256 values.

Only `tofu`, `shellcheck`, and `gitleaks` are linked into `/usr/local/bin`.
Their files are owned by `root:root`, use mode `0755`, and are not writable by
the `rivet` account. That account executes each installed binary for the
runtime version assertions but receives no sudo access, Docker-group
membership, writable installation path, or credential.

Downloads, extraction, executable enforcement, links, and runtime version
assertions are skipped in Ansible check mode because their source artifacts
may not exist yet.

## Pre-merge verification

The following checks passed:

- Bash syntax for every changed shell script;
- ShellCheck 0.11.0 for every changed shell script;
- the focused release-pin and installation-policy tests, including Ansible
  syntax validation;
- the system package, service-account, Ubuntu 24.04 platform, and site
  composition tests;
- both OpenTofu configuration validation runs and all six OpenTofu tests when
  using the checksum-verified temporary OpenTofu binary and an isolated
  provider data directory.

The full cloud-foundation suite was attempted with all three checksum-verified
temporary binaries in `PATH`, without system-wide installation. It stopped at
pre-existing ShellCheck `SC2016` findings in
`tests/ansible-t3-code-browser-runtime.sh` and
`tests/cloud-originated-rivet-pr-docs.sh`; those files are outside this change.
The final cloud suite is therefore not claimed as passing before merge.

Privileged Ansible convergence, installed-version verification on the cloud
host, a second idempotency convergence, and the final cloud-foundation suite
remain explicit post-merge gates. No deployment or privileged convergence was
performed for this change.
