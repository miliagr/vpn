# 0002. Separate WireGuard client for SSH to the server

Date: 2026-10-11
Status: Accepted

## Context

The owner's laptop used the same WireGuard profile (`owner`) as the owner's Android phone. With the tunnel on, the laptop lost access to the server.

Checked on `aeza-de-n-1` and on the laptop (2026-10-11, read-only):

- A WireGuard server keeps one endpoint per client key and answers whoever sent the last packet. The server saw two UDP flows to the WireGuard port from the same public address with different source ports, and one session. The phone sends a keepalive every 25 s and keeps taking the session over, so the second device gets no replies. The laptop's own WireGuard log could not be read, so the laptop side is not confirmed.
- SSH from inside the tunnel was not allowed at all: port 22 accepted only the addresses in `hosts/ssh_allowed_ips`, none of them a tunnel address. The laptop reached SSH only through another route (Tailscale).

## Decision

- A fourth client, `admin`, with its own key and the address `10.42.0.5`, marked `"ssh": true` in `hosts/wireguard_clients.json`.
- `nix/wireguard.nix` adds one firewall rule per such client: TCP 22 accepted on `wg0` from exactly that tunnel address. fail2ban ignores it, like the addresses in `hosts/ssh_allowed_ips`. Other WireGuard clients (the phones) still cannot reach port 22.
- Its profile is a split tunnel: `AllowedIPs = 10.42.0.1/32`, no `DNS`. Only `ssh admin@10.42.0.1` goes through it; the laptop's other traffic and any other VPN on it are untouched.
- `make-wireguard-profiles.sh` takes the client list from `hosts/wireguard_clients.json` instead of a second hard-coded list.

SSH still needs the key from `hosts/authorized_keys`; the WireGuard key only makes the port reachable.

## Alternatives considered

- **A second full-tunnel client for the laptop.** Solves the key conflict but not SSH, and fights with the laptop's other VPN for the default route. Rejected.
- **Add `10.42.0.0/24` to `hosts/ssh_allowed_ips`.** Opens port 22 to every WireGuard client, including the parents' phones. Rejected.
- **Add only `10.42.0.5` to `hosts/ssh_allowed_ips`.** Works, but the rule would not be bound to `wg0`, and the reason for the address would live in a different file than the client. Rejected.
- **Keep using only the public allowlist.** Depends on the laptop's current public address or on a third-party network. Kept as the other way in, not replaced.

## Consequences

- This widens who can reach port 22: before, two public addresses; now also the holder of the `admin` WireGuard key. `build/mobile/<host>-wireguard-admin.conf` is therefore an admin credential: keep it only on the owner's laptop.
- Deploy with `./scripts/nix-deploy.sh <host> admin@<ip>` (the owner's go-ahead is required: it changes SSH access). The existing public allowlist is unchanged, so access cannot be lost by this change.
- On the laptop: import `build/mobile/<host>-wireguard-admin.conf` into the WireGuard app, remove the `owner` tunnel from the laptop (one key, one device), then `ssh admin@10.42.0.1`. The first connection asks to confirm the host key for the new address; it is the same key as for the public address.
- A deploy over this tunnel restarts the network on the server; the session normally survives, but the public route is the safer one for deploys.
- Verify: `sudo iptables -S nixos-fw | grep 'dport 22'` on the server shows the two public rules and one `-i wg0 -s 10.42.0.5` rule; `ssh admin@10.42.0.1 true` works from the laptop with the tunnel on; `./scripts/nix-check.sh`, `./scripts/nix-status.sh <host>`.
- Roll back: remove the `admin` entry (or its `ssh` flag) from `hosts/wireguard_clients.json` and deploy.
