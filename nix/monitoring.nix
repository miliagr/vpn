{ config, lib, pkgs, ... }:
let
  cfg = config.vpn;
  metricsDir = "/var/lib/vpn-metrics";

  # Writes Prometheus textfile metrics; node_exporter (localhost only) serves them.
  # Only aggregate per-inbound byte counters are read from Xray, never per-client or per-destination data.
  health = pkgs.writeShellApplication {
    name = "vpn-health";
    runtimeInputs = with pkgs; [ coreutils iproute2 systemd jq curl gnugrep ];
    text = ''
      out=${metricsDir}/vpn.prom
      hist=${metricsDir}/history.csv
      tmp="$out.$$"
      now=$(date +%s)

      xray_up=0
      if systemctl is-active --quiet xray; then xray_up=1; fi

      vpn_ports_ok=1
      port_lines=""
      for port in ${toString [ cfg.universalPort cfg.xhttpPort ]}; do
        if [ -n "$(ss -lntH "sport = :$port")" ]; then v=1; else v=0; vpn_ports_ok=0; fi
        port_lines="$port_lines
      vpn_port_listening{port=\"$port\"} $v"
      done
      vpn_up=$((xray_up * vpn_ports_ok))

      # Approximate "online": distinct source IPs with an established VPN connection. Only the count is kept, never the addresses.
      sockets=$(ss -ntH state established "( sport = :${toString cfg.universalPort} or sport = :${toString cfg.xhttpPort} )")
      conns=$(printf '%s\n' "$sockets" | grep -c . || true)
      online=$(printf '%s\n' "$sockets" | awk '{print $4}' | sed -E 's/:[0-9]+$//' | sort -u | grep -c . || true)

      iface=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}' || true)
      rx=0; tx=0
      if [ -n "$iface" ] && [ -r "/sys/class/net/$iface/statistics/rx_bytes" ]; then
        rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
        tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
      fi

      {
        echo "vpn_xray_up $xray_up"
        echo "vpn_up $vpn_up"
        echo "$port_lines" | grep .
        echo "vpn_established_connections $conns"
        echo "vpn_online_source_ips $online"
        echo "vpn_net_rx_bytes_total{iface=\"$iface\"} $rx"
        echo "vpn_net_tx_bytes_total{iface=\"$iface\"} $tx"
        echo "vpn_failed_units $(systemctl --failed --no-legend | grep -c . || true)"
        echo "vpn_root_disk_used_percent $(df --output=pcent / | tail -n 1 | tr -dc '0-9')"
        if [ "$(readlink /run/booted-system/kernel)" = "$(readlink /run/current-system/kernel)" ]; then r=0; else r=1; fi
        echo "vpn_reboot_required $r"
        if stats="$(curl -fsS --max-time 3 http://127.0.0.1:11111/debug/vars 2>/dev/null)"; then
          echo 'vpn_xray_metrics_up 1'
          echo "$stats" | jq -r '(.stats.inbound // {}) | to_entries[] | .key as $t | .value | to_entries[]
            | "vpn_xray_inbound_bytes_total{inbound=\"\($t)\",direction=\"\(.key)\"} \(.value)"'
        else
          echo 'vpn_xray_metrics_up 0'
        fi
        echo "vpn_health_last_run_timestamp_seconds $now"
      } > "$tmp"
      mv "$tmp" "$out"

      # One line per minute, kept for 7 days: ts,vpn_up,online_source_ips,connections,rx_bytes,tx_bytes (cumulative counters).
      echo "$now,$vpn_up,$online,$conns,$rx,$tx" >> "$hist"
      tail -n 10080 "$hist" > "$hist.$$" && mv "$hist.$$" "$hist"
      chmod 0644 "$hist"
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

  systemd.services.vpn-health = {
    description = "Write VPN health metrics";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${health}/bin/vpn-health";
      ReadWritePaths = [ metricsDir ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
  systemd.timers.vpn-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "1min"; OnUnitActiveSec = "1min"; };
  };
}
