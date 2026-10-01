# Installing a server (NixOS)

Step-by-step for putting a fresh VPS under this repository's control. The same steps work for every host listed in `hosts/hosts.json`; do **one server at a time** and verify it before touching the next. Background and design: [nixos.md](nixos.md).

> Installing **erases the whole disk** of the target VPS. Run it only against a server you just rented or one whose data you do not need.

## 0. What you need

**On your Mac**
- Nix with flakes, `xray`, `jq`, `qrencode`, `ssh`:
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
  brew install xray jq qrencode
  ```
  If `nix` is not found in a new shell: `export PATH=$PATH:/nix/var/nix/profiles/default/bin`.
- You must run the scripts from an address listed in `hosts/ssh_allowed_ips` (the installed server accepts SSH from nowhere else).

**The VPS**
- Full virtualization (KVM), x86_64, public IPv4.
- RAM: at least 1 GB for the installer (nixos-anywhere requirement, excluding swap); 2 GB is comfortable. A "1 GB" plan often shows slightly under 1000 MB in `free -m`, which may be too little.
- Disk: 15-20 GB or more.
- A fresh Ubuntu/Debian image with **root login by SSH key** from your Mac. If the provider only gives a password, install your key first: `ssh-copy-id root@SERVER_IP`.
- Ports 443 and 8443 not blocked by a provider-side firewall.
- Access to the provider's web console (VNC) as a safety net.

## 1. Inspect the server

```bash
ssh root@SERVER_IP 'lsblk; free -m; ip -4 addr; ip route'
```

Check:
- **Disk name** (`lsblk`): `vda`, `sda` or `nvme0n1`. Put it in `hosts/hosts.json` as `"disk": "/dev/<name>"`. A wrong name stops the install at partitioning.
- **Memory** (`free -m`): see above.
- **Network** (`ip addr`, `ip route`): the installed system asks for an address by DHCP. If the provider gives a **static** address, IPv6-only, or a non-standard gateway, the server can boot without network; add static network settings before installing.
- **Reachability of the REALITY target** from this server: it must answer over TLS 1.3 with HTTP/2:
  ```bash
  ssh root@SERVER_IP 'echo | openssl s_client -connect TARGET:443 -servername TARGET -tls1_3 -alpn h2 2>/dev/null | grep -E "Protocol|ALPN"'
  ```
  Expect `TLSv1.3` and `h2`. `TARGET` is `REALITY_SERVER_NAME` in `.env.local`.

## 2. Describe the server in the repository

1. `.env.local` (git-ignored; `cp .env.example .env.local` if missing): set `VPS1_ADDR` (or `VPSn_ADDR`) to the server's IP.
2. `hosts/hosts.json`: set `disk`, and optionally `datacenter` and `country`; they become part of the profile names (`Family VPN 1 - Hetzner FSN1, DE`):
   ```json
   "vps1": {"disk": "/dev/vda", "system": "x86_64-linux", "datacenter": "Hetzner FSN1", "country": "DE"}
   ```
3. `hosts/authorized_keys` must contain the public key you will log in with; `hosts/ssh_allowed_ips` the address(es) you will log in from. Both are checked at build time (an empty list refuses to build, so you cannot lock everyone out by accident).
4. Commit the changes (the pre-commit hook runs the tests and requires a `CHANGELOG.md` entry and docs; see [nixos.md](nixos.md#tests-and-commit-policy)).

## 3. Secrets and validation (local)

```bash
./scripts/preflight.sh            # tools present
./scripts/generate-secrets.sh     # fills empty UUID/keys/short IDs in .env.local; prints nothing
./scripts/nix-validate.sh         # every host evaluates
./tests/run.sh                    # optional full check
```
Back up `.env.local` (password manager). Losing it means new keys and re-importing every client profile.

## 4. Install (erases the disk)

```bash
./scripts/nix-install.sh vps1 root@SERVER_IP
```
You must type the host name to confirm. nixos-anywhere then:
1. logs in as root and boots a small NixOS installer into RAM (`kexec`);
2. partitions the disk as described in `nix/disk.nix` (BIOS-boot + EFI + ext4);
3. installs the system from this flake and reboots.

It takes several minutes; the SSH connection drops during the reboot. Afterwards:
- the server's SSH host key changed: `ssh-keygen -R SERVER_IP`;
- **root login is disabled**; log in as `admin`, from an allowed address only: `ssh admin@SERVER_IP`.

Xray is installed but does not start yet; it waits for its secrets.

## 5. Send the secrets and start Xray

```bash
./scripts/nix-push-secrets.sh vps1 admin@SERVER_IP
```
This copies the host's secrets from `.env.local` to `/var/lib/family-vpn/xray.env` (root-only, never in git or the Nix store), renders the config, runs `xray run -test`, and only then restarts Xray. A bad value keeps the previous file.

## 6. Verify

```bash
./scripts/nix-check.sh admin@SERVER_IP    # system, xray active, ports 443/8443 listening, SSH policy
./scripts/nix-status.sh vps1              # health summary; exit code 1 on any problem
./scripts/nix-probe.sh vps1               # real tunnel from your Mac (universal and XHTTP)
```
All three must pass before you continue. A passing probe from outside Russia says nothing about reachability through Russian filtering: test from a Russian mobile network too.

## 7. The second server, then phone profiles

Repeat steps 1-6 for `vps2` (`./scripts/nix-install.sh vps2 root@IP2`, and so on). Then:

```bash
./scripts/make-mobile-profiles.sh          # QR codes in build/mobile/
./scripts/make-android-auto-profile.sh     # optional: Android auto-failover config
```
- Android (v2rayNG): all four QR codes (`vps*-universal.png`, `vps*-xhttp-android.png`), or the auto-failover config.
- iPhone (Streisand): only the two `vps*-universal.png`.

Never paste QR contents, VLESS links or the auto-failover JSON into chats or tickets.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `nix-install.sh` stops at partitioning | Wrong `disk` in `hosts/hosts.json`; check `lsblk` and retry. |
| Installer fails or hangs early | Not enough RAM for `kexec` (< 1 GB) or no `kexec` support; use a larger plan or install NixOS from the provider's ISO and continue from step 5. |
| After the reboot the server never answers | Network did not come up (static address, IPv6-only). Open the provider console, look at `ip a`, fix the network configuration, redeploy. Reinstalling the provider image and trying again is also fine. |
| `Permission denied (publickey)` as `admin` | Your key is not in `hosts/authorized_keys`, or you are not connecting from an allowed address. Fix the repository and redeploy via the console or reinstall. |
| SSH times out but VPN works | Your current IP is not in `hosts/ssh_allowed_ips`. Use the provider console to fix it (see [nixos.md](nixos.md#changing-the-allowed-ssh-address)). |
| `nix-push-secrets.sh`: "failed the Xray config test" | A value in `.env.local` is wrong or empty (for example an unreachable `REALITY_DEST` format). The old secrets stay in place; fix and rerun. |
| `nix-check.sh` shows xray `inactive` | Secrets not pushed yet (step 5), or see `ssh admin@IP sudo journalctl -u xray -n 50`. |
| Probe fails but the server looks healthy | A provider firewall blocks 443/8443, or the REALITY target is unreachable from the server (step 1). |

To redo an install, just run `nix-install.sh` again; it wipes and reinstalls. To roll back a bad change on a running server: `ssh admin@IP sudo nixos-rebuild switch --rollback`.

## Status of this guide

The Nix configuration, the Xray template and the scripts are covered by tests ([nixos.md](nixos.md#tests-and-commit-policy)), but the full install has not yet been run against a real VPS. The first real run may surface provider-specific issues (disk names, network setup); fix them in the repository and note them here.
