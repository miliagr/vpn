# NixOS deployment (primary)

Every server is a NixOS system described by this flake. Hosts are listed in `hosts/hosts.json`; the flake builds one `nixosConfigurations.<name>` per entry.

```text
flake.nix            hosts -> nixosConfigurations
hosts/hosts.json     host names, disk device, system, optional datacenter/country (no IPs, no secrets)
hosts/authorized_keys  public SSH keys of the admin user (public, committed)
hosts/ssh_allowed_ips  source IPs/CIDRs allowed to reach SSH (committed; one per line)
nix/common.nix       boot, BBR, GC, journald
nix/security.nix     users, SSH, firewall, fail2ban, sysctl (see Security)
nix/monitoring.nix   localhost-only node_exporter + health timer (see Monitoring)
nix/disk.nix         disko partitioning (BIOS+EFI GPT, ext4)
nix/xray.nix         Xray systemd unit; config rendered at start from server/xray-server.template.json
```

Secrets never enter git or the Nix store. `.env.local` holds them locally; `scripts/nix-push-secrets.sh` writes a per-host `/var/lib/family-vpn/xray.env` (root, 0600) over ssh. The unit renders and tests the config (`xray run -test`) in `ExecStartPre`, and stays skipped until that file exists.

## Local prerequisites
Nix with flakes (`curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install`), `xray`, `jq`, `qrencode`. `flake.lock` is committed; refresh it with `nix flake update`. Both hosts were evaluated against nixpkgs `nixos-unstable` (NixOS 26.11 pre-release); the unit itself has not yet run on a real server.

## First two servers
Follow [install.md](install.md): inspect the VPS, fill `hosts/hosts.json` and `.env.local`, `generate-secrets.sh`, `nix-validate.sh`, then per server `nix-install.sh` (erases the disk), `nix-push-secrets.sh`, `nix-check.sh`, `nix-status.sh`, `nix-probe.sh`; finally `make-mobile-profiles.sh`.

## Day-2
- Config change: edit `nix/`, `./scripts/nix-validate.sh`, `./scripts/nix-deploy.sh <host> admin@ip`, `./scripts/nix-check.sh admin@ip`. Roll back with `ssh admin@ip sudo nixos-rebuild switch --rollback`.
- Rotate secrets: clear the fields in `.env.local`, rerun `generate-secrets.sh`, `nix-push-secrets.sh` per host, regenerate profiles and re-import QR codes.
- Update Xray: `nix flake update nixpkgs`, validate, deploy one host at a time.

## Add a third (Nth) server
1. Add `"vps3": {"disk": "...", "system": "x86_64-linux", "datacenter": "Hetzner FSN1", "country": "DE"}` to `hosts/hosts.json` (`datacenter`/`country` are optional; `country` is a two-letter code).
2. Add `VPS3_ADDR=` to `.env.local`; run `generate-secrets.sh`.
3. `nix-validate.sh`, `nix-install.sh vps3 ...`, `nix-push-secrets.sh vps3 ...`, `nix-check.sh ...`.
4. `make-mobile-profiles.sh` emits `vps3-universal` and `vps3-xhttp-android` automatically. Profile names include the location, e.g. `Family VPN 3 - Hetzner FSN1, DE` and `Family VPN 3 XHTTP - Hetzner FSN1, DE`; without `datacenter`/`country` they are just `Family VPN 3`. Changing a name means re-importing that QR code.

The Ubuntu scripts (`render/deploy/check-server/validate`) are the legacy path and still cover only vps1/vps2.

## Automatic failover (Android)
`./scripts/make-android-auto-profile.sh [--with-xhttp]` writes `build/mobile/android-auto.json`: one Xray client config that contains every server, health-checks them every 10 s through the tunnel itself (`burstObservatory`) and sends new connections to the fastest live one (`leastPing` balancer). If a server dies, new connections move to the survivor within roughly 10-25 s; connections already open on the dead server break and are re-made by the app. If every server is down it fails closed (nothing leaks outside the VPN). No subscription server or control plane is involved. `--with-xhttp` also puts the XHTTP transports in the pool; by default only the Vision profiles are used, and the XHTTP profiles stay as manual fallbacks.

- **Verified:** `tests/test_failover.sh` runs two real Xray servers from the template and a client from this generator, kills each server in turn and checks the client keeps working, and that it fails when all are down.
- **Not verified:** importing the file into the v2rayNG app (menu names and whether the app keeps the config's own inbounds, which use v2rayNG's default local ports 10808/10809). Try it on one device first.
- **How to import:** copy `android-auto.json` to the phone over a private channel (it contains the same secrets as the QR codes: never paste it into chats or cloud notes you do not trust), then in v2rayNG add a profile from a custom/full JSON config (file or clipboard).
- **iPhone:** stays on the two manual profiles (`Family VPN 1/2`); Streisand support for balancing was not verified.
- Regenerate and re-import after any change to hosts, keys or addresses.

## Security
- **Accounts:** `users.mutableUsers = false`; root has no password and cannot SSH in. The only login is `admin` (wheel, passwordless sudo because no password exists; the SSH key from `hosts/authorized_keys` is the sole credential). `nix-install.sh` is the only script that uses `root@` (the provider's initial login).
- **SSH:** key-only, `AllowUsers admin`, 3 auth tries, 20 s grace, no X11/agent forwarding, no SFTP, local TCP forwarding only (for reaching monitoring). fail2ban bans repeated failures (1 h, growing to 48 h).
- **Firewall:** default-deny inbound; 443 and 8443 TCP are open to everyone, **SSH (22) only from the addresses in `hosts/ssh_allowed_ips`** (currently the owner's address and the atlas server). No UDP, no ping. fail2ban ignores the allowed addresses.
- **Kernel:** hardened sysctl (rp_filter, no redirects/source routing, syncookies, kptr/dmesg restrict, BPF restrictions), unused network protocols disabled, kernel image protected, core dumps off.
- **Xray:** dynamic unprivileged user, no access log, systemd sandbox (syscall filter, no devices/kernel access, restricted address families). Routing **blackholes private, loopback, link-local and multicast ranges**, so VPN clients cannot reach the server's own localhost (monitoring ports) or the provider's internal network/metadata service.
- Xray itself warns that REALITY with `www.microsoft.com` and non-443 ports raises the chance of a GFW block; change `REALITY_DEST`/`REALITY_SERVER_NAME` or skip the 8443 profile if that matters.

### Changing the allowed SSH address
Edit `hosts/ssh_allowed_ips` (add the new address **before** removing the old one), `./scripts/nix-validate.sh`, then `./scripts/nix-deploy.sh <host> admin@ip` for each host. If your address changes before you do this you are locked out of SSH (VPN traffic keeps working); recover through the provider's web console. Every script that uses SSH (`nix-deploy/push-secrets/check/status/history/install`) must run from an allowed address; `nix-probe.sh` only needs the VPN ports. A dynamic home IP is a poor fit: use a fixed address, or allow a CIDR you control.

## Monitoring
Self-hosted and pull-based; no third-party service, nothing reachable from the Internet. Three questions, three tools:

| Question | Tool | How it is measured |
|---|---|---|
| Is the VPN available *right now*, as a client sees it? | `./scripts/nix-probe.sh [host...]` | Opens a real VLESS+REALITY tunnel from your machine (universal and XHTTP) via a throwaway local `xray` and fetches a 204 page through it. Exit 1 on any failure. A pass from outside Russia says nothing about Russian filtering. |
| Is each server healthy, who is online, how loaded is the network? | `./scripts/nix-status.sh [--quiet] [host...]` | SSH summary: xray/ports/firewall/fail2ban, failed units, disk, reboot needed, **online source IPs**, connections, **live network Mbit/s** (2 s sample). Exit 1 on any problem; run from cron/launchd. |
| What happened over the last hours/days? | `./scripts/nix-history.sh <host> [hours]` | Availability %, average/peak online, peak Mbit/s and traffic volume from the per-minute history kept on the server for 7 days. |

**"Online" is approximate:** the number of distinct source IPs with an established connection on the VPN ports. Devices behind one router count once, and a device switching networks briefly counts twice. The family shares one UUID, so Xray cannot tell people apart; per-person UUIDs (see `CODEX_TASKS.md`) would allow per-person counts. Only the count is stored, never addresses.

On each host, `node_exporter` listens on `127.0.0.1:9100` and the `family-vpn-health` timer (every minute) writes `/var/lib/family-vpn-metrics/family_vpn.prom` (`family_vpn_up`, `family_vpn_online_source_ips`, `family_vpn_established_connections`, `family_vpn_net_{rx,tx}_bytes_total`, xray/ports/disk/reboot flags, per-inbound Xray byte counters) and appends to `history.csv` (`ts,vpn_up,online,connections,rx_bytes,tx_bytes`). No per-client or per-destination data is collected.

Raw metrics: `ssh -L 9100:127.0.0.1:9100 admin@ip`, then open `http://127.0.0.1:9100/metrics`. Alert delivery (mail, push) is deliberately not built in: it would need an external service or credentials; react to the non-zero exit of `nix-status.sh`/`nix-probe.sh` locally.

## Tests and commit policy

`./tests/run.sh` runs offline checks (syntax, placeholder/secret consistency, secret hygiene, script runs with a fake `xray` and a third host). `tests/test_nix.sh` evaluates every host and checks the security posture (skipped where Nix is absent). `tests/test_failover.sh` (about 40 s, same requirements) kills servers under a real client. `tests/test_e2e.sh` runs a real Xray server from the template plus `nix-probe.sh` against it on this machine (needs xray and internet, uses ports 14443/18443/11111; skipped otherwise). `./scripts/install-hooks.sh` enables `.githooks/pre-commit`, which runs the tests and requires a `CHANGELOG.md` entry in every commit, plus docs when scripts/nix/server/hosts/tests change.
