#!/usr/bin/env bash
# Sends this host's secrets from .env.local to /var/lib/family-vpn/xray.env, validates them, then (re)starts xray.
# Secrets travel over ssh stdin, never on a command line or in stdout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -eq 2 ]] || { echo "Usage: $0 <host-name> root@host" >&2; exit 1; }
name="$1"; target="$2"
jq -e --arg h "$name" 'has($h)' "$ROOT/hosts/hosts.json" >/dev/null || { echo "$name is not in hosts/hosts.json" >&2; exit 1; }
set -a; source "$ROOT/.env.local"; set +a
n="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
priv_v="${n}_REALITY_PRIVATE_KEY"; sid_v="${n}_SHORT_ID"
for v in VLESS_UUID REALITY_DEST REALITY_SERVER_NAME XHTTP_PATH "$priv_v" "$sid_v"; do
  [[ -n "${!v:-}" ]] || { echo "Missing $v in .env.local" >&2; exit 1; }
done
{
  printf 'VLESS_UUID=%s\n' "$VLESS_UUID"
  printf 'REALITY_PRIVATE_KEY=%s\n' "${!priv_v}"
  printf 'SHORT_ID=%s\n' "${!sid_v}"
  printf 'REALITY_DEST=%s\n' "$REALITY_DEST"
  printf 'REALITY_SERVER_NAME=%s\n' "$REALITY_SERVER_NAME"
  printf 'XHTTP_PATH=%s\n' "$XHTTP_PATH"
} | ssh "$target" 'umask 077; install -d -m 700 /var/lib/family-vpn; cat > /var/lib/family-vpn/xray.env.new'

ssh "$target" 'bash -s' <<'REMOTE'
set -euo pipefail
new=/var/lib/family-vpn/xray.env.new
cur=/var/lib/family-vpn/xray.env
# Ports come from the NixOS module; take them from the running unit definition.
ports="$(systemctl show xray -p Environment --value)"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
( set -a; . "$new"; for kv in $ports; do export "$kv"; done; set +a; xray-render "$tmp" ) || { echo 'New secrets failed the Xray config test; keeping the old ones.' >&2; rm -f "$new"; exit 1; }
[[ -f "$cur" ]] && cp -a "$cur" "$cur.bak.$(date +%Y%m%d%H%M%S)"
mv "$new" "$cur"
systemctl restart xray
systemctl is-active xray
REMOTE
echo "Secrets applied on $name. Next: ./scripts/nix-check.sh $target"
