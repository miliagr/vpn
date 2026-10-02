{ config, lib, pkgs, ... }:
let
  cfg = config.vpn;
in
{
  config = lib.mkIf (cfg.secretsFile != null) {
    networking.wireguard.enable = true;
    networking.wireguard.interfaces.wg0 = {
      ips = [ "10.0.0.1/24" ];
      listenPort = cfg.wireguardPort;
      mtu = 1280;
      privateKeyFile = "/var/lib/vpn/wg-private-key";
      peers = [];
    };

    networking.firewall.allowedUDPPorts = [ cfg.wireguardPort ];

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



