{
  description = "Joseph's NixOS systems";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixpkgs-unstable.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    aspire = {
      url = "git+https://github.com/microsoft/aspire.git?ref=main&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    aspire-cli-source = {
      url = "file+https://github.com/microsoft/aspire/releases/download/v13.6.2/aspire-cli-linux-x64-13.6.2.tar.gz";
      flake = false;
    };
    comin = {
      url = "git+https://forgejo.jetersen.dev/jetersen/comin.git?ref=dotfiles-v0.14&shallow=1";
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
    crane.url = "git+https://github.com/ipetkov/crane.git?rev=e675a36b7377bebe41d548388a2501cbb16d380d&shallow=1";
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
      inputs.crane.follows = "crane";
      inputs.rust-overlay = {
        url = "git+https://github.com/oxalica/rust-overlay.git?rev=1fb104a12a8667045559b2575d6d448ae2fbd99b&shallow=1";
        inputs.nixpkgs.follows = "nixpkgs";
      };
    };
    pulumi-packages = {
      url = "git+https://github.com/unmango/pulumipkgs.git?rev=c91b9d969e70e698dd28de5c47426e079fad7c12&shallow=1";
      flake = false;
    };
    dms-openvpn3 = {
      url = "git+https://github.com/jetersen/dms-openvpn3.git?rev=cc46cd65657b824f19c2b3a919990d10d890f8aa&shallow=1";
      flake = false;
    };
    dms-storage-monitor = {
      url = "git+https://github.com/jetersen/dms-storage-monitor.git?rev=1732a2de807e64e98480d46b75ae76d9bb34b092&shallow=1";
      flake = false;
    };
    skill-finder = {
      url = "git+https://github.com/vercel-labs/skills.git?rev=a80e4c9d12d607631249d4d7d059f835d4b2f13a&shallow=1";
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
      url = "git+https://github.com/pulumi/upgrade-provider.git?rev=1302b9e468d15195492fcc9815c78369c5d44d2e&shallow=1";
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
      url = "git+https://github.com/duxlabs-dev/dux-shell.git?ref=refs/tags/v2.0.0&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dank-qml-common = {
        url = "git+https://github.com/duxlabs-dev/dux-qml-common.git?rev=ebf5e6c002da1bdaa4aaa2f319fea7b8507abc42&shallow=1";
        flake = false;
      };
      inputs.flake-compat = {
        url = "git+https://github.com/NixOS/flake-compat.git?rev=5edf11c44bc78a0d334f6334cdaf7d60d732daab&shallow=1";
        flake = false;
      };
    };
    dank-greeter = {
      url = "git+https://github.com/duxlabs-dev/dux-greeter.git?ref=refs/tags/v2.0.0&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dank-qml-common = {
        url = "git+https://github.com/duxlabs-dev/dux-qml-common.git?rev=ebf5e6c002da1bdaa4aaa2f319fea7b8507abc42&shallow=1";
        flake = false;
      };
    };
    dux-files = {
      url = "git+https://github.com/duxlabs-dev/dux-files.git?ref=refs/tags/v2.0.0&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dank-qml-common.follows = "dms/dank-qml-common";
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
      lanzabooteSystemProfiles = import ./nixos/lib/lanzaboote-system-profiles.nix {
        inherit inputs pkgs;
      };
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
      checks.x86_64-linux = import ./nixos/tests {
        inherit pkgs pkgsUnstable inputs;
      };
      packages.x86_64-linux.installer-iso =
        inputs.self.nixosConfigurations.installer.config.system.build.isoImage;
      packages.x86_64-linux.nixos-anywhere = pkgs.nixos-anywhere;
      packages.x86_64-linux.lanzaboote-system-profiles = lanzabooteSystemProfiles.packages.lzbt;
      packages.x86_64-linux.lanzaboote-system-profiles-vm =
        lanzabooteSystemProfiles.checks.tests.system-profiles;
      packages.x86_64-linux.lanzaboote-system-profiles-boot-counting-vm =
        lanzabooteSystemProfiles.checks.tests.system-profiles-boot-counting;
      packages.x86_64-linux.lanzaboote-protected-system-vm =
        lanzabooteSystemProfiles.checks.tests.protected-system;
      packages.x86_64-linux.ssh-to-age = pkgs.ssh-to-age;
      packages.x86_64-linux.vite-plus = pkgs.callPackage ./nixos/packages/vite-plus.nix { };
      packages.x86_64-linux.proton-ge = pkgs.callPackage ./nixos/packages/proton-ge.nix { };
      packages.x86_64-linux.microfetch = pkgs.callPackage ./nixos/packages/microfetch.nix { };
      packages.x86_64-linux.pc2mqtt = pkgs.callPackage ./nixos/packages/pc2mqtt.nix {
        craneLib = inputs.crane.mkLib pkgs;
      };
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
      # Upstream's Nix manifest can lag behind its published CLI release.
      packages.x86_64-linux.aspire-cli = inputs.aspire.packages.x86_64-linux.aspire-cli.overrideAttrs {
        src = inputs.aspire-cli-source;
        # File inputs have no extension. Isolate the archive contents so upstream's
        # recursive install does not copy Nix's build-directory env-vars file.
        unpackCmd = ''mkdir source; tar -xzf "$curSrc" -C source'';
        sourceRoot = "source";
        version = builtins.head (
          builtins.match ".*/v([^/]+)/[^/]+[.]tar[.]gz" locked.nodes.aspire-cli-source.locked.url
        );
      };
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
              inputs.dux-files.nixosModules.default
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
            lanzabooteSystemProfiles.nixosModules.lanzaboote
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
                dmsCommonSource = inputs.dms.inputs.dank-qml-common;
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
