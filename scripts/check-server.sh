#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 user@host" >&2; exit 1; }
host="$1"
ssh "$host" 'bash -s' <<'REMOTE'
set -euo pipefail
echo '== xray version =='
xray version | sed -n '1,2p'
echo '== config =='
xray run -test -config /usr/local/etc/xray/config.json
echo '== service =='
systemctl is-active xray
echo '== listening =='
ss -lnt | awk 'NR==1 || /:443[[:space:]]|:8443[[:space:]]/'
echo '== recent xray log =='
journalctl -u xray -n 12 --no-pager | sed -E 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[UUID REDACTED]/Ig'
REMOTE
