#!/usr/bin/env bash
# End-to-end availability: from THIS machine, open a real VLESS+REALITY tunnel to each host/transport
# with a throwaway local xray client and fetch a 204 page through it. Exit 1 if any tunnel fails.
# Usage: nix-probe.sh [host-name...]
# A pass from outside Russia says nothing about reachability through Russian filtering.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for c in xray jq curl python3; do command -v "$c" >/dev/null || { echo "$c is required" >&2; exit 1; }; done
set -a; source "$ROOT/.env.local"; set +a
PROBE_URL="${PROBE_URL:-https://www.gstatic.com/generate_204}"
PROBE_EXPECT="${PROBE_EXPECT:-204}"
if [[ $# -gt 0 ]]; then hosts=("$@"); else hosts=(); while IFS= read -r h; do hosts+=("$h"); done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/hosts.json"); fi

WORK="$(mktemp -d)"; chmod 700 "$WORK"
XPID=""
cleanup() { [[ -n "$XPID" ]] && kill "$XPID" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

probe() {
  local host="$1" transport="$2" n addr_v pub_v sid_v socks cfg="$WORK/client.json"
  n="$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]')"; addr_v="${n}_ADDR"; pub_v="${n}_REALITY_PUBLIC_KEY"; sid_v="${n}_SHORT_ID"
  for v in "$addr_v" "$pub_v" "$sid_v"; do [[ -n "${!v:-}" ]] || { echo "$host: missing $v" >&2; return 1; }; done
  socks="$(free_port)"
  # Secrets go through the environment, not argv.
  P_SOCKS="$socks" P_ADDR="${!addr_v}" P_PUB="${!pub_v}" P_SID="${!sid_v}" P_TRANSPORT="$transport" \
  P_UUID="$VLESS_UUID" P_SNI="$REALITY_SERVER_NAME" P_UPORT="$UNIVERSAL_PORT" P_XPORT="$XHTTP_PORT" P_XPATH="$XHTTP_PATH" \
  jq -n '
    (env.P_TRANSPORT == "xhttp") as $x
    | {
      log: {loglevel: "error"},
      inbounds: [{listen: "127.0.0.1", port: (env.P_SOCKS | tonumber), protocol: "socks", settings: {udp: false}}],
      outbounds: [{
        protocol: "vless",
        settings: ({
          address: env.P_ADDR,
          port: ((if $x then env.P_XPORT else env.P_UPORT end) | tonumber),
          id: env.P_UUID,
          encryption: "none"
        } + (if $x then {} else {flow: "xtls-rprx-vision"} end)),
        streamSettings: ({
          network: (if $x then "xhttp" else "raw" end),
          security: "reality",
          realitySettings: {serverName: env.P_SNI, fingerprint: "chrome", publicKey: env.P_PUB, shortId: env.P_SID, spiderX: ""}
        } + (if $x then {xhttpSettings: {path: env.P_XPATH, mode: "auto"}} else {} end))
      }]
    }' > "$cfg"
  chmod 600 "$cfg"
  xray run -test -format json -config "$cfg" >/dev/null 2>&1 || { echo "$host $transport: generated client config failed validation"; return 1; }
  xray run -format json -config "$cfg" >"$WORK/xray.log" 2>&1 & XPID=$!
  for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$socks") 2>/dev/null && break; sleep 0.1; done
  local res
  res="$(curl -sS -o /dev/null --max-time 20 -x "socks5h://127.0.0.1:$socks" -w '%{http_code} %{time_total}' "$PROBE_URL" 2>&1 || true)"
  kill "$XPID" 2>/dev/null || true; wait "$XPID" 2>/dev/null || true; XPID=""
  if [[ "$res" == "$PROBE_EXPECT "* ]]; then
    echo "$host $transport: OK (${res#* }s)"
  else
    echo "$host $transport: FAIL ($(printf '%s' "$res" | tail -n 1 | sed -E 's/[0-9a-f]{8}-[0-9a-f-]{27,}/[UUID REDACTED]/Ig'))"
    return 1
  fi
}

rc=0
for host in "${hosts[@]}"; do
  for transport in universal xhttp; do probe "$host" "$transport" || rc=1; done
done
exit $rc
