#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$ROOT/.env.local"; set +a
OUT="$ROOT/build/mobile"; mkdir -p "$OUT"
enc() { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }
make_universal() {
  local addr="$1" pub="$2" sid="$3" name="$4"
  printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s\n' \
    "$VLESS_UUID" "$addr" "$UNIVERSAL_PORT" "$(enc "$REALITY_SERVER_NAME")" "$pub" "$sid" "$(enc "$name")"
}
make_xhttp() {
  local addr="$1" pub="$2" sid="$3" name="$4"
  printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=xhttp&path=%s&mode=auto#%s\n' \
    "$VLESS_UUID" "$addr" "$XHTTP_PORT" "$(enc "$REALITY_SERVER_NAME")" "$pub" "$sid" "$(enc "$XHTTP_PATH")" "$(enc "$name")"
}
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 1; }
i=0
while IFS= read -r host; do
  i=$((i+1))
  n="$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]')"
  addr_v="${n}_ADDR"; pub_v="${n}_REALITY_PUBLIC_KEY"; sid_v="${n}_SHORT_ID"
  for v in "$addr_v" "$pub_v" "$sid_v"; do [[ -n "${!v:-}" ]] || { echo "Missing $v in .env.local" >&2; exit 1; }; done
  make_universal "${!addr_v}" "${!pub_v}" "${!sid_v}" "Family VPN $i" > "$OUT/$host-universal.txt"
  make_xhttp "${!addr_v}" "${!pub_v}" "${!sid_v}" "Family VPN $i XHTTP" > "$OUT/$host-xhttp-android.txt"
done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/hosts.json")
if command -v qrencode >/dev/null; then
  for f in "$OUT"/*.txt; do qrencode -o "${f%.txt}.png" < "$f"; done
  echo "QR images written to $OUT"
else
  echo "Profiles written to $OUT (install qrencode to generate PNG QR codes)"
fi
