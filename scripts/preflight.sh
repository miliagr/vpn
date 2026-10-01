#!/usr/bin/env bash
set -euo pipefail
missing=0
for cmd in nix xray ssh python3 openssl jq curl; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf 'ok      %s\n' "$cmd"
  else
    printf 'missing %s\n' "$cmd"
    missing=1
  fi
done
if command -v qrencode >/dev/null 2>&1; then
  printf 'ok      qrencode\n'
else
  printf 'optional qrencode (needed only for PNG QR generation)\n'
fi
if [[ $missing -ne 0 ]]; then
  echo 'Install the missing required commands before continuing (Nix: see docs/install.md; if it is installed but not found, run: export PATH=$PATH:/nix/var/nix/profiles/default/bin).' >&2
  exit 1
fi
xray version | sed -n '1,2p'
