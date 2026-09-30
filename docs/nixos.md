# NixOS deployment (primary)

Every server is a NixOS system described by this flake. Hosts are listed in `hosts/hosts.json`; the flake builds one `nixosConfigurations.<name>` per entry.

```text
flake.nix            hosts -> nixosConfigurations
hosts/hosts.json     host names, disk device, system (no IPs, no secrets)
hosts/authorized_keys  public SSH keys allowed as root (public, committed)
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
Provision two plain Ubuntu/Debian VPS with root SSH key access, set the real `disk` in `hosts/hosts.json`, then:

```bash
cp .env.example .env.local        # set VPS1_ADDR, VPS2_ADDR
./scripts/preflight.sh
./scripts/generate-secrets.sh
./scripts/nix-validate.sh

./scripts/nix-install.sh vps1 root@VPS1_IP      # ERASES the disk (asks for confirmation)
./scripts/nix-push-secrets.sh vps1 admin@VPS1_IP   # root SSH is disabled after install
./scripts/nix-check.sh admin@VPS1_IP
# only then repeat for vps2

./scripts/make-mobile-profiles.sh
```

## Day-2
- Config change: edit `nix/`, `./scripts/nix-validate.sh`, `./scripts/nix-deploy.sh <host> admin@ip`, `./scripts/nix-check.sh admin@ip`. Roll back with `ssh admin@ip sudo nixos-rebuild switch --rollback`.
- Rotate secrets: clear the fields in `.env.local`, rerun `generate-secrets.sh`, `nix-push-secrets.sh` per host, regenerate profiles and re-import QR codes.
- Update Xray: `nix flake update nixpkgs`, validate, deploy one host at a time.

## Add a third (Nth) server
1. Add `"vps3": {"disk": "...", "system": "x86_64-linux"}` to `hosts/hosts.json`.
2. Add `VPS3_ADDR=` to `.env.local`; run `generate-secrets.sh`.
3. `nix-validate.sh`, `nix-install.sh vps3 ...`, `nix-push-secrets.sh vps3 ...`, `nix-check.sh ...`.
4. `make-mobile-profiles.sh` emits `vps3-universal` and `vps3-xhttp-android` automatically ("Family VPN 3").

The Ubuntu scripts (`render/deploy/check-server/validate`) are the legacy path and still cover only vps1/vps2.

## Security
- **Accounts:** `users.mutableUsers = false`; root has no password and cannot SSH in. The only login is `admin` (wheel, passwordless sudo because no password exists; the SSH key from `hosts/authorized_keys` is the sole credential). `nix-install.sh` is the only script that uses `root@` (the provider's initial login).
- **SSH:** key-only, `AllowUsers admin`, 3 auth tries, 20 s grace, no X11/agent forwarding, no SFTP, local TCP forwarding only (for reaching monitoring). fail2ban bans repeated failures (1 h, growing to 48 h).
- **Firewall:** default-deny inbound; only 22 (SSH), 443 and 8443 TCP. No UDP, no ping.
- **Kernel:** hardened sysctl (rp_filter, no redirects/source routing, syncookies, kptr/dmesg restrict, BPF restrictions), unused network protocols disabled, kernel image protected, core dumps off.
- **Xray:** dynamic unprivileged user, no access log, systemd sandbox (syscall filter, no devices/kernel access, restricted address families). Routing **blackholes private, loopback, link-local and multicast ranges**, so VPN clients cannot reach the server's own localhost (monitoring ports) or the provider's internal network/metadata service.
- Xray itself warns that REALITY with `www.microsoft.com` and non-443 ports raises the chance of a GFW block; change `REALITY_DEST`/`REALITY_SERVER_NAME` or skip the 8443 profile if that matters.

## Monitoring
Self-hosted and pull-based; no third-party service, nothing reachable from the Internet.
- Each host runs `node_exporter` on `127.0.0.1:9100` and a timer (`family-vpn-health`, every minute) that writes `/var/lib/family-vpn-metrics/family_vpn.prom`: xray up, ports listening, failed units, root disk %, reboot required, aggregate per-inbound byte counters from Xray's localhost metrics (`127.0.0.1:11111/debug/vars`). No per-client or per-destination data is collected.
- `./scripts/nix-status.sh [--quiet] [host...]` SSHes to each host as `admin`, prints a summary and **exits 1 on any problem** (xray down, ports closed, failed units, firewall/fail2ban inactive, disk >= 85%, stale health timer, reboot required, unreachable). Run it from cron/launchd and alert locally on a non-zero exit.
- Raw metrics: `ssh -L 9100:127.0.0.1:9100 admin@ip`, then open `http://127.0.0.1:9100/metrics` locally.
- Alert delivery (mail, push) is deliberately not built in: it would need an external service or credentials. Decide that separately.

## Tests and commit policy

`./tests/run.sh` runs offline checks (syntax, placeholder/secret consistency, secret hygiene, script runs with a fake `xray` and a third host). `tests/test_nix.sh` evaluates every host and is skipped where Nix is absent, so run it once Nix is installed. `./scripts/install-hooks.sh` enables `.githooks/pre-commit`, which runs the tests and requires a `CHANGELOG.md` entry in every commit, plus docs when scripts/nix/server/hosts/tests change.
