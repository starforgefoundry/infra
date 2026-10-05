{
  description = "Homelab NixOS";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-stable,
      disko,
      ...
    }:
    let
      utils = import ./lib/utils.nix { inherit nixpkgs nixpkgs-stable; };
      inherit (utils) mkHost;
    in
    {
      nixosConfigurations.shop-server = mkHost {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./hosts/shop-server/configuration.nix
        ];
      };
      nixosConfigurations.vps-server = mkHost {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./hosts/vps-server/configuration.nix
        ];
      };
    };
}
