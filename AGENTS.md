# AGENTS.md — instructions for Codex / AI agents

You are maintaining a small **private family VPN** repository. The users are the owner and their parents. There is no commercial service, subscription backend, billing, public registration, or multi-tenant panel.

## Target outcome

Deploy the same VPN stack to **two independent Ubuntu VPS hosts**, preferably at different providers and ASNs, and generate simple mobile import profiles.

Mobile clients:
- Android: **v2rayNG**.
- iPhone/iPad: **Streisand**.

Server transports:
- Primary/universal: `VLESS + REALITY + XTLS Vision` over RAW/TCP on `443/tcp`.
- Android fallback: `VLESS + XHTTP + REALITY` on `8443/tcp`.

The iOS setup should remain conservative: use the universal REALITY/Vision profiles unless current client compatibility has been explicitly verified.

## Non-negotiable safety rules

1. Never commit or upload `.env.local`, `build/`, generated QR codes, UUIDs, private REALITY keys, SSH private keys, or generated VLESS URIs.
2. Never paste secrets into AI/chat output. It is acceptable to say which local file contains them.
3. Never disable the host firewall or SSH security as a shortcut.
4. Do not expose an admin panel or subscription endpoint to the Internet.
5. Do not add telemetry, analytics, tracking, or third-party management services.
6. Do not replace an existing SSH configuration blindly. Preserve the user's working SSH access.
7. Never overwrite `/usr/local/etc/xray/config.json` until the new configuration validates successfully.
8. Before every server restart, run Xray's config test.
9. Keep deployment idempotent and reversible. Back up an existing Xray config before replacing it.
10. Do not invent current Xray syntax. If a schema/transport field fails validation, inspect the installed Xray version and current upstream documentation, then make the smallest compatible change.

## Tests and documentation

Run `./tests/run.sh` before committing. Every commit must update `CHANGELOG.md`, plus `README.md`/`docs/` when behaviour changes; `.githooks/pre-commit` enforces it (`./scripts/install-hooks.sh` enables it). Do not bypass with `--no-verify`.

## Repository workflow

Work in this order:

1. Read `README.md`, `CODEX_TASKS.md`, `.env.example`, and scripts before changing anything.
2. Check local prerequisites with `./scripts/preflight.sh`.
3. If `.env.local` does not exist, copy `.env.example` to `.env.local`.
4. Ask the user only for values that cannot be discovered locally, normally `VPS1_ADDR`, `VPS2_ADDR`, and SSH targets. Do not ask them to paste private keys.
5. Generate secrets locally using `./scripts/generate-secrets.sh`. This script must write secrets directly to `.env.local`, not print them.
6. Render configs with `./scripts/render.sh`.
7. Validate with `./scripts/validate.sh`.
8. Deploy one VPS at a time with `./scripts/deploy.sh`.
9. After each deployment, run `./scripts/check-server.sh` against that host before touching the second VPS.
10. Generate mobile profiles with `./scripts/make-mobile-profiles.sh`.
11. Tell the user exactly which QR files to import, but never print their VLESS URI contents.

## Server expectations

**NixOS is the primary target** (see `docs/nixos.md`, `flake.nix`, `hosts/hosts.json`); use the `scripts/nix-*.sh` workflow. Ubuntu 24.04 with `deploy.sh`/`check-server.sh` is the legacy path, used only if the user asks. On NixOS the equivalents of the config-safety rules are: config rendered from the template at start and tested in `ExecStartPre`, secrets only in `/var/lib/family-vpn/xray.env` (never the Nix store), and generation rollback instead of manual backups.

Each VPS should have:
- Xray-core managed by systemd (on NixOS: the `xray` unit from `nix/xray.nix`).
- `443/tcp` open for universal VLESS/REALITY/Vision.
- `8443/tcp` open for Android XHTTP fallback.
- SSH open only to the source addresses in `hosts/ssh_allowed_ips` (NixOS firewall).
- No unnecessary listening services.

When modifying firewall rules, first inspect whether the host uses UFW, nftables, iptables, a provider firewall, or a combination. Do not lock out SSH.

## Validation checklist

Before declaring success, verify:
- `xray run -test -config /usr/local/etc/xray/config.json` succeeds on each VPS.
- `systemctl is-active xray` returns `active`.
- TCP 443 and 8443 are listening.
- No private keys are present in git-tracked files.
- `git status --ignored` confirms `.env.local` and `build/` are ignored.
- Generated QR files exist locally.
- Android has two universal profiles plus two XHTTP fallbacks.
- iPhone has two universal profiles.

## Client UX

For parents, favor simplicity over clever automatic balancing. Give profiles names that make manual fallback obvious:
- `Family VPN 1`
- `Family VPN 2`
- `Family VPN 1 XHTTP` (Android only)
- `Family VPN 2 XHTTP` (Android only)

If automatic failover is later requested, implement it as an optional enhancement without making basic connectivity depend on a control plane or subscription service.

## Changes to avoid unless explicitly requested

- Do not introduce Docker merely for Xray.
- Do not introduce Kubernetes.
- Do not add Nginx/Caddy unless there is a concrete reason.
- Do not add Cloudflare proxying to REALITY endpoints.
- Do not add a database.
- Do not add a web UI.
- Do not add a subscription server.
- Do not require a domain name; direct VPS IPs are acceptable for the VLESS connection while REALITY uses its configured server name.

## Final response expected from Codex

Keep the final report compact. State:
- which VPS hosts were deployed;
- whether both Xray services are healthy;
- where the generated QR codes are located;
- which QR codes go to Android and which to iPhone;
- any remaining manual action.

Never include UUIDs, private keys, short IDs, or full VLESS links in that report.
