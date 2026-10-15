{
  dotnetLambda,
  dotnetScript,
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
    dotnetLambda
    dotnetScript
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
    (callPackage ../packages/vite-plus.nix { })
    (callPackage ../packages/topf.nix { })
    (callPackage ../packages/freelens.nix { })
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
