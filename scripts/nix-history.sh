#!/usr/bin/env bash
# Usage: nix-history.sh <host-name> [hours=24]
# Summarises the per-minute history each server keeps (7 days): VPN availability, online source IPs, network load.
# "Online" = distinct source IPs with an established VPN connection, so several devices behind one router count once.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 1 ]] || { echo "Usage: $0 <host-name> [hours]" >&2; exit 1; }
host="$1"; hours="${2:-24}"
[[ "$hours" =~ ^[0-9]+$ && "$hours" -gt 0 ]] || { echo 'hours must be a positive integer' >&2; exit 1; }
ADMIN_USER="${ADMIN_USER:-admin}"
set -a; source "$ROOT/.env.local"; set +a
source "$ROOT/scripts/lib/hosts.sh"
n="$(host_prefix "$host")"; addr_v="${n}_ADDR"
[[ -n "${!addr_v:-}" ]] || { echo "Missing $addr_v in .env.local" >&2; exit 1; }
source "$ROOT/scripts/lib/guards.sh"; refuse_placeholder "${!addr_v}" || exit 1

ssh -o BatchMode=yes -o ConnectTimeout=10 "$ADMIN_USER@${!addr_v}" 'cat /var/lib/vpn-metrics/history.csv' \
| awk -F, -v hours="$hours" -v host="$host" -v now="$(date +%s)" '
  BEGIN { since = now - hours * 3600 }
  $1 >= since && NF == 6 {
    if (!samples) first = $1
    samples++; up += $2; if ($3 > maxo) maxo = $3; sumo += $3
    if (havePrev && $1 > pts && $5 >= prx && $6 >= ptx) {
      dt = $1 - pts; r = ($5 - prx) * 8 / dt / 1e6; t = ($6 - ptx) * 8 / dt / 1e6
      if (r > maxr) maxr = r; if (t > maxt) maxt = t
      rxb += $5 - prx; txb += $6 - ptx
    }
    pts = $1; prx = $5; ptx = $6; havePrev = 1
  }
  END {
    if (!samples) { print host ": no samples in the last " hours "h"; exit 1 }
    # Measured from the first sample (a new server has no older history), up to now, so a stopped timer shows as downtime.
    window = now - first; if (window > hours * 3600) window = hours * 3600
    expected = int(window / 60); if (expected < samples) expected = samples
    printf "%s, last %dh (%d samples, one per minute, since first sample; gaps count as downtime)\n", host, hours, samples
    printf "  VPN availability : %.2f%%\n", up / expected * 100
    printf "  online source IPs: avg %.1f, peak %d\n", sumo / samples, maxo
    printf "  peak network load: in %.2f Mbit/s, out %.2f Mbit/s\n", maxr, maxt
    printf "  traffic          : in %.2f GB, out %.2f GB\n", rxb / 1e9, txb / 1e9
  }'
