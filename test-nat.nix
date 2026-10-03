{ pkgs ? import <nixpkgs> {} }:
let
  eval = pkgs.lib.evalModules {
    modules = [
      (import (pkgs.path + "/nixos/modules/services/networking/nat.nix"))
      {
        networking.nat.enable = true;
        networking.nat.internalInterfaces = [ "wg0" ];
      }
    ];
  };
in
eval.config.networking.firewall.extraCommands
