{ lib, pkgs, ... }:
let
  t3Port = 3773;
  userMemoryLow = "2G";
  t3MemoryLow = "1536M";
in
{
  # Preserve localhost clients while admitting remote T3 traffic only over Tailscale.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ t3Port ];

  # Keep the remote server available before desktop login.
  users.users.joseph.linger = true;

  # Reclaim protection is bounded by every ancestor of the T3 service.
  systemd.slices = {
    user = {
      overrideStrategy = "asDropin";
      sliceConfig.MemoryLow = userMemoryLow;
    };
    "user-1000" = {
      overrideStrategy = "asDropin";
      sliceConfig.MemoryLow = userMemoryLow;
    };
  };
  systemd.user.slices.app.sliceConfig.MemoryLow = t3MemoryLow;

  # A user manager can only lower a child's OOM score to the floor granted by
  # root. Keep ordinary user services killable; only T3 opts into immunity.
  systemd.services."user@1000" = {
    overrideStrategy = "asDropin";
    restartIfChanged = false;
    serviceConfig = {
      MemoryLow = userMemoryLow;
      OOMScoreAdjust = -1000;
    };
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
      serviceUnit = {
        Description = "T3 Code server";
        # Home Manager leaves the current invocation alone while agents work.
        X-SwitchMethod = "keep-old";
        After = [ "network.target" ];
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "%h";
        Environment = [
          "T3CODE_HOME=${config.home.homeDirectory}/.t3"
          "T3CODE_DISABLE_AUTO_UPDATE=1"
        ];
        ExecStart = "${t3code}/bin/t3 serve --no-browser --tailscale-serve --host 0.0.0.0 --port ${toString t3Port}";
        KillMode = "mixed";
        OOMPolicy = "continue";
        MemoryLow = t3MemoryLow;
        OOMScoreAdjust = -1000;
        ManagedOOMPreference = "omit";
        Restart = "always";
        RestartSec = 5;
        CPUWeight = 1000;
        IOWeight = 1000;
      };
      # systemd exposes the loaded configuration even while an older invocation
      # is running. Give each invocation its own copy of the unit revision.
      serviceRevision = builtins.hashString "sha256" (
        builtins.toJSON { inherit serviceUnit serviceConfig; }
      );
      applyIdleUpdate = pkgs.writeShellApplication {
        name = "t3code-apply-idle-update";
        runtimeInputs = [
          pkgs.systemd
          pkgs.gnugrep
        ];
        text = ''
          unit=t3code.service
          state=$(systemctl --user show --all \
            --property=MainPID,SubState,Job,NeedDaemonReload,Environment,ExecStart "$unit")
          grep -qx 'SubState=running' <<< "$state" || exit 0
          grep -qx 'Job=' <<< "$state" || exit 0
          grep -qx 'NeedDaemonReload=no' <<< "$state" || exit 0
          expected_start="ExecStart={ path=${t3code}/bin/t3 ; argv[]=${serviceConfig.ExecStart} ; ignore_errors=no ; "
          grep -qF "$expected_start" <<< "$state" || exit 0
          revision=T3CODE_NIX_UNIT_REVISION=${serviceRevision}
          environment=$(grep '^Environment=' <<< "$state")
          [[ " ''${environment#Environment=} " == *" $revision "* ]] || exit 0
          pid=''${state#*MainPID=}
          pid=''${pid%%$'\n'*}
          [[ $pid =~ ^[1-9][0-9]*$ && -r /proc/$pid/environ ]] || exit 0
          if grep -zqxF "$revision" "/proc/$pid/environ"; then
            exit 0
          elif [[ $? != 1 ]]; then
            exit 1
          fi

          if ${lib.getExe dotfilesPackages.t3code-idle-update}; then
            systemctl --user try-restart "$unit"
          else
            status=$?
            if [[ $status != 1 ]]; then
              exit "$status"
            fi
          fi
        '';
      };
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
        Unit = serviceUnit;
        Service = serviceConfig // {
          Environment = serviceConfig.Environment ++ [ "T3CODE_NIX_UNIT_REVISION=${serviceRevision}" ];
        };
        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.t3code-idle-update = {
        Unit.Description = "Apply staged T3 Code updates when agents are idle";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe applyIdleUpdate;
          Environment = [ "T3_IDLE_UPDATE_DATABASE=%h/.t3/userdata/statev2.sqlite" ];
        };
      };
      systemd.user.timers.t3code-idle-update = {
        Unit.Description = "Check for idle T3 Code server updates";
        Timer = {
          OnBootSec = "1min";
          OnUnitActiveSec = "5min";
        };
        Install.WantedBy = [ "timers.target" ];
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
