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

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
sed -E 's/__(UNIVERSAL|XHTTP)_PORT__/443/g; s/__[A-Z_]+__/x/g' server/xray-server.template.json > "$tmp"
check 'rendered template is valid JSON' jq -e . "$tmp"

# Secret hygiene on everything git tracks or has staged.
tracked="$(git ls-files)"
check '.env.local is ignored' git check-ignore -q .env.local
check 'build/ is ignored' git check-ignore -q build/x
check 'no .env.local or build/ tracked' bash -c '! git ls-files | grep -Eq "^(\.env\.local|build/)"'
check 'no UUIDs in tracked files' bash -c '! git ls-files -z | xargs -0 grep -IEq "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"'
check 'no concrete vless:// links in tracked files' bash -c '! git ls-files -z | xargs -0 grep -IEq "vless://[0-9a-fA-F]"'
check 'no private key blocks in tracked files' bash -c '! git ls-files -z | xargs -0 grep -IEq -- "-----BEGIN [A-Z ]*PRIVATE KEY"'
check '.env.example leaves secrets empty' bash -c '! grep -E "^(VLESS_UUID|VPS[0-9]+_(REALITY_PRIVATE_KEY|REALITY_PUBLIC_KEY|SHORT_ID))=." .env.example'
finish
