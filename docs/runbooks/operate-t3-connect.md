# Operate secure T3 Connect access

This runbook operates the T3 Connect route installed by Issue #4. It covers
authorization, service inspection, mobile access, revocation, reauthorization,
deregistration, and failure isolation. It does not expose T3 Code directly,
enable Tailscale as a T3 client route, or install agent providers.

Rivet currently supports the reviewed T3 Code `0.0.45` Linux x64 release. The
Ansible role owns installation and service configuration. Do not update the
binary or edit the generated systemd unit manually.

## Security boundaries

- Run T3 Code only as the dedicated `rivet` account.
- Keep the T3 listener on `127.0.0.1:3773`.
- Do not open the T3 port, HTTP port 80, or HTTPS port 443 in UFW or Lightsail.
- Use Tailscale-protected SSH only for host administration.
- Treat authorization URLs, short codes, callback values, session credentials,
  tunnel hostnames, trace IDs, and account identifiers as secrets.
- Give every device its own T3 Connect account session. Never copy a session
  credential between devices.
- Use account-session revocation for a lost phone. Revoking only its T3 server
  session is insufficient because a still-signed-in T3 Connect client can
  obtain a replacement server session.

The shell examples expect the connection variables from the
[cloud-foundation runbook](provision-cloud-foundation.md). The private
`RIVET_WORKSPACE_IP` is the routine administrative route, while
`RIVET_WORKSPACE_PUBLIC_IP` is used only as the previously verified SSH host-key
alias.

## Converge and verify the service

Apply the reviewed Ansible configuration over private SSH:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --ssh-common-args \
    "-o HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP -o StrictHostKeyChecking=yes" \
  ansible/site.yml
```

Run it again. The second play recap must report `changed=0`,
`unreachable=0`, and `failed=0`.

Inspect the service without printing its saved credentials:

```bash
ssh \
  -o "HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP" \
  -o StrictHostKeyChecking=yes \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "rivet_uid=\$(id -u rivet); \
  sudo -u rivet env \
    XDG_RUNTIME_DIR=/run/user/\${rivet_uid} \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\${rivet_uid}/bus \
    systemctl --user show t3code.service \
      --property=ActiveState \
      --property=UnitFileState \
      --property=Environment \
      --property=MainPID; \
  loginctl show-user rivet --property=Linger; \
  sudo ss -ltnp"
```

Require all of these conditions:

- `ActiveState=active`;
- `UnitFileState=enabled`;
- `Linger=yes`;
- the service and its `t3 serve` child run as `rivet`;
- `T3CODE_HOST=127.0.0.1`; and
- the only T3 TCP listener is `127.0.0.1:3773`.

Stop if T3 listens on a wildcard, public, or tailnet address. Do not compensate
for an incorrect bind by adding another firewall rule.

## Authorize the headless host

Run the pinned CLI as `rivet` and force its device flow. The explicit
`--headless` flag is required because privilege transitions can remove the SSH
environment variables that T3 otherwise uses to detect a headless session.

```bash
ssh \
  -o "HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP" \
  -o StrictHostKeyChecking=yes \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "sudo -u rivet env \
    HOME=/home/rivet \
    PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /home/rivet/.local/bin/t3 connect link --headless"
```

Open the displayed authorization URL on a trusted device, confirm that its
short code matches, and approve the expected T3 Connect account. Never paste
the URL, code, or resulting callback into chat, an issue, a log, or a pull
request.

Restart the supervised service so it reconciles the saved link:

```bash
ssh \
  -o "HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP" \
  -o StrictHostKeyChecking=yes \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "rivet_uid=\$(id -u rivet); \
  sudo -u rivet env \
    XDG_RUNTIME_DIR=/run/user/\${rivet_uid} \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\${rivet_uid}/bus \
    systemctl --user restart t3code.service"
```

Inspect only the non-secret status fields:

```bash
ssh \
  -o "HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP" \
  -o StrictHostKeyChecking=yes \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "sudo -u rivet env \
    HOME=/home/rivet \
    PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /home/rivet/.local/bin/t3 connect status --json" |
jq '{
  desired,
  authenticated,
  linked,
  relayClientStatus: .relayClient.status
}'
```

The four values must be `true`, `true`, `true`, and `"available"`. This is
saved configuration state, not a live mobile-connectivity check.

## Connect and exercise a mobile client

On the official mobile application:

1. Sign in to the same T3 Connect account.
2. Open **Settings → Environments** and select the linked cloud environment.
3. Enable its connection and confirm it becomes connected over mobile data.
4. Background and foreground the app and confirm it reconnects.
5. Enable airplane mode, confirm the environment disconnects, disable airplane
   mode, and confirm the same environment reconnects.
6. Disconnect every client without signing out. After 30 seconds, rerun the
   service inspection and require `ActiveState=active`.

A browser certificate warning, manually entered endpoint, direct Tailscale
route, or public listener invalidates this verification.

## Revoke and reauthorize one device

T3 server sessions and T3 Connect account sessions have different effects. A
server-session revocation terminates that credential, but a client whose cloud
account session remains valid can automatically request another one.

To remove a lost or retired phone, use another trusted T3 client:

1. Open the T3 account profile.
2. Open **Security → Active sessions**.
3. Identify the phone by its device details and recent activity.
4. Revoke only that phone's account session.
5. Confirm the phone is signed out and cannot reach the environment.

To return the phone to service, sign in again on that phone with the approved
account, select the existing environment, and confirm connectivity. Do not
relink the host; reauthorization creates a new device account session while
the existing environment link remains intact.

## Deregister and restore the environment

In the mobile app, open **Settings → T3 Connect**, select the environment's
actions, and choose **Deregister**. Confirm that it disappears from T3 Connect
and can no longer be reached through the cloud route. Deregistration removes
the account-level environment record; it does not delete local projects or T3
state from the host.

Clear the host's saved authorization separately:

```bash
ssh \
  -o "HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP" \
  -o StrictHostKeyChecking=yes \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "sudo -u rivet env \
    HOME=/home/rivet \
    PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /home/rivet/.local/bin/t3 connect logout"
```

If account-level deregistration already succeeded, a later relay-side deletion
may report a transient upstream failure. Require the command to confirm that
T3 Connect is disabled locally and its stored CLI authorization was removed.
Then inspect the filtered status: `desired`, `authenticated`, and `linked` must
all be `false`.

Restore service using the headless authorization and service-restart procedure
above. Require the filtered status to return to the four accepted values and
repeat the real mobile connection check.

## Isolate failures by layer

| Layer | Safe evidence | Interpretation |
| --- | --- | --- |
| Host | Private SSH and `systemctl --user is-active t3code.service` | Host reachability and service supervision |
| Listener | `ss -ltnp` showing only `127.0.0.1:3773` for T3 | Local origin is running without public exposure |
| Authorization | Filtered `t3 connect status --json` | Saved host authorization and desired-link state |
| Managed tunnel | Redacted service log entries showing registered tunnel connections | Host established its outbound relay transport |
| Public endpoint | DNS, TLS, and `/.well-known/t3/environment` probe with the hostname redacted | Managed endpoint is externally reachable |
| Mobile network | Same client tested separately over Wi-Fi and mobile data | Device path or network-specific filtering |
| Mobile account | Account profile and active-session state | Device remains authorized to request environment credentials |
| T3 server session | Redacted `t3 auth` session state | Current environment credential, not the device's cloud login |

Cloudflared warnings that only disable its ICMP proxy do not prove an HTTP
tunnel failure. Do not expand Linux ping permissions unless ICMP proxying is an
explicit requirement. Likewise, do not open an inbound port to work around a
T3 Connect relay, identity, DNS, TLS, or mobile-client failure.

When publishing diagnostics, retain only the failing layer, timestamp,
sanitized error category, HTTP status, and whether recovery succeeded. Remove
URLs, hostnames, IP addresses, account data, authorization material, session
identifiers, trace IDs, process IDs, and unrelated agent or repository logs.

## Authoritative references

- [ADR-0003: T3 Connect remote access](../adr/0003-use-t3-connect-for-phase-1-remote-access.md)
- [T3 Code 0.0.45 remote-access documentation](https://github.com/pingdotgg/t3code/blob/v0.0.45/docs/user/remote-access.md)
- [T3 Connect architecture](https://github.com/pingdotgg/t3code/blob/v0.0.45/docs/internals/t3-connect.md)
- [Clerk native user-profile active sessions](https://clerk.com/docs/reference/expo/native-components/user-profile-view)
