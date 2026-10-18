{
  description = "Joseph's NixOS systems";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixpkgs-unstable.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    comin = {
      url = "git+https://github.com/nlewo/comin.git?ref=refs/tags/v0.14.0&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
      inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager.git?ref=release-26.05&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
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
    dms-storage-monitor = {
      url = "git+https://github.com/jetersen/dms-storage-monitor.git?rev=8dbf7f2484b0f81683add744664b3bb17c1389e5&shallow=1";
      flake = false;
    };
    skill-finder = {
      url = "git+https://github.com/vercel-labs/skills.git?rev=13e4063a1cf913f5606d57d42ab83a86f5001e04&shallow=1";
      flake = false;
    };
    lambda-tools-source = {
      url = "file+https://api.nuget.org/v3-flatcontainer/amazon.lambda.tools/7.0.0/amazon.lambda.tools.7.0.0.nupkg";
      flake = false;
    };
    dotnet-script-source = {
      url = "file+https://api.nuget.org/v3-flatcontainer/dotnet-script/2.0.1/dotnet-script.2.0.1.nupkg";
      flake = false;
    };
    central-pkg-converter-source = {
      url = "file+https://api.nuget.org/v3-flatcontainer/centralisedpackageconverter/1.0.74/centralisedpackageconverter.1.0.74.nupkg";
      flake = false;
    };
    dotnet-counters-source = {
      url = "file+https://api.nuget.org/v3-flatcontainer/dotnet-counters/10.0.750501/dotnet-counters.10.0.750501.nupkg";
      flake = false;
    };
    dotnet-trace-source = {
      url = "file+https://api.nuget.org/v3-flatcontainer/dotnet-trace/10.0.750501/dotnet-trace.10.0.750501.nupkg";
      flake = false;
    };
    dotnet-stack-source = {
      url = "file+https://api.nuget.org/v3-flatcontainer/dotnet-stack/10.0.750501/dotnet-stack.10.0.750501.nupkg";
      flake = false;
    };
    apicompat-source = {
      url = "file+https://api.nuget.org/v3-flatcontainer/microsoft.dotnet.apicompat.tool/10.0.402/microsoft.dotnet.apicompat.tool.10.0.402.nupkg";
      flake = false;
    };
    pulumi-schema-tools-source = {
      url = "git+https://github.com/pulumi/schema-tools.git?ref=refs/tags/v0.8.1&shallow=1";
      flake = false;
    };
    pulumi-upgrade-provider-source = {
      url = "git+https://github.com/pulumi/upgrade-provider.git?rev=dba6f8dcc4fb020fd36b115c7efcfc278bb7eb14&shallow=1";
      flake = false;
    };
    powershell-posh-git = {
      url = "git+https://github.com/dahlbyk/posh-git.git?ref=refs/tags/v1.1.0&shallow=1";
      flake = false;
    };
    powershell-cd-extras = {
      url = "git+https://github.com/nickcox/cd-extras.git?ref=refs/tags/v3.0.0&shallow=1";
      flake = false;
    };
    powershell-childitemcolor = {
      url = "git+https://github.com/joonro/Get-ChildItemColor.git?ref=refs/tags/v3.5.2&shallow=1";
      flake = false;
    };
    snitch-source = {
      url = "git+https://github.com/jetersen/snitch.git?ref=integration&shallow=1";
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
      ...
    }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      pkgsUnstable = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
      pkgsAi = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "claude-code";
      };
      locked = builtins.fromJSON (builtins.readFile ./flake.lock);
      nugetTool =
        inputName: pname: nugetName:
        pkgs.callPackage ./nixos/packages/nuget-tool.nix {
          inherit pname nugetName;
          source = inputs.${inputName};
          # Keep the URL in flake.nix as the single version pin for Renovate.
          version = builtins.head (
            builtins.match ".*/([^/]+)/[^/]+[.]nupkg" locked.nodes.${inputName}.locked.url
          );
        };
    in
    {
      formatter.x86_64-linux = pkgs.nixfmt;
      packages.x86_64-linux.installer-iso =
        inputs.self.nixosConfigurations.installer.config.system.build.isoImage;
      packages.x86_64-linux.nixos-anywhere = pkgs.nixos-anywhere;
      packages.x86_64-linux.ssh-to-age = pkgs.ssh-to-age;
      packages.x86_64-linux.vite-plus = pkgs.callPackage ./nixos/packages/vite-plus.nix { };
      packages.x86_64-linux.proton-ge = pkgs.callPackage ./nixos/packages/proton-ge.nix { };
      packages.x86_64-linux.microfetch = pkgs.callPackage ./nixos/packages/microfetch.nix { };
      packages.x86_64-linux.topf = pkgs.callPackage ./nixos/packages/topf.nix { };
      packages.x86_64-linux.freelens = pkgs.callPackage ./nixos/packages/freelens.nix { };
      packages.x86_64-linux.dotnet-lambda =
        nugetTool "lambda-tools-source" "dotnet-lambda"
          "Amazon.Lambda.Tools";
      packages.x86_64-linux.dotnet-script =
        nugetTool "dotnet-script-source" "dotnet-script"
          "dotnet-script";
      packages.x86_64-linux.central-pkg-converter =
        nugetTool "central-pkg-converter-source" "central-pkg-converter"
          "centralisedpackageconverter";
      packages.x86_64-linux.dotnet-counters =
        nugetTool "dotnet-counters-source" "dotnet-counters"
          "dotnet-counters";
      packages.x86_64-linux.dotnet-trace = nugetTool "dotnet-trace-source" "dotnet-trace" "dotnet-trace";
      packages.x86_64-linux.dotnet-stack = nugetTool "dotnet-stack-source" "dotnet-stack" "dotnet-stack";
      packages.x86_64-linux.apicompat =
        nugetTool "apicompat-source" "apicompat"
          "microsoft.dotnet.apicompat.tool";
      packages.x86_64-linux.snitch = pkgs.callPackage ./nixos/packages/snitch.nix {
        source = inputs.snitch-source;
      };
      packages.x86_64-linux.varlock = pkgs.callPackage ./nixos/packages/varlock.nix { };
      packages.x86_64-linux.codex = inputs.nixpkgs-master.legacyPackages.x86_64-linux.codex;
      packages.x86_64-linux.t3code = pkgs.callPackage ./nixos/packages/t3code.nix {
        codex = inputs.self.packages.x86_64-linux.codex;
        claude-code = pkgsAi.claude-code.override {
          manifest = builtins.fromJSON (builtins.readFile ./nixos/packages/claude-code-manifest.json);
        };
      };
      packages.x86_64-linux.pulumi-schema-tools =
        pkgs.callPackage ./nixos/packages/pulumi-schema-tools.nix
          {
            source = inputs.pulumi-schema-tools-source;
            version = nixpkgs.lib.removePrefix "refs/tags/v" locked.nodes.pulumi-schema-tools-source.original.ref;
          };
      packages.x86_64-linux.pulumi-upgrade-provider =
        pkgs.callPackage ./nixos/packages/pulumi-upgrade-provider.nix
          {
            source = inputs.pulumi-upgrade-provider-source;
          };
      devShells.x86_64-linux = import ./nixos/dev-shells.nix {
        inherit pkgs pkgsUnstable;
        dotfilesPackages = inputs.self.packages.x86_64-linux;
      };
      packages.x86_64-linux.ci-tools = pkgs.buildEnv {
        name = "dotfiles-ci-tools";
        paths = [
          (pkgs.python3.withPackages (python: [ python.paho-mqtt ]))
          pkgs.attic-client
          inputs.nixpkgs-master.legacyPackages.x86_64-linux.nixVersions.latest
        ];
        pathsToLink = [ "/bin" ];
      };
      packages.x86_64-linux.pulumi-cli = pkgs.callPackage ./nixos/packages/pulumi-cli.nix { };
      packages.x86_64-linux.pulumi-language-dotnet =
        pkgs.callPackage "${inputs.pulumi-packages}/pkgs/languages/pulumi-dotnet/package.nix"
          { };

      nixosModules = {
        common = { pkgs, ... }: {
          system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
          # Includes the upstream IPv6 link-local batching fix; no custom daemon.
          services.tailscale.package =
            inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.tailscale;
          imports = [
            sops-nix.nixosModules.sops
            ./nixos/modules/common.nix
          ];
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
            programs.dms-shell.package =
              lib.mkDefault
                inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.default;
            environment.systemPackages = [
              inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta
              (pkgs.writeShellScriptBin "zen-browser" ''
                exec ${lib.getExe inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta} "$@"
              '')
            ];
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
        workstation =
          { pkgs, ... }:
          {
            imports = [
              inputs.self.nixosModules.common
              inputs.self.nixosModules.desktop
              home-manager.nixosModules.home-manager
              inputs.comin.nixosModules.comin
              ./nixos/profiles/workstation.nix
            ];
            programs.command-not-found.enable = false;
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              sharedModules = [ inputs.nix-index-database.homeModules.default ];
              extraSpecialArgs = {
                nixIndexPackages = inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system};
                pkgsMaster = import inputs.nixpkgs-master {
                  inherit (pkgs.stdenv.hostPlatform) system;
                  config.allowUnfree = true;
                };
                pkgsUnstable = import inputs.nixpkgs-unstable {
                  inherit (pkgs.stdenv.hostPlatform) system;
                  config.allowUnfree = true;
                };
                dotfilesPackages = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
                dmsSource = inputs.dms;
                storageMonitorSource = inputs.dms-storage-monitor;
                powershellModules = {
                  posh-git = inputs.powershell-posh-git + "/src";
                  cd-extras = inputs.powershell-cd-extras + "/cd-extras";
                  Get-ChildItemColor = inputs.powershell-childitemcolor + "/src";
                };
                agentSkillSources = {
                  find-skills = inputs.skill-finder + "/skills/find-skills";
                };
              };
            };
          };
        work = {
          imports = [
            inputs.self.nixosModules.company-vpn
            ./nixos/profiles/work.nix
          ];
        };
        gaming = import ./nixos/profiles/gaming.nix;
        framework = import ./nixos/hosts/framework;
        rocket = import ./nixos/hosts/rocket;
      };

      nixosConfigurations = {
        rocket = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ inputs.self.nixosModules.rocket ];
        };
        framework = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ inputs.self.nixosModules.framework ];
        };
        installer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nixos/installer.nix ];
        };
      };
    };
}
