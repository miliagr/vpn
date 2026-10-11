# Changelog

Every commit must update this file (enforced by `.githooks/pre-commit`; enable with `./scripts/install-hooks.sh`). Never put UUIDs, keys, short IDs or VLESS links here.

## Unreleased

### Added
- WireGuard client `admin` for SSH to the server through the tunnel (`ssh admin@10.42.0.1`): own key, address `10.42.0.5`, split-tunnel profile `build/mobile/<host>-wireguard-admin.conf`. Port 22 is accepted on `wg0` only from clients marked `"ssh": true` in `hosts/wireguard_clients.json`; the phones' clients still cannot reach it. `make-wireguard-profiles.sh` now reads the client list from that file. One WireGuard key works on one device at a time, so the laptop must not share the `owner` profile with the phone. See `docs/adr/0002-wireguard-admin-ssh-client.md`.

### Fixed
- `nix-check.sh` stopped with exit 1 at the SSH policy step: the installed OpenSSH prints `sshd -T` keys capitalised (`PermitRootLogin`), and the check matched lower case only. It now matches case-insensitively.

### Fixed
- WireGuard: pages loading without images or not at all, and some resources unreachable. Client profiles now set `MTU = 1280` (same as the server), the server clamps TCP MSS on `wg0`, and IPv6 is routed into the tunnel and rejected there instead of bypassing the VPN. Needs `nix-deploy` and re-importing the WireGuard profiles. See `docs/adr/0001-wireguard-mtu-mss-ipv6.md`.

### Added
- AI-agent instructions (`AGENTS.md`, `CLAUDE.md`) now require an ADR in `docs/adr/` for every serious fix or change; `docs/adr/README.md` defines "serious" and the record format.

### Changed
- WireGuard now takes each host's UDP port from `hosts/hosts.json` for the server listener, firewall and generated client profiles; the randomized `.env.local` port is removed.

### Changed
- `make-wireguard-profiles.sh` generates one `.conf`/QR profile per user and host. Client keys are stored in `.env.local`; stable client IPs are declared in `hosts/wireguard_clients.json`.

### Changed
- Renamed service and paths from `family-vpn-*` to `vpn-*`: `family-vpn-health` → `vpn-health`, `/var/lib/family-vpn` → `/var/lib/vpn`, `/var/lib/family-vpn-metrics` → `/var/lib/vpn-metrics`, `family_vpn.prom` → `vpn.prom`, metrics `family_vpn_*` → `vpn_*`. Requires server reinstall.

### Fixed
- `nix-push-secrets.sh` now calls `/run/current-system/sw/bin/xray-render` instead of bare `xray-render` inside the `sudo bash -s` block: sudo's `secure_path` doesn't include the Nix profile, so the config test failed with `xray-render: command not found` and the script kept the old secrets.

### Added
- `nix-install.sh` forwards extra options to nixos-anywhere (`--debug`, `--kexec-extra-flags ...`). Needed on Ubuntu 26.04 at Aeza, where the kernel rejects the unsigned installer kernel through the file-based kexec call (`PEFILE: Unsigned PE binary`, "Kexec failed"); the install guide's troubleshooting table documents the `--kexec-extra-flags "--kexec-syscall"` workaround.

### Changed (server naming)
- Servers are named `<datacenter>-<country>-n-<number>` (first one: `aeza-de-n-1`). The name is the key in `hosts/hosts.json`, the profile name (`VPN aeza-de-n-1`, `... XHTTP`) and, upper-cased with `-` -> `_`, the variable prefix in `.env.local` (`AEZA_DE_N_1_ADDR`). A test enforces the pattern.
- New `scripts/lib/hosts.sh` (`host_prefix`) used by all scripts that read per-host variables.
- Removed the optional `datacenter`/`country` fields and their handling: the name carries that information.
- Tests build their own sandbox hosts (hyphenated names) instead of relying on the real host list.
- `.env.local` keys of the first server migrated from `VPS1_*` to `AEZA_DE_N_1_*`; unused `VPS2_*` entries removed.

### Changed (one server for now)
- `hosts/hosts.json` lists only `vps1`; `.env.example` drops the VPS2 lines (add them when a second server exists). Tests require at least one host and add vps2/vps3 themselves in their sandbox.
- Docs (README, install guide, nixos.md, CODEX_TASKS, AGENTS, CLAUDE) describe the one-server state and the steps for adding more.
- `make-android-auto-profile.sh` notes when the pool has a single server (nothing to fail over to).

### Removed
- The Ubuntu path (`render.sh`, `validate.sh`, `deploy.sh`, `check-server.sh`) and its docs; the NixOS workflow replaces it. `preflight.sh` now requires `nix` and `curl` and no longer checks `scp`.

### Added
- `scripts/lib/guards.sh`: all scripts that take a server address refuse RFC 5737 placeholder addresses (the guard `render.sh` used to provide).
- Rule (AGENTS.md, CLAUDE.md, README): every commit updates the docs it touches and deletes what became unnecessary; a test fails on undocumented scripts, and the pre-commit hook prints a reminder.

### Changed (documentation)
- `README.md` rewritten for the current NixOS workflow (quick start, operating commands, security model, layout); the Ubuntu path is labelled legacy at the end.
- `AGENTS.md`, `CODEX_TASKS.md`, `START_HERE.txt` and `CLAUDE.md` updated: install via `nix-install.sh`/`nix-push-secrets.sh`, verification via `nix-check/status/probe`, disk-erase confirmation, current guarantees.

### Added
- `docs/install.md`: step-by-step server installation guide (requirements, inspection, configuration, secrets, install, verification, second server, profiles, troubleshooting); `docs/nixos.md` and `README.md` link to it.
- Test that every `scripts/*.sh` mentioned in the docs exists.

### Changed
- `hosts/ssh_allowed_ips`: SSH is now also allowed from the atlas server (a second source address), in addition to the owner's address.

### Added (automatic failover)
- `scripts/make-android-auto-profile.sh`: one Android client config with all servers, `burstObservatory` health checks and a `leastPing` balancer; fails closed when every server is down; `--with-xhttp` adds the XHTTP transports.
- `scripts/lib/client-outbound.sh`: shared builder for client VLESS+REALITY outbounds; `nix-probe.sh` now uses it.
- `tests/test_failover.sh`: real two-server failover test (kills each server in turn).

### Notes
- Importing the file into v2rayNG itself is not verified; iPhone remains manual.

### Added
- Optional `datacenter` and `country` per host in `hosts/hosts.json`; they are appended to mobile profile names (`VPN 1 - Hetzner FSN1, DE`, `VPN 1 XHTTP - Hetzner FSN1, DE`) and shown by `nix-status.sh`. Hosts without them keep the plain names. Tests validate the format.

### Security
- SSH (port 22) is reachable only from the addresses listed in `hosts/ssh_allowed_ips` (initially the owner's address); the firewall no longer opens 22 globally. fail2ban ignores those addresses. Evaluation fails if the list is empty or contains anything but IPs/CIDRs.
- Tests assert that 22 is not globally open and that each allowed source has exactly one accept rule.

### Added (availability, online users, network load)
- `scripts/nix-probe.sh`: end-to-end availability check; opens real VLESS+REALITY tunnels (universal and XHTTP) from the local machine through a throwaway xray client.
- `nix-status.sh` now shows online source IPs, connections and live network Mbit/s, and treats `family_vpn_up` (xray + VPN ports) as the availability signal.
- `scripts/nix-history.sh`: availability %, average/peak online, peak network load and traffic over the last N hours.
- Health timer now records `family_vpn_up`, `family_vpn_online_source_ips`, connection counts and interface counters, and keeps a 7-day per-minute `history.csv` (counts only, no addresses).
- `tests/test_e2e.sh`: real Xray server from the template + `nix-probe.sh`; also asserts clients cannot reach the server's localhost through the tunnel.

### Fixed
- `services.journald.storage` renamed upstream; use `settings.Journal.Storage`.
- `tests/test_*.sh` append (not prepend) the Nix profile to `PATH`, so they keep using the system `curl`.

### Security
- New `nix/security.nix`: immutable accounts, no root SSH login, single `admin` user with key-only SSH, hardened sshd, fail2ban, default-deny firewall (22/443/8443 TCP only, no ping/UDP), sysctl and kernel-module hardening.
- Xray unit sandboxed further (syscall filter, protected kernel/devices, restricted address families, umask 077).
- Xray template: access log off, private/loopback/link-local/multicast destinations blackholed so clients cannot reach the server itself.
- Day-2 scripts now use `admin@host` (sudo on the server); `nix-install.sh` still uses the provider's `root@host` for the first install only.

### Added (monitoring)
- `nix/monitoring.nix`: localhost-only node_exporter, `family-vpn-health` timer writing textfile metrics, Xray metrics on `127.0.0.1:11111`.
- `scripts/nix-status.sh`: pull-based health summary over SSH, non-zero exit on problems; `nix-check.sh` also shows SSH policy and all listening sockets.
- Tests: security posture assertions on the evaluated NixOS config, real `xray run -test` of the rendered template, template invariants, `nix-status.sh` against a fake ssh.

### Fixed
- `xray-render` passes `-format json`; without it the config test failed on the extensionless temp file used by `nix-push-secrets.sh`.

### Fixed
- `services.journald.extraConfig` was removed from current NixOS, so every host failed to evaluate; use `services.journald.settings.Journal`. Found by the first real Nix evaluation.
- `tests/test_nix.sh` now finds Nix in `/nix/var/nix/profiles/default/bin`, so it is no longer silently skipped in non-login shells.
- Added `flake.lock` (pins nixpkgs and disko).

### Added
- NixOS as the primary target: `flake.nix`, `nix/` (common, disko disk layout, Xray unit), `hosts/hosts.json` as the single host list. See `docs/nixos.md`.
- `scripts/nix-validate.sh`, `nix-install.sh`, `nix-push-secrets.sh`, `nix-check.sh`, `nix-deploy.sh`.
- Test suite in `tests/` (`tests/run.sh`): static checks, secret hygiene, and script runs with a fake `xray` including a third host. `tests/test_nix.sh` evaluates all hosts when Nix is installed.
- Pre-commit hook that runs the tests and requires a changelog entry plus docs for behaviour changes; `scripts/install-hooks.sh`.
- `CLAUDE.md` with project rules for Claude.

### Changed
- `generate-secrets.sh` and `make-mobile-profiles.sh` iterate over `hosts/hosts.json` instead of a hard-coded vps1/vps2.
- `preflight.sh` also checks `jq` and reports whether `nix` is present.
- Legacy Ubuntu scripts (`render`, `validate`, `deploy`, `check-server`) kept, vps1/vps2 only.
