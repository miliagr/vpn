# Changelog

Every commit must update this file (enforced by `.githooks/pre-commit`; enable with `./scripts/install-hooks.sh`). Never put UUIDs, keys, short IDs or VLESS links here.

## Unreleased

### Changed
- `hosts/ssh_allowed_ips`: SSH is now also allowed from the atlas server (a second source address), in addition to the owner's address.

### Added (automatic failover)
- `scripts/make-android-auto-profile.sh`: one Android client config with all servers, `burstObservatory` health checks and a `leastPing` balancer; fails closed when every server is down; `--with-xhttp` adds the XHTTP transports.
- `scripts/lib/client-outbound.sh`: shared builder for client VLESS+REALITY outbounds; `nix-probe.sh` now uses it.
- `tests/test_failover.sh`: real two-server failover test (kills each server in turn).

### Notes
- Importing the file into v2rayNG itself is not verified; iPhone remains manual.

### Added
- Optional `datacenter` and `country` per host in `hosts/hosts.json`; they are appended to mobile profile names (`Family VPN 1 - Hetzner FSN1, DE`, `Family VPN 1 XHTTP - Hetzner FSN1, DE`) and shown by `nix-status.sh`. Hosts without them keep the plain names. Tests validate the format.

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
