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
    dotfilesPackages.dotnet-lambda
    dotfilesPackages.dotnet-script
    grpcurl
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

  # Prefer runtimes supplied by Nix or the project's development shell.
  xdg.configFile."vite-plus/config.json".text = builtins.toJSON {
    nodeShimMode = "system_first";
    packageManagerShimModes = {
      npm = "system_first";
      pnpm = "system_first";
    };
  };
}
