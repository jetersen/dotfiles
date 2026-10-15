{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  home.activation.cloudConfigDirectories =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        run ${pkgs.coreutils}/bin/install -d -m 700 \
          ${config.home.homeDirectory}/.aws ${config.home.homeDirectory}/.kube
      '';

  home.file = {
    ".aws/config".source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.aws-config.path;
    ".kube/config".source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.kube-config.path;
  };
}
