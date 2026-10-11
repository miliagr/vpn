#!/usr/bin/env bash
# Generate per-user WireGuard client configurations as .conf and .png QR codes.
# One profile per client in hosts/wireguard_clients.json per host. Clients marked "ssh": true get a profile
# that routes only the server's tunnel address (for `ssh admin@10.42.0.1`), everyone else a full tunnel.
# Usage: make-wireguard-profiles.sh [host-name...]  (default: every host in hosts/hosts.json)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$ROOT/.env.local" ]] || { echo ".env.local missing; run ./scripts/generate-secrets.sh first" >&2; exit 1; }
set -a; source "$ROOT/.env.local"; set +a
source "$ROOT/scripts/lib/guards.sh"
source "$ROOT/scripts/lib/hosts.sh"
command -v wg >/dev/null || { echo 'wg (wireguard-tools) is required' >&2; exit 1; }
command -v qrencode >/dev/null || { echo 'qrencode is required for PNG QR codes' >&2; exit 1; }

mkdir -p "$ROOT/build/mobile"

users=(); while IFS= read -r u; do users+=("$u"); done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/wireguard_clients.json")
[[ ${#users[@]} -gt 0 ]] || { echo 'hosts/wireguard_clients.json has no clients; run ./scripts/generate-secrets.sh' >&2; exit 1; }

if [[ $# -gt 0 ]]; then hosts=("$@"); else hosts=(); while IFS= read -r h; do hosts+=("$h"); done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/hosts.json"); fi

for host in "${hosts[@]}"; do
  n="$(host_prefix "$host")"
  addr_v="${n}_ADDR"; wg_pub_v="${n}_WG_PUBLIC_KEY"
  
  for v in "$addr_v" "$wg_pub_v"; do
    [[ -n "${!v:-}" ]] || { echo "$host: missing $v in .env.local" >&2; exit 1; }
  done
  jq -e --arg h "$host" 'has($h)' "$ROOT/hosts/hosts.json" >/dev/null || { echo "$host: not in hosts/hosts.json" >&2; exit 1; }
  server_wg_port="$(jq -er --arg h "$host" '.[$h].wireguardPort // 51820 | select(type == "number" and floor == . and . >= 1 and . <= 65535)' "$ROOT/hosts/hosts.json")" \
    || { echo "$host: wireguardPort must be an integer from 1 to 65535 in hosts/hosts.json" >&2; exit 1; }
  
  refuse_placeholder "${!addr_v}" || exit 1
  
  server_addr="${!addr_v}"
  server_pubkey="${!wg_pub_v}"
  
  # Generate a client profile for each user
  for user in "${users[@]}"; do
    priv_var="WG_CLIENT_$(echo "$user" | tr 'a-z' 'A-Z')_PRIV"
    client_privkey="${!priv_var:-}"
    [[ -n "$client_privkey" ]] || { echo "$priv_var missing in .env.local; run generate-secrets.sh" >&2; exit 1; }
    
    client_ip="$(jq -r --arg u "$user" '.[$u].ip' "$ROOT/hosts/wireguard_clients.json")"
    # Same mapping as nix/wireguard.nix: the IPv4 last octet inside the tunnel's ULA prefix.
    client_ip6="fd42:42:42::${client_ip##*.}"
    
    # WireGuard client config per user
    profile_name="Family VPN $host WireGuard ($user)"
    conf_file="$ROOT/build/mobile/${host}-wireguard-${user}.conf"
    
    if [[ "$(jq -r --arg u "$user" '.[$u].ssh // false' "$ROOT/hosts/wireguard_clients.json")" == true ]]; then
      cat > "$conf_file" <<CONFEOF
[Interface]
PrivateKey = $client_privkey
Address = $client_ip/32
MTU = 1280

[Peer]
PublicKey = $server_pubkey
Endpoint = $server_addr:$server_wg_port
AllowedIPs = 10.42.0.1/32
PersistentKeepalive = 25
CONFEOF
    else
      cat > "$conf_file" <<CONFEOF
[Interface]
PrivateKey = $client_privkey
Address = $client_ip/24, $client_ip6/128
DNS = 8.8.8.8, 1.1.1.1
MTU = 1280

[Peer]
PublicKey = $server_pubkey
Endpoint = $server_addr:$server_wg_port
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
CONFEOF
    fi
    
    chmod 600 "$conf_file"
    echo "Generated: $conf_file"
    
    # Generate QR code
    qr_file="$ROOT/build/mobile/${host}-wireguard-${user}.png"
    qrencode -l L -s 6 -o "$qr_file" < "$conf_file"
    echo "Generated: $qr_file"
  done
done

echo "WireGuard profiles (per-user) ready in build/mobile/"
