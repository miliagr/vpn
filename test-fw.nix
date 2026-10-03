{ pkgs ? import <nixpkgs> {} }:
let
  eval = pkgs.lib.evalModules {
    modules = [
      (import (pkgs.path + "/nixos/modules/services/networking/nat.nix"))
      (import (pkgs.path + "/nixos/modules/services/networking/firewall.nix"))
      {
        networking.nat.enable = true;
        networking.nat.internalInterfaces = [ "wg0" ];
        networking.firewall.enable = true;
      }
    ];
  };
in
eval.config.networking.firewall.extraCommands
