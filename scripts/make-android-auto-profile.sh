#!/usr/bin/env bash
# Builds build/mobile/android-auto.json: ONE Xray client config for Android that health-checks every server
# and automatically sends new connections to the fastest live one (leastPing balancer + burstObservatory).
# Usage: make-android-auto-profile.sh [--with-xhttp]
#   --with-xhttp also adds the XHTTP outbounds (a different transport on 8443) to the pool.
# The file contains secrets (it is git-ignored under build/): hand it to the device over a private channel, never print it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
with_xhttp=0; [[ "${1:-}" == "--with-xhttp" ]] && with_xhttp=1
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 1; }
set -a; source "$ROOT/.env.local"; set +a
source "$ROOT/scripts/lib/client-outbound.sh"
AUTO_PROBE_URL="${AUTO_PROBE_URL:-https://www.gstatic.com/generate_204}"
OUT="$ROOT/build/mobile"; mkdir -p "$OUT"; chmod 700 "$ROOT/build" "$OUT" 2>/dev/null || true

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
first=""
while IFS= read -r host; do
  tag="vpn-$host-universal"; [[ -n "$first" ]] || first="$tag"
  vless_outbound "$host" universal "$tag" >> "$tmp"
  [[ $with_xhttp -eq 0 ]] || vless_outbound "$host" xhttp "vpn-$host-xhttp" >> "$tmp"
done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/hosts.json")

# Ports 10808/10809 are v2rayNG's defaults for its local SOCKS/HTTP inbounds.
FIRST="$first" PROBE="$AUTO_PROBE_URL" jq -n --slurpfile ob "$tmp" '{
  log: {loglevel: "warning"},
  dns: {servers: ["1.1.1.1", "8.8.8.8"]},
  inbounds: [
    {tag: "socks", listen: "127.0.0.1", port: 10808, protocol: "socks", settings: {udp: true}, sniffing: {enabled: true, destOverride: ["http", "tls"]}},
    {tag: "http", listen: "127.0.0.1", port: 10809, protocol: "http"}
  ],
  outbounds: ($ob + [{tag: "direct", protocol: "freedom"}]),
  burstObservatory: {
    subjectSelector: ["vpn-"],
    pingConfig: {destination: env.PROBE, interval: "10s", sampling: 2, timeout: "5s"}
  },
  routing: {
    domainStrategy: "AsIs",
    balancers: [{tag: "auto", selector: ["vpn-"], strategy: {type: "leastPing"}, fallbackTag: env.FIRST}],
    rules: [
      {type: "field", ip: ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16", "fc00::/7"], outboundTag: "direct"},
      {type: "field", network: "tcp,udp", balancerTag: "auto"}
    ]
  }
}' > "$OUT/android-auto.json"
chmod 600 "$OUT/android-auto.json"
if command -v xray >/dev/null; then
  xray run -test -format json -config "$OUT/android-auto.json" >/dev/null 2>&1 || { echo 'Generated config failed xray validation' >&2; rm -f "$OUT/android-auto.json"; exit 1; }
fi
[[ "$(jq '[.outbounds[] | select(.tag | startswith("vpn-"))] | length' "$OUT/android-auto.json")" -gt 1 ]] \
  || echo 'Note: only one server in the pool, so there is nothing to fail over to yet; add a second host to hosts/hosts.json.' >&2
echo "Wrote $OUT/android-auto.json ($(jq '[.outbounds[] | select(.tag | startswith("vpn-"))] | length' "$OUT/android-auto.json") servers in the pool). Import it in v2rayNG as a custom config."
