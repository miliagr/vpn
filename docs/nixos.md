# NixOS deployment (primary)

Every server is a NixOS system described by this flake. Hosts are listed in `hosts/hosts.json`; the flake builds one `nixosConfigurations.<name>` per entry.

```text
flake.nix            hosts -> nixosConfigurations
hosts/hosts.json     host names, disk device, system (no IPs, no secrets)
hosts/authorized_keys  public SSH keys allowed as root (public, committed)
nix/common.nix       SSH (key-only), firewall, BBR, GC
nix/disk.nix         disko partitioning (BIOS+EFI GPT, ext4)
nix/xray.nix         Xray systemd unit; config rendered at start from server/xray-server.template.json
```

Secrets never enter git or the Nix store. `.env.local` holds them locally; `scripts/nix-push-secrets.sh` writes a per-host `/var/lib/family-vpn/xray.env` (root, 0600) over ssh. The unit renders and tests the config (`xray run -test`) in `ExecStartPre`, and stays skipped until that file exists.

## Local prerequisites
Nix with flakes (`curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install`), `xray`, `jq`, `qrencode`. Run `nix flake lock` once and commit `flake.lock`.

## First two servers
Provision two plain Ubuntu/Debian VPS with root SSH key access, set the real `disk` in `hosts/hosts.json`, then:

```bash
cp .env.example .env.local        # set VPS1_ADDR, VPS2_ADDR
./scripts/preflight.sh
./scripts/generate-secrets.sh
./scripts/nix-validate.sh

./scripts/nix-install.sh vps1 root@VPS1_IP      # ERASES the disk (asks for confirmation)
./scripts/nix-push-secrets.sh vps1 root@VPS1_IP
./scripts/nix-check.sh root@VPS1_IP
# only then repeat for vps2

./scripts/make-mobile-profiles.sh
```

## Day-2
- Config change: edit `nix/`, `./scripts/nix-validate.sh`, `./scripts/nix-deploy.sh <host> root@ip`, `./scripts/nix-check.sh`. Roll back with `ssh root@ip nixos-rebuild switch --rollback`.
- Rotate secrets: clear the fields in `.env.local`, rerun `generate-secrets.sh`, `nix-push-secrets.sh` per host, regenerate profiles and re-import QR codes.
- Update Xray: `nix flake update nixpkgs`, validate, deploy one host at a time.

## Add a third (Nth) server
1. Add `"vps3": {"disk": "...", "system": "x86_64-linux"}` to `hosts/hosts.json`.
2. Add `VPS3_ADDR=` to `.env.local`; run `generate-secrets.sh`.
3. `nix-validate.sh`, `nix-install.sh vps3 ...`, `nix-push-secrets.sh vps3 ...`, `nix-check.sh ...`.
4. `make-mobile-profiles.sh` emits `vps3-universal` and `vps3-xhttp-android` automatically ("Family VPN 3").

The Ubuntu scripts (`render/deploy/check-server/validate`) are the legacy path and still cover only vps1/vps2.

## Tests and commit policy

`./tests/run.sh` runs offline checks (syntax, placeholder/secret consistency, secret hygiene, script runs with a fake `xray` and a third host). `tests/test_nix.sh` evaluates every host and is skipped where Nix is absent, so run it once Nix is installed. `./scripts/install-hooks.sh` enables `.githooks/pre-commit`, which runs the tests and requires a `CHANGELOG.md` entry in every commit, plus docs when scripts/nix/server/hosts/tests change.
