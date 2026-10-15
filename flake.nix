{
  description = "Joseph's NixOS systems";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager.git?ref=release-26.05&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "git+https://github.com/nix-community/disko.git?ref=master&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "git+https://github.com/Mic92/sops-nix.git?ref=master&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "git+https://github.com/NixOS/nixos-hardware.git?ref=master&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dms = {
      url = "git+https://github.com/AvengeMedia/DankMaterialShell.git?ref=refs/tags/v1.6.3&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dank-greeter = {
      url = "git+https://github.com/AvengeMedia/dank-greeter.git?ref=refs/tags/v1.6.2&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dank-qml-common = {
        url = "git+https://github.com/AvengeMedia/dank-qml-common.git?rev=26396ce432d6c71c3f5367438f96f4a8d667e160&shallow=1";
        flake = false;
      };
    };
    zen-browser = {
      url = "git+https://github.com/0xc000022070/zen-browser-flake.git?ref=main&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      disko,
      sops-nix,
      nixos-hardware,
      ...
    }:
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;
      packages.x86_64-linux.installer-iso =
        inputs.self.nixosConfigurations.installer.config.system.build.isoImage;
      packages.x86_64-linux.nixos-anywhere = nixpkgs.legacyPackages.x86_64-linux.nixos-anywhere;
      packages.x86_64-linux.ssh-to-age = nixpkgs.legacyPackages.x86_64-linux.ssh-to-age;

      nixosModules = {
        common = {
          imports = [
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            ./nixos/modules/common.nix
          ];
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.joseph = import ./nixos/home/joseph.nix;
          };
        };
        desktop =
          {
            pkgs,
            lib,
            ...
          }:
          {
            imports = [
              ./nixos/modules/desktop.nix
              inputs.dank-greeter.nixosModules.default
            ];
            programs.dms-shell.package = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.default;
            environment.systemPackages = [
              inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta
              (pkgs.writeShellScriptBin "zen-browser" ''
                exec ${lib.getExe inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta} "$@"
              '')
            ];
            home-manager.extraSpecialArgs = {
              dmsSource = inputs.dms;
            };
          };
        encrypted-laptop = {
          imports = [
            disko.nixosModules.disko
            ./nixos/modules/encrypted-laptop.nix
          ];
        };
        framework = {
          imports = [
            inputs.self.nixosModules.common
            inputs.self.nixosModules.desktop
            inputs.self.nixosModules.encrypted-laptop
            nixos-hardware.nixosModules.framework-intel-core-ultra-series3
            ./nixos/hosts/framework
          ];
        };
      };

      nixosConfigurations = {
        framework = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ inputs.self.nixosModules.framework ];
        };
        installer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nixos/installer.nix ];
        };
      };
    };
}
