{
  description = "Joseph's multi-host NixOS and cross-platform dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      system = "x86_64-linux";
      mkHost = import ./nix/lib/mk-host.nix { inherit inputs; };
    in
    {
      nixosConfigurations = {
        rocket = mkHost {
          hostSpec = {
            hostName = "rocket";
            inherit system;
            role = "desktop";
            isWork = false;
            desktop = {
              musicOutput = "Lenovo Group Limited LEN P27h-10 0x344D3533";
              dockOutput = null;
              internalDisplay = null;
            };
          };
          modules = [
            ./nix/hosts/rocket
            ./nix/modules/nixos/desktop.nix
            ./nix/modules/nixos/gaming.nix
          ];
          homeModules = [ ./nix/modules/home/desktop.nix ];
        };

        framework = mkHost {
          hostSpec = {
            hostName = "framework";
            inherit system;
            role = "laptop";
            isWork = true;
            desktop = {
              musicOutput = "Dell Inc. DELL P2725D 3S5S864";
              dockOutput = "Dell Inc. DELL P2725D 24CRZ64";
              internalDisplay = {
                name = "eDP-1";
                width = 1920;
                height = 1200;
                refresh = 60.001;
                scale = 1.0;
              };
            };
          };
          modules = [
            ./nix/hosts/framework
            ./nix/modules/nixos/desktop.nix
            ./nix/modules/nixos/laptop.nix
          ];
          homeModules = [ ./nix/modules/home/desktop.nix ];
        };

        karl = mkHost {
          hostSpec = {
            hostName = "karl";
            inherit system;
            role = "server";
            isWork = false;
            desktop = null;
          };
          modules = [
            ./nix/hosts/karl
            ./nix/modules/nixos/server.nix
          ];
        };
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
