{ config, lib, pkgs, ... }:
let
  metricsDir = "/var/lib/family-vpn-metrics";

  # Writes Prometheus textfile metrics; node_exporter (localhost only) serves them.
  # Only aggregate per-inbound byte counters are read from Xray, never per-client or per-destination data.
  health = pkgs.writeShellApplication {
    name = "family-vpn-health";
    runtimeInputs = with pkgs; [ coreutils iproute2 systemd jq curl gnugrep ];
    text = ''
      out=${metricsDir}/family_vpn.prom
      tmp="$out.$$"
      {
        if systemctl is-active --quiet xray; then echo 'family_vpn_xray_up 1'; else echo 'family_vpn_xray_up 0'; fi
        for port in ${toString config.networking.firewall.allowedTCPPorts}; do
          if [ -n "$(ss -lntH "sport = :$port")" ]; then v=1; else v=0; fi
          echo "family_vpn_port_listening{port=\"$port\"} $v"
        done
        echo "family_vpn_failed_units $(systemctl --failed --no-legend | grep -c . || true)"
        echo "family_vpn_root_disk_used_percent $(df --output=pcent / | tail -n 1 | tr -dc '0-9')"
        if [ "$(readlink /run/booted-system/kernel)" = "$(readlink /run/current-system/kernel)" ]; then r=0; else r=1; fi
        echo "family_vpn_reboot_required $r"
        if stats="$(curl -fsS --max-time 3 http://127.0.0.1:11111/debug/vars 2>/dev/null)"; then
          echo 'family_vpn_xray_metrics_up 1'
          echo "$stats" | jq -r '(.stats.inbound // {}) | to_entries[] | .key as $t | .value | to_entries[]
            | "family_vpn_xray_inbound_bytes_total{inbound=\"\($t)\",direction=\"\(.key)\"} \(.value)"'
        else
          echo 'family_vpn_xray_metrics_up 0'
        fi
        echo "family_vpn_health_last_run_timestamp_seconds $(date +%s)"
      } > "$tmp"
      mv "$tmp" "$out"
    '';
  };
in
{
  # Nothing here is reachable from the Internet: exporters bind to 127.0.0.1 and the firewall has no rule for them.
  # Read them with: ssh -L 9100:127.0.0.1:9100 admin@host   (Xray counters: 127.0.0.1:11111/debug/vars)
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9100;
    openFirewall = false;
    enabledCollectors = [ "systemd" ];
    extraFlags = [ "--collector.textfile.directory=${metricsDir}" ];
  };

  systemd.tmpfiles.rules = [ "d ${metricsDir} 0755 root root -" ];
  environment.systemPackages = [ health ];

  systemd.services.family-vpn-health = {
    description = "Write family VPN health metrics";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${health}/bin/family-vpn-health";
      ReadWritePaths = [ metricsDir ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
  systemd.timers.family-vpn-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "1min"; OnUnitActiveSec = "1min"; };
  };
}
