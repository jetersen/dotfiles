{
  dotfilesPackages,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    nodejs_24 # Includes npm.
    pnpm
    python3
    uv
    powershell
    just
    go
    rustc
    cargo
    rustfmt
    clippy
    stdenv.cc # Linker for Rust and cgo outside project development shells.
    pkg-config
    bun
    (maven.override { jdk_headless = jdk21; })
    yq-go
    kargo
    sqlcmd
    actionlint
    git-cliff
    ssm-session-manager-plugin
    kubernetes-helm
    kustomize
    fluxcd
    argocd
    talosctl
    kubectx # Includes kubens.
    btop
    dnsutils
    openssl
    zip
    unzip
    ilspycmd
    dotnet-outdated
    csharpier
    dotfilesPackages.snitch
    dotfilesPackages.central-pkg-converter
    dotfilesPackages.dotnet-counters
    dotfilesPackages.dotnet-trace
    dotfilesPackages.dotnet-stack
    dotfilesPackages.apicompat
    dotfilesPackages.dotnet-lambda
    dotfilesPackages.dotnet-script
    grpcurl
    dive
    popeye
    duckdb
    glab
    ansible
    snowflake-cli
    postgresql
    mariadb.client
    crane
    skopeo
    trivy
    dbeaver-bin
    charles
    remmina
    (victorialogs.overrideAttrs (old: {
      pname = "vlogscli";
      subPackages = [ "app/vlogscli" ];
      meta = old.meta // {
        mainProgram = "vlogscli";
      };
    }))
    dotfilesPackages.vite-plus
    dotfilesPackages.topf
    dotfilesPackages.freelens
    (writeShellApplication {
      name = "git-dirty";
      runtimeInputs = [
        bash
        coreutils
        findutils
        git
        gnused
      ];
      text = ''
        exec ${bash}/bin/bash ${../../home/dot_local/bin/executable_git-dirty} "$@"
      '';
    })
  ];

  programs.java = {
    enable = true;
    package = pkgs.jdk21;
  };

  # Prefer runtimes supplied by Nix or the project's development shell.
  xdg.configFile."vite-plus/config.json".text = builtins.toJSON {
    nodeShimMode = "system_first";
    packageManagerShimModes = {
      npm = "system_first";
      pnpm = "system_first";
    };
  };
}
