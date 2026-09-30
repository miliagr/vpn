{ hostCfg, ... }:
{
  # GPT with both a BIOS-boot and an EFI partition, so it boots on either kind of VPS.
  disko.devices.disk.main = {
    type = "disk";
    device = hostCfg.disk or "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        boot = { size = "1M"; type = "EF02"; priority = 1; };
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };
  };
}
