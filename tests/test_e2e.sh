#!/usr/bin/env bash
# End to end on this machine: real xray server from the real template + nix-probe.sh as the client.
# Needs a real xray and internet (REALITY forwards handshakes to a real site); skipped otherwise.
source "$(dirname "$0")/lib.sh"
export PATH="$PATH:/nix/var/nix/profiles/default/bin"
X="$(command -v xray || true)"
if [[ -z "$X" ]] && command -v nix >/dev/null; then X="$(nix build nixpkgs#xray --no-link --print-out-paths 2>/dev/null)/bin/xray"; fi
[[ -x "$X" ]] || { skip 'no xray available'; finish; }
curl -fsS --max-time 15 -o /dev/null https://www.gstatic.com/generate_204 || { skip 'no internet (gstatic unreachable)'; finish; }
(exec 3<>/dev/tcp/127.0.0.1/11111) 2>/dev/null && { skip 'port 11111 already in use'; finish; }

W="$(mktemp -d)"; SPID=""
trap '[[ -n "$SPID" ]] && kill "$SPID" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$W/repo" "$W/bin"; ln -s "$X" "$W/bin/xray"
cp -R "$ROOT/scripts" "$W/repo/"; mkdir "$W/repo/hosts"
echo '{"aeza-de-n-1": {"disk": "/dev/vda", "system": "x86_64-linux"}}' > "$W/repo/hosts/hosts.json"
keys="$("$X" x25519)"
priv="$(awk '/PrivateKey/ {print $NF}' <<<"$keys")"; pub="$(awk '/Password|PublicKey/ {print $NF; exit}' <<<"$keys")"
uuid="$("$X" uuid)"; sid=0123456789abcdef
sed -E "s/__UNIVERSAL_PORT__/14443/; s/__XHTTP_PORT__/18443/; s/__VLESS_UUID__/$uuid/g; s/__REALITY_PRIVATE_KEY__/$priv/g; s/__SHORT_ID__/$sid/g; s|__REALITY_DEST__|www.gstatic.com:443|; s/__REALITY_SERVER_NAME__/www.gstatic.com/g; s|__XHTTP_PATH__|/api/v1/sync|" "$ROOT/server/xray-server.template.json" > "$W/server.json"
"$X" run -format json -config "$W/server.json" >"$W/server.log" 2>&1 & SPID=$!
for _ in $(seq 1 50); do (exec 3<>/dev/tcp/127.0.0.1/14443) 2>/dev/null && break; sleep 0.1; done
check 'server from the real template is listening on both ports' bash -c '(exec 3<>/dev/tcp/127.0.0.1/14443) && (exec 3<>/dev/tcp/127.0.0.1/18443)'
check 'Xray metrics answer on localhost' bash -c "curl -fsS --max-time 3 http://127.0.0.1:11111/debug/vars | jq -e '.stats'"

cat > "$W/repo/.env.local" <<ENV
AEZA_DE_N_1_ADDR=127.0.0.1
AEZA_DE_N_1_REALITY_PUBLIC_KEY=$pub
AEZA_DE_N_1_SHORT_ID=$sid
VLESS_UUID=$uuid
REALITY_SERVER_NAME=www.gstatic.com
UNIVERSAL_PORT=14443
XHTTP_PORT=18443
XHTTP_PATH=/api/v1/sync
ENV
export PATH="$W/bin:$PATH"
out="$("$W/repo/scripts/nix-probe.sh" aeza-de-n-1 2>&1)"; rc=$?
echo "$out" | sed 's/^/    /'
[[ "$out" == *"aeza-de-n-1 universal: OK"* ]] && pass 'probe: VLESS+REALITY+Vision tunnel works end to end' || fail 'probe: universal tunnel'
[[ "$out" == *"aeza-de-n-1 xhttp: OK"* ]] && pass 'probe: VLESS+XHTTP+REALITY tunnel works end to end' || fail 'probe: xhttp tunnel'
[[ $rc -eq 0 ]] && pass 'probe exits 0 when everything works' || fail 'probe exit code'
check 'probe output contains no UUID' bash -c '! grep -Eq "[0-9a-f]{8}-[0-9a-f]{4}-" <<<"$0"' "$out"

# Through the tunnel, the server's own localhost (Xray metrics) must be unreachable: the routing rule blackholes it.
check 'sanity: metrics are reachable directly' curl -fsS --max-time 3 -o /dev/null http://127.0.0.1:11111/debug/vars
out="$(PROBE_URL=http://127.0.0.1:11111/debug/vars PROBE_EXPECT=200 "$W/repo/scripts/nix-probe.sh" aeza-de-n-1 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"aeza-de-n-1 universal: FAIL"* && "$out" == *"aeza-de-n-1 xhttp: FAIL"* ]] \
  && pass 'clients cannot reach the server localhost through the VPN (both transports)' || fail "localhost reachable through the tunnel: $out"
kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null; SPID=""
out="$("$W/repo/scripts/nix-probe.sh" aeza-de-n-1 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"FAIL"* ]] && pass 'probe reports failure and exits 1 when the server is down' || fail 'probe against a dead server'
finish
