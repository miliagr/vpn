{ lib, hostCfg, ... }:
let
  net = hostCfg.network or null;
in
{
  # Hosts without a "network" block keep the default (DHCP). Providers that hand out static addresses
  # (no DHCP server, gateway outside the subnet) need the block in hosts/hosts.json.
  config = lib.mkIf (net != null) {
    networking.useDHCP = false;
    networking.useNetworkd = true;
    networking.nameservers = net.dns;

    # Matched by MAC so the interface name (enp0s3, ens3, ...) does not matter.
    systemd.network.enable = true;
    systemd.network.networks."10-wan" = {
      matchConfig.MACAddress = net.mac;
      address = [ net.address ];
      routes = [{
        Gateway = net.gateway;
        GatewayOnLink = net.gatewayOnLink or false;
      }];
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
