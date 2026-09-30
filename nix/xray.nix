{ config, lib, pkgs, ... }:
let
  cfg = config.familyVpn;

  # Reuse the single Xray template: __NAME__ placeholders become ${NAME} for envsubst.
  template = pkgs.runCommand "xray-template.json" { } ''
    sed -E 's/__([A-Z_]+)__/''${\1}/g' ${../server/xray-server.template.json} > $out
  '';

  required = [ "VLESS_UUID" "REALITY_PRIVATE_KEY" "SHORT_ID" "REALITY_DEST" "REALITY_SERVER_NAME" "XHTTP_PATH" "UNIVERSAL_PORT" "XHTTP_PORT" ];

  # Renders the config from the environment into $1 and validates it. Used before every (re)start.
  xrayRender = pkgs.writeShellScriptBin "xray-render" ''
    set -euo pipefail
    umask 077
    for v in ${lib.concatStringsSep " " required}; do
      [ -n "''${!v:-}" ] || { echo "xray-render: $v is not set" >&2; exit 1; }
    done
    ${pkgs.gettext}/bin/envsubst < ${template} > "$1"
    ${pkgs.xray}/bin/xray run -test -format json -config "$1" >/dev/null
  '';
in
{
  options.familyVpn = {
    universalPort = lib.mkOption { type = lib.types.port; default = 443; };
    xhttpPort = lib.mkOption { type = lib.types.port; default = 8443; };
    secretsFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/family-vpn/xray.env";
      description = "Runtime-only env file with per-host secrets; pushed by scripts/nix-push-secrets.sh, never in the Nix store.";
    };
  };

  config = {
    environment.systemPackages = [ xrayRender ];
    networking.firewall.allowedTCPPorts = [ cfg.universalPort cfg.xhttpPort ];

    systemd.services.xray = {
      description = "Xray (VLESS + REALITY) for the family VPN";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = cfg.secretsFile; # skipped cleanly until secrets are pushed
      serviceConfig = {
        DynamicUser = true;
        EnvironmentFile = cfg.secretsFile;
        Environment = [ "UNIVERSAL_PORT=${toString cfg.universalPort}" "XHTTP_PORT=${toString cfg.xhttpPort}" ];
        RuntimeDirectory = "xray";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = "${xrayRender}/bin/xray-render /run/xray/config.json";
        ExecStart = "${pkgs.xray}/bin/xray run -config /run/xray/config.json";
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
        UMask = "0077";
        LimitNOFILE = 65536;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
