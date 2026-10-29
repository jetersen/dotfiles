{ pkgs, ... }:
let
  t3Port = 3773;
in
{
  # Preserve localhost clients while admitting remote T3 traffic only over Tailscale.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ t3Port ];

  # Keep the remote server available before desktop login.
  users.users.joseph.linger = true;

  # A user manager can only lower a child's OOM score to the floor granted by
  # root. Keep ordinary user services killable; only T3 opts into immunity.
  systemd.services."user@1000" = {
    overrideStrategy = "asDropin";
    restartIfChanged = false;
    serviceConfig.OOMScoreAdjust = -1000;
  };
  systemd.user.extraConfig = "DefaultOOMScoreAdjust=200";

  # Apply the floor to an existing login without restarting the desktop. Also
  # protect the running server; changing a unit alone does not update its PID.
  system.activationScripts.t3OomProtection = {
    deps = [ "users" ];
    text = ''
      manager_pid=$(${pkgs.systemd}/bin/systemctl show user@1000.service --property=MainPID --value 2>/dev/null || true)
      case "$manager_pid" in
        ""|0) ;;
        *[!0-9]*) echo "Invalid user manager PID" >&2; exit 1 ;;
        *)
          if [ -e "/proc/$manager_pid/oom_score_adj" ]; then
            echo -1000 > "/proc/$manager_pid/oom_score_adj"
          fi
          server_pid=$(${pkgs.util-linux}/bin/runuser -u joseph -- \
            ${pkgs.coreutils}/bin/env XDG_RUNTIME_DIR=/run/user/1000 \
            ${pkgs.systemd}/bin/systemctl --user show t3code.service --property=MainPID --value 2>/dev/null || true)
          case "$server_pid" in
            ""|0) ;;
            *[!0-9]*) echo "Invalid T3 server PID" >&2; exit 1 ;;
            *)
              if [ -e "/proc/$server_pid/oom_score_adj" ]; then
                echo -1000 > "/proc/$server_pid/oom_score_adj"
              fi
              ;;
          esac
          ;;
      esac
    '';
  };

  home-manager.users.joseph =
    { config, dotfilesPackages, ... }:
    let
      t3code = dotfilesPackages.t3code;
      desktop = {
        name = "T3 Code";
        exec = "${pkgs.coreutils}/bin/env T3CODE_DISABLE_AUTO_UPDATE=1 ${t3code}/bin/t3code-desktop %U";
        icon = "t3code";
        terminal = false;
        categories = [ "Development" ];
        mimeType = [ "x-scheme-handler/t3code" ];
        settings.StartupWMClass = "t3code";
      };
    in
    {
      systemd.user.services.t3code = {
        Unit = {
          Description = "T3 Code server";
          After = [ "network.target" ];
          StartLimitIntervalSec = 300;
          StartLimitBurst = 5;
        };
        Service = {
          Type = "simple";
          WorkingDirectory = "%h";
          Environment = [
            "T3CODE_HOME=${config.home.homeDirectory}/.t3"
            "T3CODE_DISABLE_AUTO_UPDATE=1"
          ];
          ExecStart = "${t3code}/bin/t3 serve --no-browser --tailscale-serve --host 0.0.0.0 --port ${toString t3Port}";
          KillMode = "mixed";
          OOMPolicy = "continue";
          OOMScoreAdjust = -1000;
          ManagedOOMPreference = "omit";
          Restart = "always";
          RestartSec = 5;
          CPUWeight = 1000;
          IOWeight = 1000;
        };
        Install.WantedBy = [ "default.target" ];
      };

      # The desktop uses ~/.t3 with its local server disabled. Retain URL-handler names.
      xdg.desktopEntries = {
        t3code = desktop;
        t3code-url-handler = desktop // {
          noDisplay = true;
        };
        "com.t3tools.T3Code" = desktop // {
          noDisplay = true;
        };
      };
    };
}
