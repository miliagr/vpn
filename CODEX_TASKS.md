# CODEX_TASKS.md

This file is the operational checklist for an AI coding agent.

## Phase 1 — inspect, do not change servers yet

- Read `AGENTS.md` completely.
- Run `git status` and inspect `.gitignore`.
- Run `./scripts/preflight.sh`.
- Inspect `.env.local` if it exists, but never echo it to chat/output.
- Confirm both VPS addresses are non-placeholder values.
- Confirm SSH access to VPS1 and VPS2 with a harmless command such as `uname -a`.

Stop deployment if either address is still one of the RFC 5737 examples (`203.0.113.0/24`, `198.51.100.0/24`, `192.0.2.0/24`).

## Phase 2 — local secrets and rendering

- If `.env.local` is missing: `cp .env.example .env.local`.
- Run `./scripts/generate-secrets.sh` if required fields are empty.
- Do not display `.env.local` after generation.
- Run `./scripts/render.sh`.
- Run `./scripts/validate.sh`.
- If validation fails because of Xray version/schema drift, fix the template for the locally installed current Xray version and validate again.

## Phase 3 — VPS1

- Inspect OS and existing firewall before changing it.
- Deploy with `./scripts/deploy.sh vps1 <ssh-target>`.
- Run `./scripts/check-server.sh <ssh-target>`.
- Do not continue to VPS2 unless VPS1 passes config test, service status, and listening-port checks.

## Phase 4 — VPS2

- Repeat the same process for VPS2.
- Keep VPS2 independent from VPS1; do not make either server depend on the other.

## Phase 5 — phone profiles

Run:

```bash
./scripts/make-mobile-profiles.sh
```

Expected output:

```text
build/mobile/vps1-universal.png
build/mobile/vps2-universal.png
build/mobile/vps1-xhttp-android.png
build/mobile/vps2-xhttp-android.png
```

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
