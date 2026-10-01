# Family VPN

A small private VPN for the owner and parents: the same Xray stack (VLESS + REALITY) on independent VPS hosts, each one a **NixOS system declared in this repository**, plus generated mobile import profiles. It deliberately has **no subscription service, panel, database, billing, or public user management**.

## Architecture

```text
Android / v2rayNG                     iPhone / Streisand
      |                                      |
      |---- Family VPN 1 --------------------|
      |      VLESS + REALITY + Vision :443   |
      |                                      |
      |---- Family VPN 2 --------------------|
      |      VLESS + REALITY + Vision :443   |
      |                                      |
      +---- Android-only fallbacks --------->|
             XHTTP + REALITY :8443
             on every server
```

Start with two servers (different providers/ASNs when practical); adding more is one entry in `hosts/hosts.json`. Android can also use one auto-failover profile that switches between servers by itself; iPhone switches manually.

## Quick start

**Full guide with requirements, checks and troubleshooting: [docs/install.md](docs/install.md).** In short, per server:

```bash
cp .env.example .env.local                  # once; set VPS1_ADDR (and VPS2_ADDR)
# edit hosts/hosts.json (disk, optional datacenter/country), hosts/ssh_allowed_ips, hosts/authorized_keys

./scripts/preflight.sh
./scripts/generate-secrets.sh               # fills UUID/keys/short IDs in .env.local, prints nothing
./scripts/nix-validate.sh                   # every host must evaluate

./scripts/nix-install.sh vps1 root@VPS1_IP          # ERASES the VPS disk, installs NixOS
./scripts/nix-push-secrets.sh vps1 admin@VPS1_IP    # secrets -> server, tested, Xray starts
./scripts/nix-check.sh admin@VPS1_IP
./scripts/nix-status.sh vps1
./scripts/nix-probe.sh vps1                 # real tunnel from your Mac

# repeat for vps2, then:
./scripts/make-mobile-profiles.sh           # QR codes in build/mobile/
./scripts/make-android-auto-profile.sh      # optional Android auto-failover config
```

Requirements on your Mac: Nix with flakes, `xray`, `jq`, `qrencode` (`brew install xray jq qrencode`; Nix: see the install guide). Run the scripts from an address listed in `hosts/ssh_allowed_ips`: servers accept SSH only from there, and only as the `admin` user (root login is disabled after the install).

Never commit or paste `.env.local`, `build/`, UUIDs, REALITY keys, short IDs, VLESS links or the auto-failover JSON.

## Mobile profiles

```text
build/mobile/vps1-universal.png        vps2-universal.png
build/mobile/vps1-xhttp-android.png    vps2-xhttp-android.png
build/mobile/android-auto.json         (optional, secrets inside)
```

Names include the location when set in `hosts/hosts.json`, e.g. `Family VPN 1 - Hetzner FSN1, DE`.

- **Android (v2rayNG):** import all four QR codes. Use `Family VPN 1` normally, `Family VPN 2` if the first is unreachable, XHTTP profiles as extra fallbacks. Or import the auto-failover config (see [docs/nixos.md](docs/nixos.md#automatic-failover-android); importing it into the app is not yet verified).
- **iPhone (Streisand):** import only the two universal QR codes; switch to `Family VPN 2` manually if needed.

## Operating it

| Need | Command |
|---|---|
| Health, online users, network load; exit 1 on problems | `./scripts/nix-status.sh [--quiet] [host]` |
| Is the VPN really usable from here (real tunnel) | `./scripts/nix-probe.sh [host]` |
| Availability, peak users/load, traffic over N hours | `./scripts/nix-history.sh <host> [hours]` |
| Apply a configuration change | `./scripts/nix-validate.sh`, then `./scripts/nix-deploy.sh <host> admin@IP` |
| Roll back | `ssh admin@IP sudo nixos-rebuild switch --rollback` |
| Add a server | entry in `hosts/hosts.json` + `VPSn_ADDR`, then the quick start for it |

Details, security hardening, monitoring, replacing servers: [docs/nixos.md](docs/nixos.md).

## Security model

- Secrets live only in `.env.local` (local) and `/var/lib/family-vpn/xray.env` (root-only, on each server); never in git or the Nix store.
- Servers: immutable accounts, key-only SSH from allowed addresses only, default-deny firewall (443/8443 TCP public), fail2ban, hardened kernel settings, sandboxed Xray that blackholes private/loopback destinations, no access logs. Monitoring is localhost-only and pull-based.
- The owner of the server can technically see destinations of unencrypted traffic, as with any VPN; third parties on the network path cannot decrypt it.
- One family VLESS UUID is used for simplicity; per-person UUIDs can be added later (see `CODEX_TASKS.md`).

## Repository layout

```text
flake.nix, nix/        NixOS configuration (common, disk, security, monitoring, xray)
hosts/                 hosts.json, authorized_keys, ssh_allowed_ips
server/                Xray config template (shared)
scripts/               nix-*.sh (NixOS workflow), make-*-profiles, generate-secrets, preflight
scripts/lib/           shared helpers
tests/                 ./tests/run.sh
docs/                  install.md, nixos.md
```

## Tests and contributing

```bash
./scripts/install-hooks.sh   # once
./tests/run.sh
```

Every commit updates `CHANGELOG.md` (and docs when behaviour changes); the pre-commit hook runs the tests and enforces it.

## Using an AI agent

Open the folder in Codex or Claude Code (they read `AGENTS.md` / `CLAUDE.md`) and use a prompt such as:

```text
Read AGENTS.md and CODEX_TASKS.md completely and follow them.
Prepare and deploy this private family VPN to my VPS hosts using the NixOS workflow.
Keep all secrets local and never print UUIDs, REALITY private keys, short IDs, or VLESS URIs in chat.
Ask before any step that erases a disk, and verify each VPS before moving to the next one.
At the end tell me only which QR files to import into v2rayNG on Android and Streisand on iPhone.
```

## Legacy: Ubuntu without NixOS

The older path configures Xray on an existing Ubuntu 24.04 host and is kept only for reference; it covers exactly `vps1` and `vps2` and has none of the NixOS hardening or monitoring:

```bash
./scripts/render.sh && ./scripts/validate.sh
./scripts/deploy.sh vps1 root@VPS1_IP && ./scripts/check-server.sh root@VPS1_IP
./scripts/deploy.sh vps2 root@VPS2_IP && ./scripts/check-server.sh root@VPS2_IP
```

`render.sh` refuses documentation/placeholder addresses, so both `VPS1_ADDR` and `VPS2_ADDR` must be real for it. Do not mix this path with the NixOS one on the same server.
