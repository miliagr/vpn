# CODEX_TASKS.md

This file is the operational checklist for an AI coding agent.

## Phase 1 — inspect, do not change servers yet

- Read `AGENTS.md` and `docs/install.md` completely.
- Run `git status` and inspect `.gitignore`.
- Run `./scripts/preflight.sh`.
- Check `.env.local` only for emptiness (for example `grep -q '^VLESS_UUID=.' .env.local`); never echo it to chat/output.
- Confirm every `VPSn_ADDR` is a real address, not one of the RFC 5737 examples (`203.0.113.0/24`, `198.51.100.0/24`, `192.0.2.0/24`). Stop if it is a placeholder.
- Confirm SSH access as root to each fresh VPS with a harmless command, and collect `lsblk`, `free -m`, `ip -4 addr`, `ip route`.
- Name each host `<datacenter>-<country>-n-<number>` (e.g. `aeza-de-n-1`) and set its `disk` in `hosts/hosts.json`; confirm `hosts/ssh_allowed_ips` and `hosts/authorized_keys`.

## Phase 2 — local secrets and validation

- If `.env.local` is missing: `cp .env.example .env.local`.
- Run `./scripts/generate-secrets.sh` if required fields are empty. Do not display `.env.local` afterwards.
- Run `./scripts/nix-validate.sh` and `./tests/run.sh`.
- If validation fails because of Xray/NixOS version drift, fix the code for the locally installed versions and validate again.

## Phase 3 — the first host

- Get the user's explicit go-ahead: the next step erases the disk.
- `./scripts/nix-install.sh <host> root@<ip>`, then `ssh-keygen -R <ip>`.
- `./scripts/nix-push-secrets.sh <host> admin@<ip>`.
- `./scripts/nix-check.sh admin@<ip>`, `./scripts/nix-status.sh <host>`, `./scripts/nix-probe.sh <host>`.
- Do not continue to another host unless all of them pass.

## Phase 4 — further hosts (optional)

- Only when the user adds another server: add it to `hosts/hosts.json` and `.env.local`, repeat Phase 3 for it. Keep hosts independent; no host may depend on another.

## Phase 5 — phone profiles

Run:

```bash
./scripts/make-mobile-profiles.sh
```

Expected output (one pair per host; shown for aeza-de-n-1):

```text
build/mobile/aeza-de-n-1-universal.png
build/mobile/aeza-de-n-1-xhttp-android.png
```

With two or more hosts, `./scripts/make-android-auto-profile.sh` also writes `build/mobile/android-auto.json` (secrets inside; never print it).

If `qrencode` is unavailable, install it locally or leave `.txt` profile files in place and report that PNG creation remains.

### Android / v2rayNG

Import, per host in `hosts/hosts.json` order: `<host>-universal.png`, then all `<host>-xhttp-android.png`.

### iPhone / Streisand

Import only the `<host>-universal.png` files.

## Phase 6 — smoke test

Ask the user to test from a Russian mobile/ISP network if available. A successful test should include:
- one universal profile through each host;
- Android XHTTP fallback if Android is available.

Do not treat a successful test from a non-Russian network as proof that the setup works through Russian filtering.

## Optional later improvement: per-person UUIDs

The initial repository intentionally uses a single UUID for simplicity. If the user asks for revocation per device/person, extend the Xray `clients` list and QR generation so the owner and each parent receive a distinct UUID. Keep the same server keys. Do not introduce a subscription backend just for this.
