#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nix >/dev/null || { echo 'nix is required (https://install.determinate.systems/)' >&2; exit 1; }
cd "$ROOT"
nix flake check --no-build
while IFS= read -r host; do
  echo "==> evaluating $host"
  nix eval --raw ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" >/dev/null
done < <(jq -r 'keys_unsorted[]' hosts/hosts.json)
echo 'All hosts evaluate.'
