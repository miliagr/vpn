#!/usr/bin/env bash
# Apply the current flake to an already-installed host. NixOS keeps previous generations for rollback.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -eq 2 ]] || { echo "Usage: $0 <host-name> admin@host (root SSH login is disabled after install)" >&2; exit 1; }
name="$1"; target="$2"
command -v nix >/dev/null || { echo 'nix is required' >&2; exit 1; }
jq -e --arg h "$name" 'has($h)' "$ROOT/hosts/hosts.json" >/dev/null || { echo "$name is not in hosts/hosts.json" >&2; exit 1; }
cd "$ROOT"
nix run nixpkgs#nixos-rebuild -- switch --flake ".#$name" --target-host "$target" --build-host "$target" --elevate sudo
echo "Next: ./scripts/nix-check.sh $target   (rollback: ssh $target sudo nixos-rebuild switch --rollback)"
