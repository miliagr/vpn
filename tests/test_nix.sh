#!/usr/bin/env bash
# Evaluates every NixOS host. Skipped where Nix is not installed (e.g. this Mac before setup).
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
# Nix installed by the Determinate installer is often missing from non-login shells.
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
if ! command -v nix >/dev/null; then skip 'nix not installed: NixOS code is NOT evaluated by this run'; finish; fi
[[ -f flake.lock ]] || { fail 'flake.lock missing: run nix flake lock and commit it'; finish; }
check 'nix flake check' nix flake check --no-build
while IFS= read -r h; do
  check "evaluate $h" nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath"
done < <(jq -r 'keys_unsorted[]' hosts/hosts.json)
finish
