#!/usr/bin/env bash
# End-to-end availability: from THIS machine, open a real VLESS+REALITY tunnel to each host/transport
# with a throwaway local xray client and fetch a 204 page through it. Exit 1 if any tunnel fails.
# Usage: nix-probe.sh [host-name...]
# A pass from outside Russia says nothing about reachability through Russian filtering.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for c in xray jq curl python3; do command -v "$c" >/dev/null || { echo "$c is required" >&2; exit 1; }; done
set -a; source "$ROOT/.env.local"; set +a
source "$ROOT/scripts/lib/client-outbound.sh"
PROBE_URL="${PROBE_URL:-https://www.gstatic.com/generate_204}"
PROBE_EXPECT="${PROBE_EXPECT:-204}"
if [[ $# -gt 0 ]]; then hosts=("$@"); else hosts=(); while IFS= read -r h; do hosts+=("$h"); done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/hosts.json"); fi

WORK="$(mktemp -d)"; chmod 700 "$WORK"
XPID=""
cleanup() { [[ -n "$XPID" ]] && kill "$XPID" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

probe() {
  local host="$1" transport="$2" socks cfg="$WORK/client.json"
  socks="$(free_port)"
  vless_outbound "$host" "$transport" probe > "$WORK/outbound.json" || return 1
  P_SOCKS="$socks" jq -n --slurpfile ob "$WORK/outbound.json" '{
    log: {loglevel: "error"},
    inbounds: [{listen: "127.0.0.1", port: (env.P_SOCKS | tonumber), protocol: "socks", settings: {udp: false}}],
    outbounds: $ob
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
