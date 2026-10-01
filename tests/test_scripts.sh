#!/usr/bin/env bash
# Runs generate-secrets.sh and make-mobile-profiles.sh in a throwaway copy with a fake xray.
# Adds a third host to prove the tooling scales from hosts/hosts.json alone.
source "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || { skip 'jq missing'; finish; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/repo" "$W/bin"
cp -R "$ROOT/scripts" "$W/repo/"; mkdir "$W/repo/hosts"
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

# Fixture: three hosts named <datacenter>-<country>-n-<number>, so env prefixes with "-" -> "_" are exercised.
cat > hosts/hosts.json <<'JSON'
{
  "aeza-de-n-1": {"disk": "/dev/vda", "system": "x86_64-linux"},
  "hetzner-fi-n-1": {"disk": "/dev/vda", "system": "x86_64-linux"},
  "ovh-nl-n-1": {"disk": "/dev/vda", "system": "x86_64-linux"}
}
JSON
cat > .env.example <<'ENV'
AEZA_DE_N_1_ADDR=100.64.0.1
HETZNER_FI_N_1_ADDR=100.64.0.2
OVH_NL_N_1_ADDR=100.64.0.3
VLESS_UUID=
REALITY_DEST=www.microsoft.com:443
REALITY_SERVER_NAME=www.microsoft.com
UNIVERSAL_PORT=443
XHTTP_PORT=8443
XHTTP_PATH=/api/v1/sync
ENV

check 'generate-secrets runs' scripts/generate-secrets.sh
for n in AEZA_DE_N_1 HETZNER_FI_N_1 OVH_NL_N_1; do
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
for h in aeza-de-n-1 hetzner-fi-n-1 ovh-nl-n-1; do
  check "$h universal profile" test -s "build/mobile/$h-universal.txt"
  check "$h xhttp profile" test -s "build/mobile/$h-xhttp-android.txt"
done
check 'universal uses Vision flow' grep -q 'flow=xtls-rprx-vision' build/mobile/aeza-de-n-1-universal.txt
check 'xhttp profile uses xhttp' grep -q 'type=xhttp' build/mobile/hetzner-fi-n-1-xhttp-android.txt
check 'profile name is the host name' grep -q '#Family%20VPN%20aeza-de-n-1$' build/mobile/aeza-de-n-1-universal.txt
check 'XHTTP profile name is the host name plus XHTTP' grep -q '#Family%20VPN%20ovh-nl-n-1%20XHTTP$' build/mobile/ovh-nl-n-1-xhttp-android.txt
check 'no leftover profiles beyond hosts' bash -c '[[ "$(ls build/mobile/*.txt | wc -l)" -eq 6 ]]'

# nix-status.sh against a fake ssh that returns canned health output.
cat > "$W/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
case "$*" in
  *100.64.0.3*) echo 'ssh: connect to host 100.64.0.3 port 22: Connection timed out' >&2; exit 255 ;;
  *100.64.0.2*) want_ports=0 ;;
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
out="$(scripts/nix-status.sh aeza-de-n-1 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *"aeza-de-n-1: OK"* ]] && pass 'nix-status: healthy host exits 0' || fail 'nix-status: healthy host'
out="$(scripts/nix-status.sh hetzner-fi-n-1 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"VPN ports not listening"* ]] && pass 'nix-status: closed port is reported, exit 1' || fail 'nix-status: closed port'
out="$(scripts/nix-status.sh ovh-nl-n-1 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"UNREACHABLE"* ]] && pass 'nix-status: unreachable host is reported, exit 1' || fail 'nix-status: unreachable host'
out="$(scripts/nix-status.sh --quiet aeza-de-n-1 2>&1)"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] && pass 'nix-status --quiet is silent when healthy' || fail 'nix-status --quiet'

out="$(scripts/nix-status.sh aeza-de-n-1 2>&1)"
[[ "$out" == *"online_source_ips=2"* && "$out" == *"net_rx_mbit=1.50"* ]] && pass 'nix-status shows online users and network load' || fail 'nix-status online/network fields'

# nix-history.sh: fake ssh serves a CSV (ts,vpn_up,online,conns,rx,tx), 1 minute apart, 1 sample down, 1 gap.
cat > "$W/bin/ssh" <<FAKE
#!/usr/bin/env bash
now=\$(date +%s)
printf '%s\n' "\$((now-240)),1,1,3,1000000000,500000000" "\$((now-180)),1,3,9,1000000000,500000000" "\$((now-120)),0,0,0,1000000000,500000000" "\$((now-60)),1,2,5,1750000000,560000000"
FAKE
chmod +x "$W/bin/ssh"
out="$(scripts/nix-history.sh aeza-de-n-1 1 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass 'nix-history runs' || fail "nix-history failed: $out"
[[ "$out" == *"peak 3"* ]] && pass 'nix-history peak online users' || fail "nix-history peak online: $out"
[[ "$out" == *"in 100.00 Mbit/s"* ]] && pass 'nix-history peak inbound load (750 MB in 60 s = 100 Mbit/s)' || fail "nix-history peak load: $out"
[[ "$out" == *"VPN availability : 75.00%"* ]] && pass 'nix-history availability counts the down sample' || fail "nix-history availability: $out"

# Placeholder (documentation) addresses are refused by every script that takes one.
sed -i.bak 's/^AEZA_DE_N_1_ADDR=.*/AEZA_DE_N_1_ADDR=203.0.113.10/' .env.local
out="$(scripts/make-mobile-profiles.sh 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"placeholder address"* ]] && pass 'make-mobile-profiles refuses a placeholder address' || fail "make-mobile-profiles placeholder: $out"
out="$(scripts/nix-status.sh aeza-de-n-1 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"placeholder address"* ]] && pass 'nix-status refuses a placeholder address' || fail "nix-status placeholder: $out"
out="$(scripts/nix-install.sh aeza-de-n-1 root@198.51.100.20 </dev/null 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"placeholder address"* ]] && pass 'nix-install refuses a placeholder target before doing anything' || fail "nix-install placeholder: $out"
out="$(scripts/nix-push-secrets.sh aeza-de-n-1 admin@192.0.2.5 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"placeholder address"* ]] && pass 'nix-push-secrets refuses a placeholder target' || fail "nix-push-secrets placeholder: $out"

# nix-install.sh forwards extra options to nixos-anywhere (fake nix records its arguments).
sed -i.bak 's/^AEZA_DE_N_1_ADDR=.*/AEZA_DE_N_1_ADDR=100.64.0.1/' .env.local
cat > "$W/bin/nix" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$NIX_ARGS_FILE"
FAKE
chmod +x "$W/bin/nix"
export NIX_ARGS_FILE="$W/nix-args"
echo aeza-de-n-1 | scripts/nix-install.sh aeza-de-n-1 root@100.64.0.1 --kexec-extra-flags "--kexec-syscall" >/dev/null 2>&1
check 'nix-install passes extra options to nixos-anywhere' bash -c 'grep -qx -- "--kexec-extra-flags" "$0" && grep -qx -- "--kexec-syscall" "$0" && grep -qx -- ".#aeza-de-n-1" "$0"' "$NIX_ARGS_FILE"
echo aeza-de-n-1 | scripts/nix-install.sh aeza-de-n-1 root@100.64.0.1 >/dev/null 2>&1
check 'nix-install works without extra options' bash -c '! grep -q -- "--kexec" "$0" && grep -qx -- "--target-host" "$0"' "$NIX_ARGS_FILE"
finish
