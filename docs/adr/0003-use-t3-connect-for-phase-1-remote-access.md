# ADR-0003: Use T3 Connect for Phase 1 remote access

- Status: Accepted
- Date: 2026-10-07
- Decision owners: Project maintainers
- Review trigger: Failed mobile acceptance test, material trust-boundary change,
  or recurring relay outage

## Context

Rivet needs one secure route between the official T3 Code mobile app and the
always-on Lightsail host. The route must work without the developer's laptop,
must not expose an unauthenticated T3 endpoint, and must recover after a host
reboot.

T3 Code currently documents three suitable categories:

- T3 Connect, using T3's hosted identity, relay, and managed tunnel;
- Tailscale HTTPS, using a private tailnet and Tailscale Serve; and
- direct HTTPS, using a public address, DNS, TLS termination, and T3 pairing.

All three routes ultimately connect a client to the same T3 environment and
use the environment's authorization model. The route changes reachability and
trust dependencies; it does not move repositories, providers, execution, or
durable T3 state away from the Lightsail host.

The product and security facts in this record were checked on 2026-10-07. T3
Connect is an evolving hosted service, so its architecture, commands, limits,
and recovery behavior must be rechecked before provisioning.

## Decision

Phase 1 will use T3 Connect as its only supported T3 client access route.

The Lightsail host will:

1. run T3 Code as the dedicated non-root service user selected by the host
   configuration decision;
2. link that environment to the developer's T3 Connect account with
   `t3 connect`;
3. run T3 Code through the background service required by ADR-0002;
4. keep the T3 origin bound to loopback for the managed tunnel; and
5. make only the outbound connections required by T3 Connect.

The Lightsail firewall will not expose the T3 server port, HTTP port 80, or
HTTPS port 443 to the public internet for this route. Administrative SSH policy
will be decided and enforced separately; it is not a T3 client route.

Phase 1 will not configure Tailscale Serve, Tailscale Funnel, a public reverse
proxy, a custom T3 domain, or a direct-HTTPS fallback. A fallback that silently
bypasses T3 Connect would invalidate the tested exposure and authentication
boundary.

## Why this option

T3 Connect is the route built specifically to make a T3 environment available
to T3's other clients without router forwarding. It gives the mobile app
environment discovery and connection recovery without requiring a separate
VPN application, tailnet membership, public DNS zone, TLS certificate
automation, or public inbound web port.

Its managed connector uses an outbound Cloudflare Tunnel. Cloudflare documents
that `cloudflared` establishes outbound-only connections, so the origin does
not require a publicly reachable T3 listener. T3 further documents that its
managed tunnel exposes only a validated loopback HTTP origin.

T3 Connect also preserves the linked environment when an offline tunnel is
reclaimed. When the host starts again, the connector can request a replacement
tunnel while retaining the same managed hostname, so clients do not need to be
paired again. This aligns with the reboot-recovery requirement in ADR-0002.

This is a usability decision with an explicit trust tradeoff. It is not a
claim that T3 Connect has fewer external dependencies or a smaller trust
boundary than a private tailnet.

## Trust and authorization boundary

The accepted route depends on:

- T3's hosted relay for environment linking, discovery, managed tunnel
  allocation, and short-lived connection bootstrap credentials;
- Clerk for T3 Connect cloud identity;
- Cloudflare for the managed tunnel and hostname; and
- the local T3 environment for the final session and RPC authorization.

T3 documents the relay as a trusted broker. The relay asks the environment for
a one-time bootstrap credential bound to the client's DPoP key. The client
exchanges that credential directly with the environment, and the relay does
not receive the resulting environment session token. Each RPC still requires
an environment scope; establishing a socket does not grant unrestricted
authority.

These controls reduce credential replay and prevent a cloud login alone from
becoming an environment session. They do not remove trust in the relay: T3
explicitly documents that compromise of the relay signing key is not made
harmless by DPoP. Clerk, the relay, Cloudflare, DNS, or the public network can
also make the route temporarily unavailable.

Phase 1 accepts those dependencies for one developer and one environment. It
does not claim an uptime guarantee for T3 Connect and must report relay or
tunnel failure separately from host or T3 service failure.

## Access rules

- Each phone, browser profile, or desktop client must receive its own T3
  authorization; credentials must not be copied between devices.
- Pairing links and authorization codes are secrets and must never appear in
  Git, screenshots, logs, issue bodies, or pull requests.
- New client authorization must delegate only the scopes needed for the mobile
  development workflow.
- Ordinary clients must not receive access-management authority unless the
  tested workflow requires it and the grant is documented.
- A lost or retired device must have its environment session revoked.
- Deregistering the T3 Connect environment is a separate operation from
  revoking a client and must require explicit human intent.
- T3 Connect credentials must be stored under the non-root service account and
  outside all repositories.
- The host firewall must not open a public T3 listener as a troubleshooting
  shortcut.

## Acceptance gate

The route is accepted only after the real Phase 1 host and official mobile app
pass all of these checks:

1. Inspect the Lightsail firewall and host listeners; confirm that no T3,
   HTTP, or HTTPS port is publicly reachable.
2. Run `t3 connect`, complete the documented headless sign-in, and verify the
   background service independently with `t3 service status`.
3. Connect from the official mobile app over mobile data, not the host's local
   network.
4. Open an existing project and thread, invoke one authorized read action, and
   invoke one authorized development action.
5. Background and foreground the mobile app long enough to force connection
   replacement, then confirm that it reconnects to the same environment.
6. Disconnect all clients and verify that the host service remains running.
7. Reboot the host and verify that T3 Connect restores access without SSH,
   laptop action, a new pairing, or a changed saved environment.
8. Revoke the phone's environment session and confirm that its existing saved
   connection can no longer read or execute against the host.
9. Authorize the phone again with a fresh flow and confirm that access returns.
10. Deregister the environment from the T3 Connect account and confirm that its
    cloud access is removed without deleting local projects or T3 state.
11. Inspect service and connector logs for pairing credentials, authorization
    codes, provider secrets, prompts, and repository content; none may be
    exposed unnecessarily.

The gate fails if a public T3 port is required, a revoked client retains usable
access, reboot recovery needs the laptop, the service runs as root, or a secret
is written to repository-controlled or routinely published output.

Testing must also record distinct symptoms for:

- host unavailable;
- T3 background service unavailable;
- T3 Connect authentication rejected;
- relay or Cloudflare tunnel unavailable; and
- mobile network unavailable.

Those states require different recovery actions and must not be collapsed into
a generic "offline" result.

## Consequences

### Positive

- The official mobile app can discover and reach the environment without a
  separate VPN client.
- The host needs no public inbound T3, HTTP, or HTTPS port.
- No custom domain, certificate renewal, or reverse proxy is required.
- T3's environment scopes and revocation model remain authoritative.
- The managed link can recover its tunnel after the host returns without
  pairing every client again.
- T3 Connect matches the one-developer Phase 1 workflow with the least custom
  network infrastructure.

### Negative

- Availability depends on T3's relay, Clerk, Cloudflare, and public DNS in
  addition to AWS and the host.
- The relay is a trusted broker with signing authority in the bootstrap flow.
- T3 Connect service behavior and limits are outside Rivet's control.
- A relay, identity, or tunnel incident can block mobile access even when the
  Lightsail host and T3 service are healthy.
- This decision does not provide a private network for SSH or other host
  administration.

## Alternatives considered

### Tailscale HTTPS

Tailscale Serve can keep the endpoint private to a tailnet, apply tailnet
access rules, and provide HTTPS for the T3 endpoint. Tailscale documents its
node connections as end-to-end encrypted. This is the preferred fallback if a
later threat model rejects the T3 Connect trust boundary.

It was not selected for the first proof because every participating phone and
computer must also join and maintain the tailnet. Rivet would need to manage a
second client application, device approval, access policy, server key expiry,
and recovery when a remote server's key expires. Enabling Tailscale HTTPS also
publishes the machine and tailnet certificate name to Certificate Transparency,
even though access remains restricted to the tailnet.

Tailscale's current Personal plan is free only for qualifying personal,
non-commercial use. Rivet must not assume that price for a later commercial or
multi-user offering.

### Direct public HTTPS

Direct HTTPS removes the T3 relay and private-network client, but it requires a
stable public endpoint, DNS, certificate issuance and renewal, a reverse proxy,
public firewall rules, security patching, and additional monitoring. A typical
public ACME configuration exposes ports 80 and 443, while a DNS challenge
instead places DNS-provider credentials on the host or another automation
system.

T3 authentication would still be required because TLS alone does not authorize
a client. The additional internet-facing surface and operational burden are
unnecessary for Phase 1, so this route is rejected.

### Support multiple routes simultaneously

Multiple routes would make recovery appear more flexible but would multiply
exposure, credential, revocation, monitoring, and test paths. It would also
allow an insecure fallback to mask a failure in the selected route. Phase 1
will prove one route completely before adding another.

## Revisit this decision when

- T3 Connect cannot pass the mobile or reboot acceptance gate;
- relay, identity, or tunnel outages repeatedly block the workflow;
- T3 materially changes the relay trust or environment-authentication model;
- T3 Connect introduces a price or limit incompatible with Phase 1;
- project policy requires a private network or self-hosted access plane;
- Rivet adds secure remote administration that would already require a
  tailnet;
- more than one developer or environment changes the authorization model; or
- direct HTTPS becomes necessary for a client T3 Connect cannot support.

Any replacement ADR must define endpoint exposure, TLS ownership, client and
device identity, least-privilege scopes, revocation, secret storage, reboot
recovery, mobile background recovery, and failure observability.

## Sources

- [T3 Code remote access](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)
- [T3 Connect architecture](https://github.com/pingdotgg/t3code/blob/main/docs/internals/t3-connect.md)
- [T3 environment authentication](https://github.com/pingdotgg/t3code/blob/main/docs/internals/environment-auth.md)
- [T3 remote architecture](https://github.com/pingdotgg/t3code/blob/main/docs/internals/remote.md)
- [T3 connection runtime](https://github.com/pingdotgg/t3code/blob/main/docs/internals/connection-runtime.md)
- [T3 Connect relay](https://github.com/pingdotgg/t3code/blob/main/infra/relay/README.md)
- [Cloudflare Tunnel connectivity](https://developers.cloudflare.com/cloudflare-one/networks/connectivity-options/)
- [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)
- [Tailscale HTTPS certificates](https://tailscale.com/docs/how-to/set-up-https-certificates)
- [Tailscale key expiry](https://tailscale.com/docs/features/access-control/key-expiry)
- [Tailscale pricing](https://tailscale.com/pricing)
- [Caddy HTTPS quick start](https://caddyserver.com/docs/quick-starts/https)
- [Lightsail firewall behavior](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-firewall-and-port-mappings-in-amazon-lightsail.html)
