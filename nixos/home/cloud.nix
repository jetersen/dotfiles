{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  codeartifactProvider = pkgs.callPackage ../packages/aws-codeartifact-nuget.nix { };
  pluginDirectory = ".nuget/plugins/netcore/AWS.CodeArtifact.NuGetCredentialProvider";
  workRegistry = "156445482446.dkr.ecr.eu-west-1.amazonaws.com";
  # The shared registry belongs to the default account even from production shells.
  ecrHelper = pkgs.writeShellScriptBin "docker-credential-ecr-msp" ''
    export AWS_PROFILE=default
    exec ${pkgs.amazon-ecr-credential-helper}/bin/docker-credential-ecr-login "$@"
  '';
  configureDocker = pkgs.writeShellApplication {
    name = "configure-docker";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config_dir="$HOME/.docker"
      install -d -m 700 "$config_dir"
      settings="$config_dir/config.json"
      current="$settings"
      if [[ ! -s "$current" ]]; then current=${pkgs.writeText "docker-empty.json" "{}"}; fi
      temporary=$(mktemp "$config_dir/.config.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq '.credHelpers["${workRegistry}"] = "ecr-msp"' "$current" > "$temporary"
      chmod 600 "$temporary"
      mv "$temporary" "$settings"
    '';
  };
in
{
  home.packages = [
    pkgs.amazon-ecr-credential-helper
    ecrHelper
  ];

  home.activation.cloudConfigDirectories =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        run ${pkgs.coreutils}/bin/install -d -m 700 \
          ${config.home.homeDirectory}/.aws ${config.home.homeDirectory}/.kube
      '';

  home.file = {
    ".aws/config".source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.aws-config.path;
    ".kube/config".source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.kube-config.path;
    "${pluginDirectory}" = {
      source = "${codeartifactProvider}/lib/nuget/plugins/netcore/AWS.CodeArtifact.NuGetCredentialProvider";
      recursive = true;
    };
    "${pluginDirectory}/configuration.json".text = builtins.toJSON {
      # Delegate modern SSO session handling to the installed AWS CLI.
      DefaultProfile = "default-process";
      SourceProfileOverrides = null;
    };
    # Additional user configuration leaves NuGet's main config writable.
    ".nuget/NuGet/config/msp.config".text = ''
      <?xml version="1.0" encoding="utf-8"?>
      <configuration>
        <packageSources>
          <add key="msp" value="https://msp-156445482446.d.codeartifact.eu-west-1.amazonaws.com/nuget/msp/v3/index.json" />
        </packageSources>
        <packageSourceMapping>
          <packageSource key="nuget.org">
            <package pattern="*" />
          </packageSource>
          <packageSource key="msp">
            <package pattern="Msp.*" />
            <package pattern="MovieStarPlanet.*" />
          </packageSource>
        </packageSourceMapping>
      </configuration>
    '';
  };

  home.activation.configureDocker = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureDocker}
  '';
}
