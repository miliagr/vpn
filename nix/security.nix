{ config, lib, pkgs, ... }:
let
  cfg = config.familyVpn;
  sshPort = toString (builtins.head config.services.openssh.ports);
  sshAllowed = map lib.strings.trim (lib.filter
    (l: builtins.match "[[:space:]]*(#.*)?" l == null)
    (lib.splitString "\n" (builtins.readFile ../hosts/ssh_allowed_ips)));
  validSource = ip: builtins.match "[0-9a-fA-F:.]+(/[0-9]+)?" ip != null;
  sshRule = ip: "${if lib.hasInfix ":" ip then "ip6tables" else "iptables"} -A nixos-fw -p tcp -s ${ip} --dport ${sshPort} -j nixos-fw-accept";
  blockedProtocols = [ "dccp" "sctp" "rds" "tipc" "ax25" "netrom" "rose" ];
in
{
  options.familyVpn.adminUser = lib.mkOption {
    type = lib.types.str;
    default = "admin";
    description = "The only account that can log in over SSH; root login is disabled.";
  };

  config = {
    # Accounts are fully declarative: no passwords exist, so access is SSH keys only.
    users.mutableUsers = false;
    users.users.root.hashedPassword = "!";
    users.users.${cfg.adminUser} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      hashedPassword = "!";
      openssh.authorizedKeys.keyFiles = [ ../hosts/authorized_keys ];
    };
    assertions = [
      {
        assertion = sshAllowed != [ ] && lib.all validSource sshAllowed;
        message = "hosts/ssh_allowed_ips must list at least one valid IP/CIDR (otherwise nobody could SSH in) and nothing else.";
      }
      {
        assertion = lib.hasInfix "ssh-" (builtins.readFile ../hosts/authorized_keys);
        message = "hosts/authorized_keys has no SSH public key; refusing to build a host you could not log in to.";
      }
    ];

    security.sudo = {
      enable = true;
      wheelNeedsPassword = false; # no password exists; the SSH key is the credential
      execWheelOnly = true;
    };
    nix.settings = {
      trusted-users = [ "root" cfg.adminUser ];
      allowed-users = [ "@wheel" ];
    };

    services.openssh = {
      enable = true;
      openFirewall = false; # port 22 is opened only for hosts/ssh_allowed_ips, below
      allowSFTP = false;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        AllowUsers = [ cfg.adminUser ];
        MaxAuthTries = 3;
        LoginGraceTime = 20;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
        X11Forwarding = false;
        AllowAgentForwarding = false;
        AllowTcpForwarding = "local"; # needed to reach the localhost-only monitoring ports
      };
    };

    services.fail2ban = {
      enable = true;
      maxretry = 4;
      bantime = "1h";
      bantime-increment = { enable = true; maxtime = "48h"; };
      ignoreIP = sshAllowed;
      jails.sshd.settings = { enabled = true; port = "ssh"; };
    };

    # Default deny inbound. SSH only from hosts/ssh_allowed_ips; the two VPN ports are opened in xray.nix.
    networking.firewall = {
      enable = true;
      allowPing = false;
      logRefusedConnections = false;
      extraCommands = lib.concatMapStringsSep "\n" sshRule sshAllowed;
    };

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv4.tcp_syncookies" = 1;
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "kernel.kptr_restrict" = 2;
      "kernel.dmesg_restrict" = 1;
      "kernel.sysrq" = 0;
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
    };
    boot.extraModprobeConfig = lib.concatMapStringsSep "\n" (m: "install ${m} ${pkgs.coreutils}/bin/false") blockedProtocols;
    security.protectKernelImage = true;

    systemd.coredump.enable = false;
    environment.defaultPackages = lib.mkForce [ ];
    documentation.enable = false;
  };
}
