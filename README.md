# Family VPN — Codex-ready deployment

A small private VPN setup for the owner and parents. It deliberately has **no subscription service, panel, database, billing, or public user management**.

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
             on VPS1 and VPS2
```

Use two VPS hosts at different providers/ASNs when practical.

## Recommended way to use this repository with Codex

Open the repository folder in Codex and paste **only this prompt**:

```text
Read AGENTS.md and CODEX_TASKS.md completely and follow them.
Prepare and deploy this private family VPN to my two VPS hosts.
Keep all secrets local and never print UUIDs, REALITY private keys, short IDs, or VLESS URIs in chat.
Use the existing scripts where possible, improve them if validation requires it, and verify each VPS before moving to the next one.
At the end tell me only which QR files to import into v2rayNG on Android and Streisand on iPhone.
```

Codex should then work through the repository checklist rather than improvising the architecture.

## What you need to provide locally

Copy the environment template:

```bash
cp .env.example .env.local
```

Edit only the VPS addresses initially:

```dotenv
VPS1_ADDR=<first-vps-ip-or-hostname>
VPS2_ADDR=<second-vps-ip-or-hostname>
```

Do **not** send `.env.local` to anyone or commit it.

## Local prerequisites on macOS

The preflight script checks them:

```bash
./scripts/preflight.sh
```

Typical installation:

```bash
brew install xray jq qrencode
```

OpenSSH, Python 3, OpenSSL and `scp` are normally already present on macOS.

## Manual workflow without Codex

```bash
cp .env.example .env.local
# edit VPS1_ADDR and VPS2_ADDR

./scripts/preflight.sh
./scripts/generate-secrets.sh
./scripts/render.sh
./scripts/validate.sh

./scripts/deploy.sh vps1 root@VPS1_IP
./scripts/check-server.sh root@VPS1_IP

./scripts/deploy.sh vps2 root@VPS2_IP
./scripts/check-server.sh root@VPS2_IP

./scripts/make-mobile-profiles.sh
```

## Generated mobile files

```text
build/mobile/vps1-universal.png
build/mobile/vps2-universal.png
build/mobile/vps1-xhttp-android.png
build/mobile/vps2-xhttp-android.png
```

### Android / v2rayNG

Import all four QR codes. Use `Family VPN 1` normally, `Family VPN 2` if the first server is unreachable, and XHTTP profiles as additional fallbacks.

### iPhone / Streisand

Import only the two universal QR codes. Start with `Family VPN 1`; switch to `Family VPN 2` if needed.

## Security model

Secrets live only in `.env.local` and generated `build/` files. Both are ignored by git. Server deployment validates the new Xray config before replacing an existing config and creates a backup when applicable.

The default template uses one family VLESS UUID. For just a few trusted family devices this is intentionally simple. Per-person UUIDs can be added later without changing the overall architecture.

## NixOS (primary)

Servers are declared as NixOS systems: **[docs/install.md](docs/install.md)** is the step-by-step installation guide, [docs/nixos.md](docs/nixos.md) the design, security and monitoring reference. The Ubuntu workflow above is the legacy path.

## Tests and contributing

```bash
./scripts/install-hooks.sh   # once
./tests/run.sh
```

Every commit updates `CHANGELOG.md`; the pre-commit hook enforces it.
