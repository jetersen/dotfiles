{ config, lib, ... }:
{
  programs.direnv = {
    enable = true;
    config.global.hide_env_diff = true;
  };

  xdg.configFile."powershell/profile.ps1".text = lib.mkAfter ''
    & '${lib.getExe config.programs.direnv.package}' hook pwsh | Out-String | Invoke-Expression
  '';

  xdg.configFile."kube/homelab-context.yaml".text = ''
    apiVersion: v1
    kind: Config
    current-context: homelab
  '';
}
