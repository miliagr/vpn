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
eq 'globally open TCP ports are only the VPN ports (SSH is not among them)' networking.firewall.allowedTCPPorts '[443,8443]'
allowed="$(grep -Ev '^[[:space:]]*(#|$)' hosts/ssh_allowed_ips)"
rules="$(nix eval --raw ".#nixosConfigurations.$h.config.networking.firewall.extraCommands" 2>/dev/null)"
n_rules="$(grep -c -- '-A nixos-fw -p tcp -s [^ ]* --dport 22 -j nixos-fw-accept' <<<"$rules")"
[[ "$n_rules" == "$(wc -l <<<"$allowed" | tr -d ' ')" && -n "$allowed" ]] && pass 'one SSH accept rule per allowed source' || fail "SSH firewall rules ($n_rules) do not match hosts/ssh_allowed_ips"
while IFS= read -r ip; do grep -q -- "-s $ip --dport 22" <<<"$rules" && pass "SSH allowed only from $ip" || fail "no SSH rule for $ip"; done <<<"$allowed"
wg_ssh="$(jq -r '.[] | select(.ssh == true) | .ip' hosts/wireguard_clients.json)"
n_wg_ssh="$(grep -c . <<<"$wg_ssh" || true)"
[[ "$(grep -c -- '--dport 22' <<<"$rules")" == "$((n_rules + n_wg_ssh))" && "$rules" != *"-A nixos-fw -p tcp --dport 22"* ]] && pass 'no unconditional SSH rule' || fail 'unconditional SSH rule present'
while IFS= read -r ip; do [[ -z "$ip" ]] && continue; grep -q -- "-A nixos-fw -i wg0 -p tcp -s $ip --dport 22 -j nixos-fw-accept" <<<"$rules" && pass "SSH through the tunnel allowed for the ssh client $ip" || fail "no tunnel SSH rule for $ip"; done <<<"$wg_ssh"
while IFS= read -r ip; do grep -q -- "-s $ip --dport 22" <<<"$rules" && fail "SSH allowed for ordinary WireGuard client $ip" || pass "no SSH for ordinary WireGuard client $ip"; done < <(jq -r '.[] | select(.ssh != true) | .ip' hosts/wireguard_clients.json)
[[ "$(grep -c -- '-i wg0 .*--dport 22' <<<"$rules")" == "$n_wg_ssh" ]] && pass 'tunnel SSH rules exist only for ssh clients' || fail 'unexpected SSH rule on wg0'
eq 'WireGuard port comes from the host configuration' vpn.wireguardPort "$(jq -r --arg h "$h" '.[$h].wireguardPort // 51820' hosts/hosts.json)"
eq 'fail2ban enabled' services.fail2ban.enable 'true'
eq 'node exporter on localhost' services.prometheus.exporters.node.listenAddress '"127.0.0.1"'
eq 'xray runs as a dynamic user' systemd.services.xray.serviceConfig.DynamicUser 'true'
eq 'WireGuard enabled' networking.wireguard.enable 'true'
eq 'WireGuard listen port matches host configuration' networking.wireguard.interfaces.wg0.listenPort "$(jq -r --arg h "$h" '.[$h].wireguardPort // 51820' hosts/hosts.json)"
eq 'WireGuard UDP firewall port matches host configuration' networking.firewall.allowedUDPPorts "[$(jq -r --arg h "$h" '.[$h].wireguardPort // 51820' hosts/hosts.json)]"
eq 'WireGuard tunnel MTU' networking.wireguard.interfaces.wg0.mtu '1280'
eq 'WireGuard interface has the ULA address' networking.wireguard.interfaces.wg0.ips '["10.42.0.1/24","fd42:42:42::1/64"]'
wg_allowed="$(nix eval --json ".#nixosConfigurations.$h.config.networking.wireguard.interfaces.wg0.peers" 2>/dev/null | jq -c '[.[].allowedIPs] | sort')"
wg_expected="$(jq -c '[.[] | [.ip + "/32", "fd42:42:42::" + (.ip | split(".") | last) + "/128"]] | sort' hosts/wireguard_clients.json)"
[[ -n "$wg_allowed" && "$wg_allowed" == "$wg_expected" ]] && pass 'every WireGuard peer is allowed exactly its IPv4 and ULA address' || fail "WireGuard peer allowedIPs: $wg_allowed, expected $wg_expected"
for dir in i o; do
  [[ "$(grep -c -- "-A FORWARD -$dir wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu" <<<"$rules")" == 1 ]] && pass "TCP MSS clamped on wg0 (-$dir)" || fail "no TCP MSS clamp rule for -$dir wg0"
done
eq 'tunnelled IPv6 is rejected, not dropped (forwarding on)' 'boot.kernel.sysctl."net.ipv6.conf.all.forwarding"' '1'
eq 'no IPv6 NAT' networking.nat.enableIPv6 'false'
eq 'NAT enabled' networking.nat.enable 'true'
eq 'NAT internal interfaces includes wg0' networking.nat.internalInterfaces '["wg0"]'
while IFS= read -r host; do
  port="$(jq -r --arg h "$host" '.[$h].wireguardPort // 51820' hosts/hosts.json)"
  actual="$(nix eval --json ".#nixosConfigurations.$host.config.vpn.wireguardPort" 2>/dev/null)"
  [[ "$actual" == "$port" ]] && pass "$host WireGuard server port matches hosts.json" || fail "$host WireGuard server port differs from hosts.json"
done < <(jq -r 'keys_unsorted[]' hosts/hosts.json)


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
