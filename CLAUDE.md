# CLAUDE.md

Private family VPN: the same Xray stack (VLESS + REALITY) deployed to independent VPS hosts, declared as NixOS systems (`flake.nix`, `hosts/hosts.json`; start with two, add more by adding an entry), plus generated mobile import profiles (QR codes). No panel, database, subscription server, or Docker.

@AGENTS.md
@CODEX_TASKS.md

The two files above are the source of truth for architecture, safety rules, and the phased deployment checklist. Everything below is Claude-specific addition; if it conflicts with them, they win.

## Layout

- `server/xray-server.template.json` — the only Xray config template. Placeholders look like `__VLESS_UUID__` and are substituted by `scripts/render.sh` via `sed`.
- `flake.nix`, `nix/`, `hosts/` — NixOS definition (primary). See `docs/nixos.md`. Adding a host = a `hosts/hosts.json` entry + `<NAME>_ADDR` in `.env.local`.
- `scripts/` — plain bash (`set -euo pipefail`). NixOS run order: `preflight` → `generate-secrets` → `nix-validate` → `nix-install <host> <ssh>` (ERASES disk) → `nix-push-secrets` → `nix-check` → `make-mobile-profiles`; later changes via `nix-deploy`; monitoring via `nix-status` (health, online, load; exit 1 on problems), `nix-probe` (real end-to-end tunnel) and `nix-history`. After install root SSH is disabled: use `admin@ip`, never `root@ip`, except for `nix-install`. `render`/`validate`/`deploy`/`check-server` are the legacy Ubuntu path (vps1/vps2 only).
- `.env.local` (git-ignored, mode 600) — all secrets and per-VPS values. Template: `.env.example`.
- `build/` (git-ignored) — rendered server configs and `build/mobile/*.txt|png` (contain VLESS URIs).
- `docs/amneziawg.md` — optional manual fallback notes only, not part of the automated flow.

Tests: `./tests/run.sh` (static checks, secret hygiene, script runs against a fake `xray` with a third host; `tests/test_nix.sh` evaluates the flake only if Nix is installed and otherwise prints a skip, so a green run without Nix does not prove the Nix code). Live verification is `./scripts/nix-check.sh` on each VPS (legacy: `validate.sh`, `check-server.sh`).

## Working rules for Claude

- **Never read `.env.local` or anything in `build/`** (no `cat`, `Read`, `grep`, `source`-and-echo). To check whether a value is set, test emptiness without printing it, e.g. `grep -q '^VLESS_UUID=.' .env.local`. Do the same for generated `.txt` profiles: check existence with `ls`, never contents.
- Don't run commands whose output would include secrets (`xray x25519`, `xray uuid`, `env`, `set`, `cat build/...`). Scripts that handle secrets must write them to files, not stdout.
- Any script change must keep the existing guarantees: validate before replacing `/usr/local/etc/xray/config.json`, back up the old config, run `xray run -test` before every restart, and stay idempotent. Keep `check-server.sh` log output UUID-redacted.
- Adding a template placeholder requires three edits together: `.env.example`, the `need=(...)` list and `sed` line in `render.sh`, and (if it affects clients) `make-mobile-profiles.sh`.
- Keep the server template free of invented syntax. It currently uses `"network": "raw"` and `"target"` (current Xray naming); if `xray run -test` rejects a field, check the installed version (`./scripts/preflight.sh`) and upstream docs before changing anything.
- `nix-install.sh` wipes the target disk; never run it, or `nix-deploy`/`nix-push-secrets`, without explicit go-ahead for that host. `nix` may not be installed locally; if so, say the Nix code is unevaluated rather than claiming it works.
- Deployment touches real remote servers and is hard to reverse: do not run `deploy.sh` or SSH commands against a VPS without the user's explicit go-ahead for that specific host, and do VPS1 fully (deploy + check) before VPS2.
- Refuse to deploy while `VPS*_ADDR` are RFC 5737 placeholders (`203.0.113.*`, `198.51.100.*`, `192.0.2.*`); `render.sh` already enforces this.
- Stay within scope: no new services, UI, telemetry, or control plane (see "Changes to avoid" in AGENTS.md).

## Security invariants (do not weaken without asking)
- Inbound: 443 and 8443 TCP for everyone; SSH (22) only from `hosts/ssh_allowed_ips`. Never open 22 globally, and never empty that list (it would lock everyone out). Deploying a change to it needs the user's go-ahead, because a wrong address locks them out until they use the provider console. Monitoring (node_exporter 9100, Xray metrics 11111) stays on 127.0.0.1; never open it in the firewall or set `openFirewall = true`.
- The Xray routing rule blackholing private/loopback ranges must stay, otherwise VPN clients can reach those localhost ports.
- No root SSH login, no passwords, no access logs, no third-party monitoring/alerting service. `tests/test_nix.sh` asserts these.

## Tests and documentation (every commit)

- Run `./tests/run.sh` before proposing a commit; add or extend a test for each behaviour change in `scripts/`, `nix/`, `server/`, or `hosts/`. Tests must never touch real servers or read `.env.local`.
- Every commit updates `CHANGELOG.md` (under "Unreleased"), and changes to scripts/nix/server/hosts/tests also update `README.md`, `docs/`, `AGENTS.md`, or `CLAUDE.md`. `.githooks/pre-commit` enforces this and runs the tests; enable with `./scripts/install-hooks.sh`. Never bypass it with `--no-verify`.

## Reporting

Final reports are compact: which hosts were deployed, health of both Xray services, QR file locations (Android: all four; iPhone: the two `*-universal.png` only), remaining manual steps. Never include UUIDs, keys, short IDs, or VLESS links. Respond to the user in Russian unless they write in English.
