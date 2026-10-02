# AGENTS.md — instructions for Codex / AI agents

You are maintaining a small **private VPN** repository. The users are the owner and their parents. There is no commercial service, subscription backend, billing, public registration, or multi-tenant panel.

## Target outcome

Deploy the same VPN stack to **independent VPS hosts running NixOS** (currently one; each is an entry in `hosts/hosts.json`), preferably at different providers and ASNs, and generate simple mobile import profiles.

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

## Tests, documentation and cleanup

With every commit:
- Run `./tests/run.sh`.
- Update all documentation the change touches (`README.md`, `docs/`, `AGENTS.md`, `CLAUDE.md`, `CODEX_TASKS.md`) and add a `CHANGELOG.md` entry. Docs describe only what exists now; rewrite or delete outdated text.
- Delete what became unnecessary: scripts, tests, config options, env variables, doc sections, dead references. Git history is the archive; do not keep code "for reference".

`.githooks/pre-commit` enforces the tests, the changelog and docs for behaviour changes (`./scripts/install-hooks.sh` enables it); `tests/test_static.sh` fails on scripts that no document mentions and on docs that mention missing scripts. Do not bypass with `--no-verify`.

## Repository workflow

Work in this order:

1. Read `README.md`, `docs/install.md`, `CODEX_TASKS.md`, `.env.example`, and scripts before changing anything.
2. Check local prerequisites with `./scripts/preflight.sh` (Nix, xray, jq).
3. If `.env.local` does not exist, copy `.env.example` to `.env.local`.
4. Ask the user only for values that cannot be discovered locally: the server name (`<datacenter>-<country>-n-<number>`) and its address, the disk device, allowed SSH source addresses. Do not ask them to paste private keys.
5. Generate secrets locally using `./scripts/generate-secrets.sh`. This script writes secrets directly to `.env.local`, not to the output.
6. Validate with `./scripts/nix-validate.sh` (and `./tests/run.sh`).
7. Install one VPS at a time with `./scripts/nix-install.sh <host> root@<ip>`. **This erases the disk: get the user's explicit go-ahead for that host first.**
8. Send secrets with `./scripts/nix-push-secrets.sh <host> admin@<ip>`.
9. Verify with `./scripts/nix-check.sh`, `./scripts/nix-status.sh <host>` and `./scripts/nix-probe.sh <host>` before touching the next VPS.
10. Generate mobile profiles with `./scripts/make-mobile-profiles.sh` (and optionally `./scripts/make-android-auto-profile.sh`).
11. Tell the user exactly which QR files to import, but never print their VLESS URI contents.

Later changes: `./scripts/nix-validate.sh`, then `./scripts/nix-deploy.sh <host> admin@<ip>` one host at a time, then the checks from step 9.

## Server expectations

**NixOS is the target** (see `docs/install.md`, `docs/nixos.md`, `flake.nix`, `hosts/hosts.json`); use the `scripts/nix-*.sh` workflow. On NixOS the equivalents of the config-safety rules are: config rendered from the template at start and tested in `ExecStartPre`, secrets only in `/var/lib/vpn/xray.env` (never the Nix store), and generation rollback instead of manual backups.

Each VPS should have:
- Xray-core managed by systemd (on NixOS: the `xray` unit from `nix/xray.nix`).
- `443/tcp` open for universal VLESS/REALITY/Vision.
- `8443/tcp` open for Android XHTTP fallback.
- SSH open only to the source addresses in `hosts/ssh_allowed_ips` (NixOS firewall).
- No unnecessary listening services.

When changing firewall or SSH settings, never lock out SSH: `hosts/ssh_allowed_ips` must always contain the address the owner connects from, and a change to it needs the owner's go-ahead (recovery is only through the provider console).

## Validation checklist

Before declaring success, verify:
- `./scripts/nix-check.sh` passes on each VPS (xray `active`, config test passes at start, TCP 443 and 8443 listening, SSH policy as expected).
- `./scripts/nix-status.sh` exits 0 and `./scripts/nix-probe.sh` passes for each host.
- No private keys are present in git-tracked files.
- `git status --ignored` confirms `.env.local` and `build/` are ignored.
- Generated QR files exist locally.
- Android has universal profiles plus XHTTP fallbacks for every server (or the auto-failover config).
- iPhone has the universal profiles only.

## Client UX

For parents, favor simplicity over clever automatic balancing. Profile names come from the server names (`<datacenter>-<country>-n-<number>`, e.g. `aeza-de-n-1`), so the location is visible and manual fallback is obvious:
- `VPN aeza-de-n-1`
- `VPN aeza-de-n-1 XHTTP` (Android only)

Automatic failover exists as the optional Android-only `build/mobile/android-auto.json` (`scripts/make-android-auto-profile.sh`): a static client config with a health-checked balancer, no control plane or subscription service. Basic connectivity must keep working with the plain manual profiles; iPhone stays manual unless client support is verified.

## Changes to avoid unless explicitly requested

- Do not introduce Docker merely for Xray.
- Do not introduce Kubernetes.
- Do not add Nginx/Caddy unless there is a concrete reason.
- Do not add Cloudflare proxying to REALITY endpoints.
- Do not add a database.
- Do not add a web UI.
- Do not add a subscription server.
- Do not require a domain name; direct VPS IPs are acceptable for the VLESS connection while REALITY uses its configured server name.

## Final response expected from the agent

Keep the final report compact. State:
- which VPS hosts were deployed;
- whether both Xray services are healthy;
- where the generated QR codes are located;
- which QR codes go to Android and which to iPhone;
- any remaining manual action.

Never include UUIDs, private keys, short IDs, or full VLESS links in that report.
