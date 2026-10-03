# VPN

A small private VPN for the owner and parents: the same Xray stack (VLESS + REALITY) on independent VPS hosts, each one a **NixOS system declared in this repository**, plus generated mobile import profiles. It deliberately has **no subscription service, panel, database, billing, or public user management**.

## Architecture

```text
Android / v2rayNG                     iPhone / Streisand
      |                                      |
      |---- VPN <server 1> ------------|
      |      VLESS + REALITY + Vision :443   |
      |                                      |
      |---- VPN <server 2> ------------|
      |      VLESS + REALITY + Vision :443   |
      |                                      |
      +---- Android-only fallbacks --------->|
             XHTTP + REALITY :8443
             on every server
```

Currently one server; adding more is one entry in `hosts/hosts.json` (different providers/ASNs when practical, so one outage does not take everything down). Android can also use one auto-failover profile that switches between servers by itself; iPhone switches manually.

## Quick start

**Full guide with requirements, checks and troubleshooting: [docs/install.md](docs/install.md).** In short, per server:

```bash
cp .env.example .env.local                  # once; set AEZA_DE_N_1_ADDR (your host's variable, see below)
# edit hosts/hosts.json (host name + disk), hosts/ssh_allowed_ips, hosts/authorized_keys

./scripts/preflight.sh
./scripts/generate-secrets.sh               # fills UUID/keys/short IDs in .env.local, prints nothing
./scripts/nix-validate.sh                   # every host must evaluate

./scripts/nix-install.sh aeza-de-n-1 root@SERVER_IP          # ERASES the VPS disk, installs NixOS
./scripts/nix-push-secrets.sh aeza-de-n-1 admin@SERVER_IP    # secrets -> server, tested, Xray starts
./scripts/nix-check.sh admin@SERVER_IP
./scripts/nix-status.sh aeza-de-n-1
./scripts/nix-probe.sh aeza-de-n-1                 # real tunnel from your Mac

./scripts/make-mobile-profiles.sh           # VLESS QR codes in build/mobile/
./scripts/make-wireguard-profiles.sh        # WireGuard QR codes in build/mobile/
# later, with 2+ servers: ./scripts/make-android-auto-profile.sh (Android auto-failover config, VLESS only)
```

Requirements on your Mac: Nix with flakes, `xray`, `jq`, `qrencode` (`brew install xray jq qrencode`; Nix: see the install guide). Run the scripts from an address listed in `hosts/ssh_allowed_ips`: servers accept SSH only from there, and only as the `admin` user (root login is disabled after the install).

Never commit or paste `.env.local`, `build/`, UUIDs, REALITY keys, short IDs, VLESS links or the auto-failover JSON.

## Mobile profiles

```text
build/mobile/<host>-universal.png         one per host, VLESS+REALITY+Vision
build/mobile/<host>-xhttp-android.png     one per host, Android only, VLESS+XHTTP+REALITY
build/mobile/<host>-wireguard-owner.png     per-user WireGuard profile (owner)
build/mobile/<host>-wireguard-parent1.png   per-user WireGuard profile (parent1)
build/mobile/<host>-wireguard-parent2.png   per-user WireGuard profile (parent2)
build/mobile/android-auto.json            optional, needs 2+ servers, VLESS auto-failover, secrets inside
```

Profile names: `VPN <host name>` (e.g. `VPN aeza-de-n-1`), `... XHTTP` (Android only), `... WireGuard (<user>)`.

**Server naming:** `<datacenter>-<country>-n-<number>`, for example `aeza-de-n-1`. The name is the key in `hosts/hosts.json`, the profile name, and (upper-cased, `-` replaced by `_`) the prefix of its variables in `.env.local`: `AEZA_DE_N_1_ADDR`, `AEZA_DE_N_1_REALITY_PRIVATE_KEY`, ...

WireGuard's UDP listen/firewall port is set once per host as `wireguardPort` in `hosts/hosts.json`. Both the NixOS server configuration and generated client profiles use that value; it is not a secret or an `.env.local` variable.

- **Android (v2rayNG for VLESS, WireGuard app for WireGuard):** import every VLESS QR code (`*-universal.png`, `*-xhttp-android.png`). Use your main server's profile normally, another server's profile if it is unreachable, XHTTP profiles as extra fallbacks. Import your personal WireGuard profile (e.g., `*-wireguard-owner.png`) into the WireGuard app. Or import the auto-failover config (see [docs/nixos.md](docs/nixos.md#automatic-failover-android); importing it into the app is not yet verified).
- **iPhone (Streisand for VLESS, WireGuard app for WireGuard):** import only the VLESS `*-universal.png` QR codes; with several servers switch manually if one is unreachable. Import your personal WireGuard profile into the WireGuard app.

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

- Secrets live only in `.env.local` (local) and `/var/lib/vpn/xray.env` (root-only, on each server); never in git or the Nix store.
- Servers: immutable accounts, key-only SSH from allowed addresses only, default-deny firewall (443/8443 TCP public), fail2ban, hardened kernel settings, sandboxed Xray that blackholes private/loopback destinations, no access logs. Monitoring is localhost-only and pull-based.
- The owner of the server can technically see destinations of unencrypted traffic, as with any VPN; third parties on the network path cannot decrypt it.
- One VLESS UUID is used for simplicity; per-person UUIDs can be added later (see `CODEX_TASKS.md`).

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

Every commit must (1) pass the tests, (2) update `CHANGELOG.md` and any docs it touches, and (3) delete whatever became unnecessary (scripts, options, tests, outdated doc text). The pre-commit hook runs the tests and checks the changelog/docs; the cleanup is on the author, and `tests/test_static.sh` catches orphaned scripts and doc references to missing ones.

## Using an AI agent

Open the folder in Codex or Claude Code (they read `AGENTS.md` / `CLAUDE.md`) and use a prompt such as:

```text
Read AGENTS.md and CODEX_TASKS.md completely and follow them.
Prepare and deploy this private VPN to my VPS hosts using the NixOS workflow.
Keep all secrets local and never print UUIDs, REALITY private keys, short IDs, or VLESS URIs in chat.
Ask before any step that erases a disk, and verify each VPS before moving to the next one.
At the end tell me only which QR files to import into v2rayNG on Android and Streisand on iPhone.
```
