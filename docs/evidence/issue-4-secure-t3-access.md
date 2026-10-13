# Issue #4 secure T3 access verification

Verification date: 2026-10-13

Implementation commit before evidence documentation: `cda2f80`

This record contains only redacted results. It intentionally excludes account
identifiers, authorization URLs and codes, callback values, session and tunnel
identifiers, trace IDs, hostnames, IP addresses, SSH material, process IDs, and
unrelated logs.

## Delivered scope

- Pinned and checksum-verified T3 Code `0.0.45` for Linux x64.
- Private installation and state directories owned by the non-root `rivet`
  service account.
- Enabled systemd user service with lingering and explicit loopback binding.
- Headless T3 Connect authorization and managed outbound tunnel.
- No public T3, HTTP, HTTPS, or Tailscale client listener.
- Documented authorization, inspection, revocation, reauthorization,
  deregistration, recovery, and layered troubleshooting.

## Automated verification

`tests/verify-cloud-foundation.sh` passed at `cda2f80`. The gate included
OpenTofu formatting, validation and tests; Ansible syntax and policy tests;
T3 package, layout, checksum-download, extraction, symlink, service,
lingering, and loopback tests; firewall-policy tests; shell checks; and
repository secret scanning.

Ansible check mode completed without an unreachable host or failure:

```text
ok=33 changed=6 unreachable=0 failed=0 skipped=13 rescued=0 ignored=0
```

The first live convergence completed successfully after adding the two runtime
packages required by the actual host:

```text
ok=46 changed=8 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

The second live run proved idempotence:

```text
ok=45 changed=0 unreachable=0 failed=0 skipped=2 rescued=0 ignored=0
```

Service inspection confirmed:

- the launcher and `t3 serve` child ran as `rivet`;
- the user service was active and enabled;
- lingering was enabled;
- `T3CODE_HOST=127.0.0.1`; and
- T3 listened only on `127.0.0.1:3773`.

The listener inspection contained no public T3, HTTP, or HTTPS socket. The
repository firewall checks retained the existing deny-by-default host policy
and Lightsail's sentinel-only administrative rule.

After final reauthorization, the redacted T3 Connect status was:

```json
{
  "desired": true,
  "authenticated": true,
  "linked": true,
  "relayClientStatus": "available"
}
```

## Manual verification

| Scenario | Result |
| --- | --- |
| Initial mobile connection | Android discovered and connected to the intended cloud environment through T3 Connect. |
| Public exposure | Connection required no manually entered endpoint, browser certificate exception, direct Tailscale route, or public inbound T3/HTTP/HTTPS port. |
| App interruption | Backgrounding and foregrounding the Android app restored the existing environment connection. |
| Network interruption | Airplane mode disconnected the client; disabling it reconnected the same environment. |
| No connected clients | After Mac and Android disconnected, `t3code.service` remained active. |
| Server-session revocation | Revoked the Android environment session; the signed-in T3 Connect client automatically obtained a replacement, proving server-session revocation alone is not a lost-device control. |
| Device-account revocation | Revoked Android under the account's active sessions; Android was signed out and could not access the environment. |
| Device reauthorization | A fresh Android account sign-in created new authorization and restored environment connectivity without relinking the host. |
| Environment deregistration | Mobile account-level deregistration removed cloud access without deleting the host's local T3 state. |
| Host authorization removal | Host logout disabled the local link and cleared its stored CLI authorization even though relay cleanup reported a transient upstream failure after deregistration. |
| Environment reauthorization | A fresh headless host authorization and service restart restored the managed link and mobile connectivity. |

No thread-continuity claim is included: no development thread existed during
this issue's access verification.

## Failure and recovery evidence

The verification distinguished two non-product-code failures:

1. Relay cleanup returned a transient upstream-unavailable response after the
   environment had already been deregistered. Local logout still removed the
   host authorization, and a later fresh authorization restored service.
2. Android temporarily failed to fetch the managed environment endpoint over
   both Wi-Fi and mobile data. During the failure, redacted host logs showed
   four registered managed-tunnel connections, and independent DNS, TLS, and
   HTTP probes succeeded. The mobile connection subsequently recovered without
   widening a firewall or exposing another route.

Cloudflared also reported that its optional ICMP proxy was disabled for the
non-root service group. HTTP tunnel registration and mobile connectivity both
succeeded, so no additional ping capability was granted.

## Security review

- T3 Code runs as a dedicated non-root service user.
- The origin remains loopback-only.
- T3 Connect is the only T3 client route.
- Administrative SSH remains separate and private through Tailscale.
- Device-level account revocation, not server-session deletion alone, is the
  documented lost-phone control.
- No secret or private identifier from the authorization and diagnostic work
  is present in this record.
- Human review remains required before merge.
