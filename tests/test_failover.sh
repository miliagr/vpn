#!/usr/bin/env bash
# Real failover test on this machine: two Xray servers from the real template, one client from
# make-android-auto-profile.sh. Kill servers and check the client keeps working through the survivor.
# Needs xray + internet; takes about two minutes; skipped otherwise.
source "$(dirname "$0")/lib.sh"
export PATH="$PATH:/nix/var/nix/profiles/default/bin"
X="$(command -v xray || true)"
if [[ -z "$X" ]] && command -v nix >/dev/null; then X="$(nix build nixpkgs#xray --no-link --print-out-paths 2>/dev/null)/bin/xray"; fi
[[ -x "$X" ]] || { skip 'no xray available'; finish; }
curl -fsS --max-time 15 -o /dev/null https://www.gstatic.com/generate_204 || { skip 'no internet (gstatic unreachable)'; finish; }
for p in 11111 11112 10808 10809 14443 14444 18443 18444; do
  (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null && { skip "port $p already in use"; finish; }
done

W="$(mktemp -d)"; PIDS=()
trap 'for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"' EXIT
mkdir -p "$W/repo" "$W/bin"; ln -s "$X" "$W/bin/xray"
cp -R "$ROOT/scripts" "$ROOT/hosts" "$W/repo/"
keys="$("$X" x25519)"
priv="$(awk '/PrivateKey/ {print $NF}' <<<"$keys")"; pub="$(awk '/Password|PublicKey/ {print $NF; exit}' <<<"$keys")"
uuid="$("$X" uuid)"; sid=0123456789abcdef

render() { # <universal port> <xhttp port> <metrics port>
  sed -E "s/__UNIVERSAL_PORT__/$1/; s/__XHTTP_PORT__/$2/; s/__VLESS_UUID__/$uuid/g; s/__REALITY_PRIVATE_KEY__/$priv/g; s/__SHORT_ID__/$sid/g; s|__REALITY_DEST__|www.gstatic.com:443|; s/__REALITY_SERVER_NAME__/www.gstatic.com/g; s|__XHTTP_PATH__|/api/v1/sync|; s/127.0.0.1:11111/127.0.0.1:$3/" "$ROOT/server/xray-server.template.json"
}
render 14443 18443 11111 > "$W/a.json"; render 14444 18444 11112 > "$W/b.json"
start_server() { "$X" run -format json -config "$W/$1.json" >"$W/$1.log" 2>&1 & echo $!; }
wait_port() { for _ in $(seq 1 50); do (exec 3<>/dev/tcp/127.0.0.1/$1) 2>/dev/null && return 0; sleep 0.1; done; return 1; }
A="$(start_server a)"; B="$(start_server b)"; PIDS=("$A" "$B")
wait_port 14443 && wait_port 14444 && pass 'both servers are up' || fail 'servers did not start'

cat > "$W/repo/.env.local" <<ENV
VPS1_ADDR=127.0.0.1
VPS2_ADDR=127.0.0.1
VPS1_REALITY_PUBLIC_KEY=$pub
VPS2_REALITY_PUBLIC_KEY=$pub
VPS1_SHORT_ID=$sid
VPS2_SHORT_ID=$sid
VLESS_UUID=$uuid
REALITY_SERVER_NAME=www.gstatic.com
UNIVERSAL_PORT=14443
XHTTP_PORT=18443
XHTTP_PATH=/api/v1/sync
ENV
export PATH="$W/bin:$PATH"
out="$("$W/repo/scripts/make-android-auto-profile.sh" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass 'auto profile generated and accepted by xray -test' || fail "generator failed: $out"
check 'output does not print secrets' bash -c '! grep -Eq "[0-9a-f]{8}-[0-9a-f]{4}-" <<<"$0"' "$out"
cfg="$W/repo/build/mobile/android-auto.json"
check 'config is private (mode 600)' bash -c '[[ "$(stat -f %Lp "$0" 2>/dev/null || stat -c %a "$0")" == 600 ]]' "$cfg"
check 'pool has both servers' jq -e '[.outbounds[] | select(.tag | startswith("vpn-"))] | length == 2' "$cfg"
check 'uses a leastPing balancer with health checks' jq -e '.routing.balancers[0].strategy.type == "leastPing" and (.burstObservatory.subjectSelector == ["vpn-"])' "$cfg"

# Same host, different ports: second server's outbound points at 14444; use test-only SOCKS port.
jq '(.outbounds[] | select(.tag == "vpn-vps2-universal") | .settings.port) = 14444 | .inbounds[0].port = 20808 | .inbounds[1].port = 20809 | .burstObservatory.pingConfig.interval = "5s"' "$cfg" > "$W/client.json"
"$X" run -format json -config "$W/client.json" >"$W/client.log" 2>&1 & C=$!; PIDS+=("$C")
wait_port 20808 || fail 'client did not start'
fetch() { curl -sS -o /dev/null --max-time 10 -x socks5h://127.0.0.1:20808 -w '%{http_code}' https://www.gstatic.com/generate_204 2>/dev/null; }
retry() { local msg="$1" t; for t in $(seq 1 12); do [[ "$(fetch)" == 204 ]] && { pass "$msg"; return 0; }; sleep 3; done; fail "$msg"; return 1; }

sleep 12
retry 'traffic flows with both servers up'
kill "$A" 2>/dev/null; wait "$A" 2>/dev/null
retry 'server A killed: client still works (via B)'
A="$(start_server a)"; PIDS+=("$A"); wait_port 14443; sleep 15
kill "$B" 2>/dev/null; wait "$B" 2>/dev/null
retry 'server B killed: client still works (via A)'
kill "$A" 2>/dev/null; wait "$A" 2>/dev/null; sleep 2
[[ "$(fetch)" != 204 ]] && pass 'with every server down the client reports failure instead of leaking' || fail 'traffic flowed with all servers down'
finish
