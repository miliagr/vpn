# CODEX_TASKS.md

This file is the operational checklist for an AI coding agent.

## Phase 1 — inspect, do not change servers yet

- Read `AGENTS.md` and `docs/install.md` completely.
- Run `git status` and inspect `.gitignore`.
- Run `./scripts/preflight.sh`.
- Check `.env.local` only for emptiness (for example `grep -q '^VLESS_UUID=.' .env.local`); never echo it to chat/output.
- Confirm every `VPSn_ADDR` is a real address, not one of the RFC 5737 examples (`203.0.113.0/24`, `198.51.100.0/24`, `192.0.2.0/24`). Stop if it is a placeholder.
- Confirm SSH access as root to each fresh VPS with a harmless command, and collect `lsblk`, `free -m`, `ip -4 addr`, `ip route`.
- Set `disk` (and optional `datacenter`/`country`) for each host in `hosts/hosts.json`; confirm `hosts/ssh_allowed_ips` and `hosts/authorized_keys`.

## Phase 2 — local secrets and validation

- If `.env.local` is missing: `cp .env.example .env.local`.
- Run `./scripts/generate-secrets.sh` if required fields are empty. Do not display `.env.local` afterwards.
- Run `./scripts/nix-validate.sh` and `./tests/run.sh`.
- If validation fails because of Xray/NixOS version drift, fix the code for the locally installed versions and validate again.

## Phase 3 — VPS1

- Get the user's explicit go-ahead: the next step erases the disk.
- `./scripts/nix-install.sh vps1 root@<ip>`, then `ssh-keygen -R <ip>`.
- `./scripts/nix-push-secrets.sh vps1 admin@<ip>`.
- `./scripts/nix-check.sh admin@<ip>`, `./scripts/nix-status.sh vps1`, `./scripts/nix-probe.sh vps1`.
- Do not continue to VPS2 unless all of them pass.

## Phase 4 — VPS2 (and any further host)

- Repeat Phase 3 for the next host. Keep hosts independent; no host may depend on another.

## Phase 5 — phone profiles

Run:

```bash
./scripts/make-mobile-profiles.sh
```

Expected output (one pair per host):

```text
build/mobile/vps1-universal.png
build/mobile/vps2-universal.png
build/mobile/vps1-xhttp-android.png
build/mobile/vps2-xhttp-android.png
```

Optionally `./scripts/make-android-auto-profile.sh` writes `build/mobile/android-auto.json` (secrets inside; never print it).

If `qrencode` is unavailable, install it locally or leave `.txt` profile files in place and report that PNG creation remains.

### Android / v2rayNG

Import in this order:
1. `vps1-universal.png`
2. `vps2-universal.png`
3. `vps1-xhttp-android.png`
4. `vps2-xhttp-android.png`

### iPhone / Streisand

Import only:
1. `vps1-universal.png`
2. `vps2-universal.png`

## Phase 6 — smoke test

Ask the user to test from a Russian mobile/ISP network if available. A successful test should include:
- one universal profile through VPS1;
- one universal profile through VPS2;
- Android XHTTP fallback if Android is available.

Do not treat a successful test from a non-Russian network as proof that the setup works through Russian filtering.

## Optional later improvement: per-person UUIDs

The initial repository intentionally uses a single family UUID for simplicity. If the user asks for revocation per device/person, extend the Xray `clients` list and QR generation so the owner and each parent receive a distinct UUID. Keep the same server keys. Do not introduce a subscription backend just for this.
