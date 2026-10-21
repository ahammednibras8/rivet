# Issue #52 T3 browser runtime evidence

Verification date: 2026-10-21

This record contains only redacted operating-system, runtime, and verification
facts. It excludes private paths, repository identities, credentials, prompts,
and unrelated logs.

## Exact observed failure

```text
Preview automation open failed: This host is missing libraries T3's browser needs (libatk-1.0.so.0, libatk-bridge-2.0.so.0, libXcomposite.so.1, libXdamage.so.1, libXfixes.so.3, libXrandr.so.2, libgbm.so.1, libasound.so.2, libatspi.so.0). Run `sudo env "PATH=$PATH" t3 browser setup` on the host to install them, then try again.
```

The failure was reproduced once on Ubuntu 24.04 AMD64 with T3 CLI 0.1.0.
The installed browser executable is Chrome Headless Shell 154.0.8037.92.
Installed T3 runtime documentation states that this browser installs on first
use, and the executable was present, so no separate browser download is
required.

## Library diagnosis

`ldd` reported only these unresolved libraries and Ubuntu package mappings:

| Missing library | Ubuntu 24.04 package |
| --- | --- |
| `libatk-1.0.so.0` | `libatk1.0-0t64` |
| `libatk-bridge-2.0.so.0` | `libatk-bridge2.0-0t64` |
| `libatspi.so.0` | `libatspi2.0-0t64` |
| `libXcomposite.so.1` | `libxcomposite1` |
| `libXdamage.so.1` | `libxdamage1` |
| `libXfixes.so.3` | `libxfixes3` |
| `libXrandr.so.2` | `libxrandr2` |
| `libgbm.so.1` | `libgbm1` |
| `libasound.so.2` | `libasound2t64` |

The installed T3 runtime maps these same nine libraries to these minimum
packages. Ubuntu package metadata reports AMD64 candidates for every package.

The AppArmor user-namespace restriction is enabled, AppArmor is active, and
the required T3 browser profile was absent at diagnosis time. The managed
profile grants `userns` only to T3's Chrome Headless Shell path pattern.

## Reproducible correction

The existing T3 Code Ansible role now owns the nine browser library packages
alongside its existing runtime package. It also installs a validated AppArmor
profile as `root:root` mode `0644` and reloads the profile only when the managed
file changes. The `rivet` account receives no sudo access, Docker-group
membership, credential, or additional administrative capability.

## Verification boundary

Focused static policy, AppArmor syntax, Ansible syntax, ownership,
idempotency-structure, service-account boundary, and diff checks are run before
publication.

Pre-publication verification passed:

- Bash syntax checks for the changed test and suite scripts;
- the focused T3 browser runtime test, including parse-only AppArmor validation;
- every T3 Code Ansible role test;
- the system package policy, service-account policy, and site composition
  tests; and
- `git diff --check`.

No privileged convergence or successful browser launch is claimed yet.

OpenTofu, ShellCheck, and Gitleaks remain unavailable while Issue #51 is paused,
so the full cloud-foundation suite is not claimed as passing.

Human review and a privileged Ansible apply remain required.
