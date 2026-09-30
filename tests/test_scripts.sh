#!/usr/bin/env bash
# Runs generate-secrets.sh and make-mobile-profiles.sh in a throwaway copy with a fake xray.
# Adds a third host to prove the tooling scales from hosts/hosts.json alone.
source "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || { skip 'jq missing'; finish; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/repo" "$W/bin"
cp -R "$ROOT/scripts" "$ROOT/hosts" "$ROOT/.env.example" "$W/repo/"
cat > "$W/bin/xray" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  uuid) echo "$(openssl rand -hex 4)-1111-4111-8111-$(openssl rand -hex 6)" ;;
  x25519) printf 'PrivateKey: %s\nPassword: %s\n' "$(openssl rand -hex 16)" "$(openssl rand -hex 16)" ;;
  version) echo 'Xray fake' ;;
esac
FAKE
chmod +x "$W/bin/xray"
export PATH="$W/bin:$PATH"
cd "$W/repo"

jq '. + {"vps3": {"disk": "/dev/vda", "system": "x86_64-linux"}}' hosts/hosts.json > h.json && mv h.json hosts/hosts.json
sed -i.bak 's/^VPS1_ADDR=.*/VPS1_ADDR=192.0.2.1/; s/^VPS2_ADDR=.*/VPS2_ADDR=192.0.2.2/' .env.example
printf 'VPS3_ADDR=192.0.2.3\n' >> .env.example

check 'generate-secrets runs' scripts/generate-secrets.sh
for n in VPS1 VPS2 VPS3; do
  for k in REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY SHORT_ID; do
    check "${n}_$k generated" grep -q "^${n}_$k=." .env.local
  done
done
check 'VLESS_UUID generated' grep -q '^VLESS_UUID=.' .env.local
check '.env.local is mode 600' bash -c '[[ "$(stat -f %Lp .env.local 2>/dev/null || stat -c %a .env.local)" == 600 ]]'
before="$(shasum .env.local)"
scripts/generate-secrets.sh >/dev/null
[[ "$before" == "$(shasum .env.local)" ]] && pass 'generate-secrets is idempotent' || fail 'generate-secrets changed existing secrets'
check 'generate-secrets does not print secrets' bash -c '! scripts/generate-secrets.sh | grep -Eq "[0-9a-f]{16}"'

check 'make-mobile-profiles runs' scripts/make-mobile-profiles.sh
for h in vps1 vps2 vps3; do
  check "$h universal profile" test -s "build/mobile/$h-universal.txt"
  check "$h xhttp profile" test -s "build/mobile/$h-xhttp-android.txt"
done
check 'universal uses Vision flow' grep -q 'flow=xtls-rprx-vision' build/mobile/vps1-universal.txt
check 'xhttp profile uses xhttp' grep -q 'type=xhttp' build/mobile/vps2-xhttp-android.txt
check 'profiles are named by order' grep -q '#Family%20VPN%203$' build/mobile/vps3-universal.txt
check 'no leftover profiles beyond hosts' bash -c '[[ "$(ls build/mobile/*.txt | wc -l)" -eq 6 ]]'

# nix-status.sh against a fake ssh that returns canned health output.
cat > "$W/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
case "$*" in
  *192.0.2.3*) echo 'ssh: connect to host 192.0.2.3 port 22: Connection timed out' >&2; exit 255 ;;
  *192.0.2.2*) want_ports=0 ;;
  *) want_ports=1 ;;
esac
cat <<OUT
xray_active=active
xray_up=1
vpn_up=1
port_443=1
port_8443=$want_ports
failed_units=0
disk_used_percent=20
reboot_required=0
health_age_seconds=30
firewall=active
fail2ban=active
banned_ips=0
uptime=up 1 day
online_source_ips=2
connections=7
net_rx_mbit=1.50
net_tx_mbit=0.30
load=0.01 0.02 0.03
mem_available_mb=900
OUT
FAKE
chmod +x "$W/bin/ssh"
out="$(scripts/nix-status.sh vps1 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *"vps1: OK"* ]] && pass 'nix-status: healthy host exits 0' || fail 'nix-status: healthy host'
out="$(scripts/nix-status.sh vps2 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"VPN ports not listening"* ]] && pass 'nix-status: closed port is reported, exit 1' || fail 'nix-status: closed port'
out="$(scripts/nix-status.sh vps3 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"UNREACHABLE"* ]] && pass 'nix-status: unreachable host is reported, exit 1' || fail 'nix-status: unreachable host'
out="$(scripts/nix-status.sh --quiet vps1 2>&1)"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] && pass 'nix-status --quiet is silent when healthy' || fail 'nix-status --quiet'

out="$(scripts/nix-status.sh vps1 2>&1)"
[[ "$out" == *"online_source_ips=2"* && "$out" == *"net_rx_mbit=1.50"* ]] && pass 'nix-status shows online users and network load' || fail 'nix-status online/network fields'

# nix-history.sh: fake ssh serves a CSV (ts,vpn_up,online,conns,rx,tx), 1 minute apart, 1 sample down, 1 gap.
cat > "$W/bin/ssh" <<FAKE
#!/usr/bin/env bash
now=\$(date +%s)
printf '%s\n' "\$((now-240)),1,1,3,1000000000,500000000" "\$((now-180)),1,3,9,1000000000,500000000" "\$((now-120)),0,0,0,1000000000,500000000" "\$((now-60)),1,2,5,1750000000,560000000"
FAKE
chmod +x "$W/bin/ssh"
out="$(scripts/nix-history.sh vps1 1 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass 'nix-history runs' || fail "nix-history failed: $out"
[[ "$out" == *"peak 3"* ]] && pass 'nix-history peak online users' || fail "nix-history peak online: $out"
[[ "$out" == *"in 100.00 Mbit/s"* ]] && pass 'nix-history peak inbound load (750 MB in 60 s = 100 Mbit/s)' || fail "nix-history peak load: $out"
[[ "$out" == *"VPN availability : 75.00%"* ]] && pass 'nix-history availability counts the down sample' || fail "nix-history availability: $out"
finish
