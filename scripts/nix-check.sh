#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 user@host" >&2; exit 1; }
source "$(dirname "$0")/lib/guards.sh"; refuse_placeholder "$1" || exit 1
ssh "$1" 'bash -s' <<'REMOTE'
set -euo pipefail
echo '== system =='
nixos-version
readlink /run/current-system
echo '== service =='
systemctl is-active xray
echo '== listening =='
ss -lnt | awk 'NR==1 || /:443[[:space:]]|:8443[[:space:]]/'
echo '== firewall =='
systemctl is-active firewall
echo '== ssh policy =='
sudo sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|allowusers) '
echo '== all listening sockets =='
ss -lntuH | awk '{print $1, $5}'
echo '== recent xray log =='
sudo journalctl -u xray -n 12 --no-pager | sed -E 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[UUID REDACTED]/Ig'
REMOTE
