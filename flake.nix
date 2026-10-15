{
  description = "Joseph's NixOS systems";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
    nixpkgs-unstable.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    comin = {
      url = "git+https://github.com/nlewo/comin.git?ref=refs/tags/v0.14.0&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    };
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
    lanzaboote = {
      url = "git+https://github.com/nix-community/lanzaboote.git?ref=refs/tags/v1.2.0&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.crane.url = "git+https://github.com/ipetkov/crane.git?rev=73b980519cefc727a5f6cc8e5c0947a2f9be6edd&shallow=1";
      inputs.rust-overlay = {
        url = "git+https://github.com/oxalica/rust-overlay.git?rev=1fb104a12a8667045559b2575d6d448ae2fbd99b&shallow=1";
        inputs.nixpkgs.follows = "nixpkgs";
      };
    };
    pulumi-packages = {
      url = "git+https://github.com/unmango/pulumipkgs.git?rev=e51aea7d9473a8dde80c23081c522ac967b93988&shallow=1";
      flake = false;
    };
    dms-openvpn3 = {
      url = "git+https://github.com/jetersen/dms-openvpn3.git?rev=f9e01be5ca81840f1b0e5322d40342cbce96e09c&shallow=1";
      flake = false;
    };
    skill-finder = {
      url = "git+https://github.com/vercel-labs/skills.git?rev=13e4063a1cf913f5606d57d42ab83a86f5001e04&shallow=1";
      flake = false;
    };
    skill-unslop = {
      url = "git+https://github.com/cursor/plugins.git?rev=99743e9c151c8537cbbf1f98bb38f34ef3368453&shallow=1";
      flake = false;
    };
    skill-rea = {
      url = "git+https://github.com/morluto/rea.git?rev=3406dc4d85bf29414319b33b98bd1421d573f663&shallow=1";
      flake = false;
    };
    dms = {
      url = "git+https://github.com/AvengeMedia/DankMaterialShell.git?ref=refs/tags/v1.6.3&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dank-qml-common = {
        url = "git+https://github.com/AvengeMedia/dank-qml-common.git?rev=1ae722232da7110d26cd2c355b6615e078e94197&shallow=1";
        flake = false;
      };
      inputs.flake-compat = {
        url = "git+https://github.com/NixOS/flake-compat.git?rev=5edf11c44bc78a0d334f6334cdaf7d60d732daab&shallow=1";
        flake = false;
      };
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
      packages.x86_64-linux.vite-plus =
        nixpkgs.legacyPackages.x86_64-linux.callPackage ./nixos/packages/vite-plus.nix
          { };
      packages.x86_64-linux.topf =
        nixpkgs.legacyPackages.x86_64-linux.callPackage ./nixos/packages/topf.nix
          { };
      packages.x86_64-linux.freelens =
        nixpkgs.legacyPackages.x86_64-linux.callPackage ./nixos/packages/freelens.nix
          { };
      packages.x86_64-linux.ci-tools = nixpkgs.legacyPackages.x86_64-linux.buildEnv {
        name = "dotfiles-ci-tools";
        paths = with nixpkgs.legacyPackages.x86_64-linux; [
          attic-client
          jq
          openssh
        ];
      };
      packages.x86_64-linux.pulumi-cli =
        nixpkgs.legacyPackages.x86_64-linux.callPackage ./nixos/packages/pulumi-cli.nix
          { };
      packages.x86_64-linux.pulumi-language-dotnet =
        nixpkgs.legacyPackages.x86_64-linux.callPackage
          "${inputs.pulumi-packages}/pkgs/languages/pulumi-dotnet/package.nix"
          { };

      nixosModules = {
        common = {
          system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
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
              aiPkgs = import inputs.nixpkgs-unstable {
                inherit (pkgs.stdenv.hostPlatform) system;
                config.allowUnfree = true;
              };
              dmsSource = inputs.dms;
              agentSkillSources = {
                find-skills = inputs.skill-finder + "/skills/find-skills";
                unslop = inputs.skill-unslop + "/pstack/skills/unslop";
                reverse-engineer-anything = inputs.skill-rea + "/.agents/skills/reverse-engineer-anything";
              };
              pulumiCli = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pulumi-cli;
              pulumiDotnet = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pulumi-language-dotnet;
            };
          };
        encrypted-laptop = {
          imports = [
            disko.nixosModules.disko
            ./nixos/modules/encrypted-laptop.nix
          ];
        };
        secure-boot = {
          imports = [
            inputs.lanzaboote.nixosModules.lanzaboote
            ./nixos/modules/secure-boot.nix
          ];
        };
        company-vpn = {
          imports = [ ./nixos/modules/company-vpn.nix ];
          home-manager.extraSpecialArgs.openvpnPluginSource = inputs.dms-openvpn3;
        };
        framework = {
          imports = [
            inputs.self.nixosModules.common
            inputs.self.nixosModules.desktop
            inputs.self.nixosModules.encrypted-laptop
            inputs.self.nixosModules.secure-boot
            inputs.self.nixosModules.company-vpn
            inputs.comin.nixosModules.comin
            ./nixos/modules/gitops.nix
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
