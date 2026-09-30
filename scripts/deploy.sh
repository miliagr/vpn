#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -eq 2 ]] || { echo "Usage: $0 vps1|vps2 user@host" >&2; exit 1; }
name="$1"; host="$2"
[[ "$name" == vps1 || "$name" == vps2 ]] || { echo 'first arg must be vps1 or vps2' >&2; exit 1; }
file="$ROOT/build/server-${name}.json"
[[ -f "$file" ]] || { echo "$file not found; run ./scripts/render.sh" >&2; exit 1; }

scp "$file" "$host:/tmp/xray-config.new.json"
ssh "$host" 'bash -s' <<'REMOTE'
set -euo pipefail
if ! command -v xray >/dev/null 2>&1; then
  apt-get update
  apt-get install -y curl unzip ca-certificates
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi
install -d -m 755 /usr/local/etc/xray
xray run -test -config /tmp/xray-config.new.json
if [[ -f /usr/local/etc/xray/config.json ]]; then
  cp -a /usr/local/etc/xray/config.json "/usr/local/etc/xray/config.json.bak.$(date +%Y%m%d%H%M%S)"
fi
install -m 600 /tmp/xray-config.new.json /usr/local/etc/xray/config.json
rm -f /tmp/xray-config.new.json
systemctl enable xray >/dev/null
systemctl restart xray
systemctl is-active --quiet xray
xray run -test -config /usr/local/etc/xray/config.json
ss -lnt | awk 'NR==1 || /:443[[:space:]]|:8443[[:space:]]/'
REMOTE
