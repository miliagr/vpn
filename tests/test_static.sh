#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

for f in scripts/*.sh tests/*.sh .githooks/pre-commit; do
  check "syntax: $f" bash -n "$f"
done
if command -v shellcheck >/dev/null; then
  check 'shellcheck scripts' shellcheck -S warning scripts/*.sh
else
  skip 'shellcheck not installed'
fi

check 'hosts.json is valid JSON' jq -e . hosts/hosts.json
check 'host names are lowercase alnum (they become env prefixes)' \
  jq -e 'keys | all(test("^[a-z][a-z0-9]*$"))' hosts/hosts.json
check 'every host has a disk' jq -e 'all(.[]; .disk | type == "string" and startswith("/dev/"))' hosts/hosts.json
check 'at least two hosts' jq -e 'length >= 2' hosts/hosts.json
check 'ssh_allowed_ips lists at least one source' grep -Evq '^[[:space:]]*(#|$)' hosts/ssh_allowed_ips
check 'ssh_allowed_ips has only IPs/CIDRs' bash -c '! grep -Ev "^[[:space:]]*(#|\$)|^[0-9a-fA-F:.]+(/[0-9]+)?\$" hosts/ssh_allowed_ips'
check 'authorized_keys has an SSH public key' grep -q '^ssh-' hosts/authorized_keys
check 'authorized_keys holds no private key' bash -c '! grep -q "PRIVATE KEY" hosts/authorized_keys'

# Template placeholders must line up with the NixOS module and the secrets push script.
placeholders="$(grep -o '__[A-Z_]*__' server/xray-server.template.json | sed 's/^__//; s/__$//' | sort -u)"
required="$(sed -n 's/.*required = \[\(.*\)\];/\1/p' nix/xray.nix | tr -d '"' | tr ' ' '\n' | grep . | sort -u)"
[[ "$placeholders" == "$required" ]] && pass 'template placeholders == required list in nix/xray.nix' \
  || fail "template placeholders differ from nix/xray.nix required list"
for p in $placeholders; do
  case "$p" in
    UNIVERSAL_PORT|XHTTP_PORT) ;;
    *) grep -q "printf '$p=" scripts/nix-push-secrets.sh && pass "push-secrets writes $p" || fail "push-secrets does not write $p" ;;
  esac
  grep -q "__${p}__" scripts/render.sh && pass "render.sh (legacy) substitutes $p" || fail "render.sh does not substitute $p"
done

# The raw template is not valid JSON (unquoted port placeholders), so check a rendered copy.
T="$(mktemp)"; trap 'rm -f "$T"' EXIT
sed -E 's/__UNIVERSAL_PORT__/443/g; s/__XHTTP_PORT__/8443/g; s/__[A-Z_]+__/x/g' server/xray-server.template.json > "$T"
check 'rendered template is valid JSON' jq -e . "$T"

# Server template security/monitoring invariants.
check 'only the two VPN inbounds exist' jq -e '[.inbounds[].port] | sort == [443,8443]' "$T"
check 'metrics endpoint is localhost-only' jq -e '.metrics.listen | startswith("127.0.0.1:")' "$T"
check 'access log disabled' jq -e '.log.access == "none"' "$T"
check 'private/loopback ranges are blackholed (clients cannot reach the server itself)' \
  jq -e '.routing.rules[0] | .outboundTag == "block" and (.ip | index("127.0.0.0/8") != null and index("169.254.0.0/16") != null and index("10.0.0.0/8") != null and index("::1/128") != null)' "$T"
check 'block outbound is a blackhole' jq -e '.outbounds[] | select(.tag == "block") | .protocol == "blackhole"' "$T"

# Secret hygiene on everything git tracks or has staged.
tracked="$(git ls-files)"
check '.env.local is ignored' git check-ignore -q .env.local
check 'build/ is ignored' git check-ignore -q build/x
check 'no .env.local or build/ tracked' bash -c '! git ls-files | grep -Eq "^(\.env\.local|build/)"'
check 'no UUIDs in tracked files' bash -c '! git ls-files -z | xargs -0 grep -IEq "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"'
check 'no concrete vless:// links in tracked files' bash -c '! git ls-files -z | xargs -0 grep -IEq "vless://[0-9a-fA-F]"'
check 'no private key blocks in tracked files' bash -c '! git ls-files -z | xargs -0 grep -IEq -- "-----BEGIN [A-Z ]*PRIVATE KEY"'
check '.env.example leaves secrets empty' bash -c '! grep -E "^(VLESS_UUID|VPS[0-9]+_(REALITY_PRIVATE_KEY|REALITY_PUBLIC_KEY|SHORT_ID))=." .env.example'
# Nix modules: nothing monitoring-related may be opened in the firewall.
check 'monitoring does not open firewall ports' bash -c '! grep -Eq "openFirewall *= *true" nix/monitoring.nix'
check 'exporters bind to localhost' grep -q 'listenAddress = "127.0.0.1"' nix/monitoring.nix
finish
