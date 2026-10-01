#!/usr/bin/env bash
# First install of a brand-new VPS with nixos-anywhere. DESTROYS everything on the target disk.
# Extra arguments go to nixos-anywhere, e.g. --kexec-extra-flags "--kexec-syscall" or --debug (see docs/install.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 2 ]] || { echo "Usage: $0 <host-name-from-hosts.json> root@ip [extra nixos-anywhere options]" >&2; exit 1; }
name="$1"; target="$2"; extra=("${@:3}")
source "$ROOT/scripts/lib/guards.sh"; refuse_placeholder "$target" || exit 1
command -v nix >/dev/null || { echo 'nix is required' >&2; exit 1; }
jq -e --arg h "$name" 'has($h)' "$ROOT/hosts/hosts.json" >/dev/null || { echo "$name is not in hosts/hosts.json" >&2; exit 1; }
disk="$(jq -r --arg h "$name" '.[$h].disk' "$ROOT/hosts/hosts.json")"
echo "This will ERASE $disk on $target and install NixOS as '$name'."
read -r -p "Type the host name ($name) to continue: " answer
[[ "$answer" == "$name" ]] || { echo 'Aborted.' >&2; exit 1; }
cd "$ROOT"
nix run github:nix-community/nixos-anywhere -- --flake ".#$name" --target-host "$target" ${extra[@]+"${extra[@]}"}
echo "Installed. The host key changed: remove the old entry with ssh-keygen -R <host>."
echo "Root SSH login is now disabled; use the admin user from here on."
echo "Next: ./scripts/nix-push-secrets.sh $name admin@${target#*@}"
