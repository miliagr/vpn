#!/usr/bin/env bash
# Pull-based monitoring: ssh to each host (admin user), print a health summary, exit 1 if anything is wrong.
# Usage: nix-status.sh [--quiet] [host-name...]   (default: every host in hosts/hosts.json)
# Run it from cron/launchd and react to a non-zero exit locally; no third-party service is involved.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
quiet=0; [[ "${1:-}" == "--quiet" ]] && { quiet=1; shift; }
ADMIN_USER="${ADMIN_USER:-admin}"
source "$ROOT/scripts/lib/guards.sh"
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 1; }
set -a; source "$ROOT/.env.local"; set +a
if [[ $# -gt 0 ]]; then hosts=("$@"); else hosts=(); while IFS= read -r h; do hosts+=("$h"); done < <(jq -r 'keys_unsorted[]' "$ROOT/hosts/hosts.json"); fi

rc=0
for host in "${hosts[@]}"; do
  n="$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]')"; addr_v="${n}_ADDR"
  where="$(jq -r --arg h "$host" '[.[$h].datacenter, .[$h].country] | map(select(. != null and . != "")) | join(", ")' "$ROOT/hosts/hosts.json")"
  label="$host"; [[ -z "$where" ]] || label="$host ($where)"
  [[ -n "${!addr_v:-}" ]] || { echo "$host: missing $addr_v in .env.local" >&2; rc=1; continue; }
  refuse_placeholder "${!addr_v}" || { rc=1; continue; }
  if ! out="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$ADMIN_USER@${!addr_v}" 'bash -s' 2>&1 <<'REMOTE'
set -u
m=/var/lib/family-vpn-metrics/family_vpn.prom
val() { awk -v k="$1" 'index($0,k)==1 {print $NF; exit}' "$m" 2>/dev/null; }
now=$(date +%s); last=$(val family_vpn_health_last_run_timestamp_seconds); last=${last:-0}
echo "xray_active=$(systemctl is-active xray)"
echo "xray_up=$(val family_vpn_xray_up)"
echo "vpn_up=$(val family_vpn_up)"
echo "port_443=$(val 'family_vpn_port_listening{port="443"}')"
echo "port_8443=$(val 'family_vpn_port_listening{port="8443"}')"
echo "failed_units=$(val family_vpn_failed_units)"
echo "disk_used_percent=$(val family_vpn_root_disk_used_percent)"
echo "reboot_required=$(val family_vpn_reboot_required)"
echo "health_age_seconds=$((now - last))"
echo "firewall=$(systemctl is-active firewall)"
echo "fail2ban=$(systemctl is-active fail2ban)"
echo "banned_ips=$(sudo fail2ban-client status sshd 2>/dev/null | awk -F: '/Currently banned/ {gsub(/ /,"",$2); print $2}')"
echo "online_source_ips=$(val family_vpn_online_source_ips)"
echo "connections=$(val family_vpn_established_connections)"
iface=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
if [ -n "$iface" ]; then
  rx1=$(cat "/sys/class/net/$iface/statistics/rx_bytes"); tx1=$(cat "/sys/class/net/$iface/statistics/tx_bytes"); sleep 2
  rx2=$(cat "/sys/class/net/$iface/statistics/rx_bytes"); tx2=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
  echo "net_rx_mbit=$(awk -v a="$rx1" -v b="$rx2" 'BEGIN {printf "%.2f", (b - a) * 8 / 2 / 1e6}')"
  echo "net_tx_mbit=$(awk -v a="$tx1" -v b="$tx2" 'BEGIN {printf "%.2f", (b - a) * 8 / 2 / 1e6}')"
fi
echo "uptime=$(uptime -p)"
echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
echo "mem_available_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)"
REMOTE
  )"; then
    echo "$label: UNREACHABLE ($(printf '%s' "$out" | tail -n 1))"; rc=1; continue
  fi
  get() { printf '%s\n' "$out" | sed -n "s/^$1=//p"; }
  problems=()
  [[ "$(get xray_active)" == active && "$(get xray_up)" == 1 && "$(get vpn_up)" == 1 ]] || problems+=("VPN down (xray not running or ports closed)")
  [[ "$(get port_443)" == 1 && "$(get port_8443)" == 1 ]] || problems+=("VPN ports not listening")
  [[ "$(get failed_units)" == 0 ]] || problems+=("failed systemd units: $(get failed_units)")
  [[ "$(get firewall)" == active ]] || problems+=("firewall inactive")
  [[ "$(get fail2ban)" == active ]] || problems+=("fail2ban inactive")
  [[ "$(get disk_used_percent)" =~ ^[0-9]+$ && "$(get disk_used_percent)" -lt 85 ]] || problems+=("disk >= 85% used")
  [[ "$(get health_age_seconds)" =~ ^[0-9]+$ && "$(get health_age_seconds)" -lt 300 ]] || problems+=("health timer stale")
  [[ "$(get reboot_required)" == 1 ]] && problems+=("reboot required (new kernel)")
  if [[ ${#problems[@]} -gt 0 ]]; then
    rc=1; echo "$label: PROBLEM: $(IFS='; '; echo "${problems[*]}")"
  elif [[ $quiet -eq 0 ]]; then
    echo "$label: OK"
  fi
  [[ $quiet -eq 1 && ${#problems[@]} -eq 0 ]] || printf '%s\n' "$out" | sed 's/^/    /'
done
exit $rc
