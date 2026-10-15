{ ... }:
{
  programs.direnv = {
    enable = true;
    config.global.hide_env_diff = true;
  };

  xdg.configFile."kube/homelab-context.yaml".text = ''
    apiVersion: v1
    kind: Config
    current-context: homelab
  '';
}
