#!/usr/bin/env bash
set -euo pipefail
missing=0
for cmd in xray ssh scp python3 openssl jq; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf 'ok      %s\n' "$cmd"
  else
    printf 'missing %s\n' "$cmd"
    missing=1
  fi
done
if command -v nix >/dev/null 2>&1; then
  printf 'ok      nix (NixOS workflow)\n'
else
  printf 'optional nix (needed for the NixOS scripts/nix-*.sh workflow)\n'
fi
if command -v qrencode >/dev/null 2>&1; then
  printf 'ok      qrencode\n'
else
  printf 'optional qrencode (needed only for PNG QR generation)\n'
fi
if [[ $missing -ne 0 ]]; then
  echo 'Install the missing required commands before continuing.' >&2
  exit 1
fi
xray version | sed -n '1,2p'
