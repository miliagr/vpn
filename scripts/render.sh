#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV="$ROOT/.env.local"
[[ -f "$ENV" ]] || { echo "Missing $ENV" >&2; exit 1; }
set -a; source "$ENV"; set +a
mkdir -p "$ROOT/build"
need=(VPS1_ADDR VPS2_ADDR VLESS_UUID REALITY_DEST REALITY_SERVER_NAME VPS1_REALITY_PRIVATE_KEY VPS1_REALITY_PUBLIC_KEY VPS1_SHORT_ID VPS2_REALITY_PRIVATE_KEY VPS2_REALITY_PUBLIC_KEY VPS2_SHORT_ID UNIVERSAL_PORT XHTTP_PORT XHTTP_PATH)
for n in "${need[@]}"; do [[ -n "${!n:-}" ]] || { echo "Missing $n" >&2; exit 1; }; done
for addr in "$VPS1_ADDR" "$VPS2_ADDR"; do
  case "$addr" in
    203.0.113.*|198.51.100.*|192.0.2.*) echo "Refusing documentation/test address: $addr" >&2; exit 1;;
  esac
done
render_one() {
  local name="$1" priv="$2" sid="$3" out="$4"
  sed \
    -e "s|__UNIVERSAL_PORT__|$UNIVERSAL_PORT|g" \
    -e "s|__XHTTP_PORT__|$XHTTP_PORT|g" \
    -e "s|__VLESS_UUID__|$VLESS_UUID|g" \
    -e "s|__REALITY_DEST__|$REALITY_DEST|g" \
    -e "s|__REALITY_SERVER_NAME__|$REALITY_SERVER_NAME|g" \
    -e "s|__REALITY_PRIVATE_KEY__|$priv|g" \
    -e "s|__SHORT_ID__|$sid|g" \
    -e "s|__XHTTP_PATH__|$XHTTP_PATH|g" \
    "$ROOT/server/xray-server.template.json" > "$out"
}
render_one vps1 "$VPS1_REALITY_PRIVATE_KEY" "$VPS1_SHORT_ID" "$ROOT/build/server-vps1.json"
render_one vps2 "$VPS2_REALITY_PRIVATE_KEY" "$VPS2_SHORT_ID" "$ROOT/build/server-vps2.json"
echo "Rendered build/server-vps1.json and build/server-vps2.json"
