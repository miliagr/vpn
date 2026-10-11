{ config, lib, pkgs, ... }:
let
  cfg = config.vpn;
  
  # Read client keys if available
  clients = if builtins.pathExists ../hosts/wireguard_clients.json then builtins.fromJSON (builtins.readFile ../hosts/wireguard_clients.json) else {};

  # Tunnel MTU. make-wireguard-profiles.sh writes the same value into the client profiles.
  mtu = 1280;
  # The server has no IPv6 uplink. Clients still get an address from this ULA prefix and route ::/0 into the
  # tunnel, so IPv6 cannot bypass the VPN; the host answers it with "no route" and apps fall back to IPv4.
  # The last octet of the client's IPv4 address is reused (10.42.0.2 -> fd42:42:42::2).
  ula = "fd42:42:42::";
  ip6 = ip: "${ula}${lib.last (lib.splitString "." ip)}";
  # Without this, TCP packets larger than the tunnel MTU are dropped whenever the far end ignores ICMP
  # "fragmentation needed": pages load partially and images hang.
  # Clients marked "ssh": true in hosts/wireguard_clients.json may reach sshd through the tunnel.
  sshPort = toString (builtins.head config.services.openssh.ports);
  sshClientIps = lib.mapAttrsToList (_: data: data.ip) (lib.filterAttrs (_: data: data.ssh or false) clients);
  sshRule = ip: "iptables -w -A nixos-fw -i wg0 -p tcp -s ${ip} --dport ${sshPort} -j nixos-fw-accept";
  mssRule = op: dir: "iptables -w -t mangle -${op} FORWARD -${dir} wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu";
in
{
  config = lib.mkIf (cfg.secretsFile != null) {
    networking.nat = {
      enable = true;
      internalInterfaces = [ "wg0" ];
    };

    networking.wireguard.enable = true;
    networking.wireguard.interfaces.wg0 = {
      ips = [ "10.42.0.1/24" "${ula}1/64" ];
      listenPort = cfg.wireguardPort;
      inherit mtu;
      privateKeyFile = "/var/lib/vpn/wg-private-key";
      peers = lib.mapAttrsToList (name: data: {
        publicKey = data.publicKey;
        allowedIPs = [ "${data.ip}/32" "${ip6 data.ip}/128" ];
      }) clients;
    };

    networking.firewall.allowedUDPPorts = [ cfg.wireguardPort ];

    # Delete-then-add keeps the rules single across firewall reloads.
    networking.firewall.extraCommands = lib.concatStringsSep "\n" (
      map (dir: "${mssRule "D" dir} 2>/dev/null || true\n${mssRule "A" dir}") [ "i" "o" ]
      ++ map sshRule sshClientIps);
    networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n"
      (dir: "${mssRule "D" dir} 2>/dev/null || true") [ "i" "o" ];

    services.fail2ban.ignoreIP = sshClientIps;

    # Forwarding without an IPv6 default route makes the kernel reject tunnelled IPv6 with ICMPv6 "no route"
    # instead of silently dropping it.
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

    systemd.services.wireguard-extract-key = {
      description = "Extract WireGuard private key from secrets file";
      wantedBy = [ "network-pre.target" ];
      before = [ "wg-quick-wg0.service" ];
      unitConfig.ConditionPathExists = cfg.secretsFile;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.bash}/bin/bash -c 'source ${cfg.secretsFile} && echo \"$WG_PRIVATE_KEY\" > /var/lib/vpn/wg-private-key && chmod 600 /var/lib/vpn/wg-private-key'";
        RemainAfterExit = "yes";
      };
    };

  };
}
