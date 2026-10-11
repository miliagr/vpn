# 0001. WireGuard: fixed client MTU, TCP MSS clamping, IPv6 routed into the tunnel

Date: 2026-10-11
Status: Accepted

## Context

Reported from the phones: after a phone restart a site sometimes opens without its images, sometimes does not open at all, and some resources answer "no internet". It happens on both transports, more often on WireGuard.

The defects were found by reading the repository and then checked on `aeza-de-n-1` (2026-10-11, read-only). Over 8 days of uptime before the fix the kernel counters showed that packets towards the phones regularly did not fit into `wg0`: 2.7 million packets had to be fragmented (`IpFragOKs`) and 76 thousand were dropped with ICMP "fragmentation needed" (`IpFragFails`, `IcmpOutDestUnreachs`), out of 10.7 million packets sent into the tunnel. The server itself was healthy: WireGuard listening, handshakes fresh, NAT and firewall rules in place. Only an Android phone was connected. The IPv6 bypass (item 3) was not measured; it follows from the profile contents.

1. **MTU mismatch.** The server interface `wg0` has MTU 1280, the generated client profiles had no `MTU` line. The Android app then defaults to 1280, but the iOS app and desktop `wg-quick` derive a larger value (about 1420). Such a client announces a TCP MSS that does not fit into the server's `wg0`.
2. **No MSS clamping.** The server forwarded TCP without adjusting the MSS. A reply larger than 1280 bytes is dropped at `wg0`, and the server asks the far end to send smaller packets by ICMP "fragmentation needed". Many sites and CDNs never receive or ignore that message, so small responses (HTML) arrive and large ones (images) hang.
3. **IPv6 bypassed the tunnel.** Profiles had `AllowedIPs = 0.0.0.0/0` only. On a mobile network with IPv6, every destination with an AAAA record was reached directly, outside the VPN: blocked resources stayed blocked, and one page could load partly through the VPN and partly not.

Not explained by this ADR: the same symptoms on VLESS, and the fact that plain WireGuard is recognisable to DPI on Russian mobile networks. See "Consequences".

## Decision

- `scripts/make-wireguard-profiles.sh` writes `MTU = 1280`, the same value as `mtu` in `nix/wireguard.nix`; a test compares the two.
- `nix/wireguard.nix` adds two `mangle FORWARD` rules (`-i wg0`, `-o wg0`) with `TCPMSS --clamp-mss-to-pmtu`, so both ends of every TCP connection agree on a segment size that fits the tunnel regardless of the client's MTU.
- IPv6 goes into the tunnel and is rejected there. Clients get a ULA address `fd42:42:42::N/128` (N = last octet of their IPv4 address, so `hosts/wireguard_clients.json` stays the only list) and `AllowedIPs = 0.0.0.0/0, ::/0`. The server has `fd42:42:42::1/64` on `wg0`, allows each peer its ULA address, and has IPv6 forwarding on with no IPv6 default route, so the kernel answers with ICMPv6 "no route" and apps fall back to IPv4 at once.

## Alternatives considered

- **Raise the server MTU to 1420.** Fits fewer mobile paths (PPPoE, CGNAT, operators' own tunnels); 1280 works everywhere. Rejected.
- **Only set the client MTU, no clamping.** Leaves any client with a hand-edited or old profile broken. Rejected.
- **`AllowedIPs = 0.0.0.0/0, ::/0` without a client IPv6 address.** IPv6 is then silently dropped and apps wait for a timeout. Rejected.
- **Real IPv6 through the VPN (NAT66).** The server has no IPv6 uplink. Rejected.
- **Replace WireGuard with AmneziaWG.** Addresses DPI blocking, not these defects; a separate decision (`docs/amneziawg.md`).

## Consequences

- Deploy the server first (`./scripts/nix-deploy.sh <host> admin@<ip>`); profiles already on the phones keep working with it.
- Then regenerate the profiles (`./scripts/make-wireguard-profiles.sh`) and re-import them on every phone, deleting the old tunnel. Without the re-import the phone gets only the MSS clamping.
- All traffic through WireGuard is IPv4. IPv6-only sites are unreachable through it.
- Verify: `./scripts/nix-check.sh`, `./scripts/nix-status.sh <host>`, `./scripts/nix-probe.sh <host>`; on the server `sudo iptables -t mangle -S FORWARD` shows the two `TCPMSS` rules; on a phone a page with many images loads completely and an IP-check site shows the server's address.
- Roll back: revert the commit, `nix-deploy` again (or `nixos-rebuild --rollback` on the host); the new profiles keep working for IPv4 with the old server.
- If the failures remain after this, the next suspects are the mobile network's filtering of WireGuard and the phone clients' settings; that needs measurements from the server and a phone, not more configuration guesses.
