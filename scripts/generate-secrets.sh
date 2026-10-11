#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV="$ROOT/.env.local"
TEMPLATE="$ROOT/.env.example"
command -v xray >/dev/null || { echo 'xray is required (macOS: brew install xray)' >&2; exit 1; }
command -v openssl >/dev/null || { echo 'openssl is required' >&2; exit 1; }
command -v wg >/dev/null || { echo 'wg (wireguard-tools) is required (macOS: brew install wireguard-tools)' >&2; exit 1; }
source "$ROOT/scripts/lib/hosts.sh"
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 1; }
[[ -f "$ENV" ]] || cp "$TEMPLATE" "$ENV"
chmod 600 "$ENV"

get_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "$ENV" | tail -n 1
}
set_value() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" 'BEGIN{done=0} $0 ~ "^" k "=" {print k "=" v; done=1; next} {print} END{if(!done) print k "=" v}' "$ENV" > "$tmp"
  mv "$tmp" "$ENV"
  chmod 600 "$ENV"
}
parse_private() { printf '%s\n' "$1" | awk '/PrivateKey|Private key/ {print $NF; exit}'; }
parse_public()  { printf '%s\n' "$1" | awk '/Password|PublicKey|Public key/ {print $NF; exit}'; }

if [[ -z "$(get_value VLESS_UUID)" ]]; then
  set_value VLESS_UUID "$(xray uuid)"
fi

CLIENTS_FILE="$ROOT/hosts/wireguard_clients.json"
if [[ ! -f "$CLIENTS_FILE" ]]; then
  echo "{}" > "$CLIENTS_FILE"
fi

# Append new clients at the end: the position decides the tunnel address (10.42.0.2, .3, ...).
# "admin" is the SSH-only client (see make-wireguard-profiles.sh and nix/wireguard.nix).
users=("owner" "parent1" "parent2" "admin")
ip_counter=2
for user in "${users[@]}"; do
  priv_var="WG_CLIENT_$(echo "$user" | tr 'a-z' 'A-Z')_PRIV"
  if [[ -z "$(get_value "$priv_var")" ]]; then
    priv_val="$(wg genkey)"
    pub_val="$(printf '%s' "$priv_val" | wg pubkey)"
    set_value "$priv_var" "$priv_val"
    
    # Add to clients JSON
    ip="10.42.0.$ip_counter"
    tmp="$(mktemp)"
    jq --arg u "$user" --arg p "$pub_val" --arg ip "$ip" '.[$u] = {publicKey: $p, ip: $ip} + (if $u == "admin" then {ssh: true} else {} end)' "$CLIENTS_FILE" > "$tmp"
    mv "$tmp" "$CLIENTS_FILE"
  fi
  ((ip_counter++))
done

while IFS= read -r host; do
  n="$(host_prefix "$host")"
  
  # VLESS + REALITY keypairs
  pk="${n}_REALITY_PRIVATE_KEY"
  pub="${n}_REALITY_PUBLIC_KEY"
  sid="${n}_SHORT_ID"
  if [[ -z "$(get_value "$pk")" || -z "$(get_value "$pub")" ]]; then
    pair="$(xray x25519)"
    private="$(parse_private "$pair")"
    public="$(parse_public "$pair")"
    [[ -n "$private" && -n "$public" ]] || { echo "Could not parse xray x25519 output for $host" >&2; exit 1; }
    set_value "$pk" "$private"
    set_value "$pub" "$public"
  fi
  if [[ -z "$(get_value "$sid")" ]]; then
    set_value "$sid" "$(openssl rand -hex 8)"
  fi
  
  # WireGuard keypairs
  wg_priv="${n}_WG_PRIVATE_KEY"
  wg_pub="${n}_WG_PUBLIC_KEY"
  if [[ -z "$(get_value "$wg_priv")" || -z "$(get_value "$wg_pub")" ]]; then
    wg_priv_val="$(wg genkey)"
    wg_pub_val="$(printf '%s' "$wg_priv_val" | wg pubkey)"
    set_value "$wg_priv" "$wg_priv_val"
    set_value "$wg_pub" "$wg_pub_val"
  fi
done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/hosts.json")

echo 'Secrets generated and stored in .env.local (values intentionally not printed).'
