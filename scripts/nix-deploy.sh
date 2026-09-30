#!/usr/bin/env bash
# Apply the current flake to an already-installed host. NixOS keeps previous generations for rollback.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -eq 2 ]] || { echo "Usage: $0 <host-name> root@host" >&2; exit 1; }
name="$1"; target="$2"
command -v nix >/dev/null || { echo 'nix is required' >&2; exit 1; }
jq -e --arg h "$name" 'has($h)' "$ROOT/hosts/hosts.json" >/dev/null || { echo "$name is not in hosts/hosts.json" >&2; exit 1; }
cd "$ROOT"
nix run nixpkgs#nixos-rebuild -- switch --flake ".#$name" --target-host "$target" --build-host "$target"
echo "Next: ./scripts/nix-check.sh $target   (rollback: ssh $target nixos-rebuild switch --rollback)"
