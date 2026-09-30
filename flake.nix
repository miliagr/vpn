{
  description = "Private family VPN on NixOS";

  inputs = {
    # Xray's current config syntax ("raw", "target") needs a recent xray; flake.lock pins the exact revision.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, ... }:
    let
      hosts = builtins.fromJSON (builtins.readFile ./hosts/hosts.json);
    in
    {
      # One NixOS system per entry in hosts/hosts.json.
      nixosConfigurations = nixpkgs.lib.mapAttrs
        (name: hostCfg: nixpkgs.lib.nixosSystem {
          specialArgs = { inherit name hostCfg; };
          modules = [
            disko.nixosModules.disko
            ./nix/common.nix
            ./nix/disk.nix
            ./nix/security.nix
            ./nix/monitoring.nix
            ./nix/xray.nix
          ];
        })
        hosts;
    };
}
