#!/usr/bin/env bash
# Evaluates every NixOS host. Skipped where Nix is not installed (e.g. this Mac before setup).
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
# Nix installed by the Determinate installer is often missing from non-login shells.
export PATH="$PATH:/nix/var/nix/profiles/default/bin"
if ! command -v nix >/dev/null; then skip 'nix not installed: NixOS code is NOT evaluated by this run'; finish; fi
[[ -f flake.lock ]] || { fail 'flake.lock missing: run nix flake lock and commit it'; finish; }
check 'nix flake check' nix flake check --no-build
while IFS= read -r h; do
  check "evaluate $h" nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath"
done < <(jq -r 'keys_unsorted[]' hosts/hosts.json)

# Security posture of the evaluated configuration (first host; all hosts share the same modules).
h="$(jq -r 'keys_unsorted[0]' hosts/hosts.json)"
cfg() { nix eval --json ".#nixosConfigurations.$h.config.$1" 2>/dev/null; }
eq() { local msg="$1" attr="$2" want="$3"; [[ "$(cfg "$attr")" == "$want" ]] && pass "$msg" || fail "$msg (got $(cfg "$attr"))"; }
eq 'root SSH login disabled' services.openssh.settings.PermitRootLogin '"no"'
eq 'SSH password auth disabled' services.openssh.settings.PasswordAuthentication 'false'
eq 'only admin may SSH' services.openssh.settings.AllowUsers '["admin"]'
eq 'users are immutable' users.mutableUsers 'false'
eq 'root has no password' users.users.root.hashedPassword '"!"'
eq 'firewall enabled' networking.firewall.enable 'true'
eq 'inbound TCP is only ssh + VPN ports' networking.firewall.allowedTCPPorts '[22,443,8443]'
eq 'no inbound UDP' networking.firewall.allowedUDPPorts '[]'
eq 'fail2ban enabled' services.fail2ban.enable 'true'
eq 'node exporter on localhost' services.prometheus.exporters.node.listenAddress '"127.0.0.1"'
eq 'xray runs as a dynamic user' systemd.services.xray.serviceConfig.DynamicUser 'true'

# Validate the real template with the real Xray (same version nixpkgs ships).
X="$(nix build nixpkgs#xray --no-link --print-out-paths 2>/dev/null)/bin/xray"
if [[ -x "$X" ]]; then
  priv="$("$X" x25519 | awk '/PrivateKey/ {print $NF}')"
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  sed -E "s/__UNIVERSAL_PORT__/14443/; s/__XHTTP_PORT__/18443/; s/__VLESS_UUID__/$("$X" uuid)/g; s/__REALITY_PRIVATE_KEY__/$priv/g; s/__SHORT_ID__/0123456789abcdef/g; s|__REALITY_DEST__|example.com:443|; s/__REALITY_SERVER_NAME__/example.com/g; s|__XHTTP_PATH__|/p|" server/xray-server.template.json > "$tmp"
  check 'xray run -test accepts the rendered template (extensionless file, as in xray-render)' "$X" run -test -format json -config "$tmp"
else
  fail 'could not obtain xray from nixpkgs'
fi
finish
