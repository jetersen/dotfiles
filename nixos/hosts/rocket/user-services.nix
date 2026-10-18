{ pkgs, ... }:
{
  # Keep the remote server available before desktop login.
  users.users.joseph.linger = true;

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
          ExecStart = "${t3code}/bin/t3 serve --no-browser";
          KillMode = "mixed";
          OOMPolicy = "continue";
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
