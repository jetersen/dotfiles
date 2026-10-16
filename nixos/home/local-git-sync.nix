{ config, lib, ... }:
let
  cfg = config.services.local-git-sync;
in
{
  options.services.local-git-sync = {
    enable = lib.mkEnableOption "Git-aware device continuation";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The local-git-sync package, including its runtime tools.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    # Peers use this stable path even when SSH does not load a login profile.
    home.file.".local/libexec/local-git-sync".source = lib.getExe cfg.package;

    # Keep the exact marker checked by the checkpoint server. Both daemon and
    # SSH payload scopes use this shared budget, including on relay-only hosts.
    xdg.configFile."systemd/user/local-git-sync.slice".source =
      "${cfg.package}/share/local-git-sync/local-git-sync.slice";
    systemd.user.services.local-git-sync = {
      Unit.Description = "Local Git device synchronization";
      Service = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} device-agent --interval 10000";
        Slice = "local-git-sync.slice";
        CPUWeight = 10;
        Nice = 10;
        IOWeight = 10;
        Restart = "on-failure";
        RestartSec = 10;
        KillMode = "control-group";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
