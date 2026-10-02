#!/usr/bin/env bash
# Generate per-user WireGuard client configurations as .txt and .png QR codes.
# One profile per user per host (owner, parent1, parent2, etc.).
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

# User list (owner, parent1, parent2, ...)
users=("owner" "parent1" "parent2")

if [[ $# -gt 0 ]]; then hosts=("$@"); else hosts=(); while IFS= read -r h; do hosts+=("$h"); done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/hosts.json"); fi

for host in "${hosts[@]}"; do
  n="$(host_prefix "$host")"
  addr_v="${n}_ADDR"; wg_pub_v="${n}_WG_PUBLIC_KEY"; wg_port_v="${n}_WG_PORT"
  
  for v in "$addr_v" "$wg_pub_v" "$wg_port_v"; do
    [[ -n "${!v:-}" ]] || { echo "$host: missing $v in .env.local" >&2; exit 1; }
  done
  
  refuse_placeholder "${!addr_v}" || exit 1
  
  server_addr="${!addr_v}"
  server_pubkey="${!wg_pub_v}"
  server_wg_port="${!wg_port_v}"
  
  # Generate a client profile for each user
  for user in "${users[@]}"; do
    client_privkey="$(wg genkey)"
    client_pubkey="$(printf '%s' "$client_privkey" | wg pubkey)"
    
    # WireGuard client config per user
    profile_name="Family VPN $host WireGuard ($user)"
    conf_file="$ROOT/build/mobile/${host}-wireguard-${user}.txt"
    
    cat > "$conf_file" <<CONFEOF
[Interface]
PrivateKey = $client_privkey
Address = 10.0.0.$((2 + $(echo "$user" | md5sum | cut -c1-2 | xargs printf '%d' 2>/dev/null || echo 0) % 252 + 1))/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $server_pubkey
Endpoint = $server_addr:$server_wg_port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CONFEOF
    
    chmod 600 "$conf_file"
    echo "Generated: $conf_file"
    
    # Generate QR code
    qr_file="$ROOT/build/mobile/${host}-wireguard-${user}.png"
    qrencode -l L -s 6 -o "$qr_file" < "$conf_file"
    echo "Generated: $qr_file"
  done
done

echo "WireGuard profiles (per-user) ready in build/mobile/"
