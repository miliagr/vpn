{ config, lib, modulesPath, name, hostCfg, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  nixpkgs.hostPlatform = hostCfg.system or "x86_64-linux";
  networking.hostName = name;
  system.stateVersion = "25.05";

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "virtio_blk" "ahci" "xhci_pci" "sd_mod" "sr_mod" ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keyFiles = [ ../hosts/authorized_keys ];
  assertions = [{
    assertion = lib.hasInfix "ssh-" (builtins.readFile ../hosts/authorized_keys);
    message = "hosts/authorized_keys has no SSH public key; refusing to build a host you could not log in to.";
  }];

  networking.firewall.enable = true; # openssh opens its own port; xray.nix opens the VPN ports

  # BBR gives noticeably better throughput on lossy mobile paths.
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  zramSwap.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
  services.journald.settings.Journal.SystemMaxUse = "200M";
}
