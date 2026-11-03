{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.users.users.joseph;
  audioControl = pkgs.writeShellApplication {
    name = "pc2mqtt-wpctl";
    runtimeInputs = [
      pkgs.wireplumber
      pkgs.gawk
    ];
    text = builtins.readFile ../../modules/pc2mqtt-audio.sh;
  };
  audioAdapter = pkgs.writeShellApplication {
    name = "pc2mqtt-audio";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      # Preserve the agent's process group so cancellation reaches every helper.
      if [[ $(id -u) == 0 ]]; then
        exec timeout --foreground --kill-after=0.25s 1.5s setpriv --reuid=${toString user.uid} --regid=${
          toString config.users.groups.${user.group}.gid
        } --init-groups -- \
          env XDG_RUNTIME_DIR=/run/user/${toString user.uid} ${lib.getExe audioControl} "$@"
      fi
      [[ $(id -u) == ${toString user.uid} ]]
      exec timeout --foreground --kill-after=0.25s 1.5s env XDG_RUNTIME_DIR=/run/user/${toString user.uid} \
        ${lib.getExe audioControl} "$@"
    '';
  };
in
{
  systemd.services.pc2mqtt = {
    environment.PC2MQTT_AUDIO_COMMAND = lib.getExe audioAdapter;
    serviceConfig = {
      # Hide homes and runtime directories while exposing only the audio socket.
      ProtectHome = lib.mkForce "tmpfs";
      BindReadOnlyPaths = [ "-/run/user/${toString user.uid}/pipewire-0" ];
    };
  };
  # A socket bind pins its inode; refresh it after login or a PipeWire restart.
  systemd.paths.pc2mqtt-audio-session = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/run/user/${toString user.uid}/pipewire-0";
      Unit = "pc2mqtt-audio-session.service";
    };
  };
  systemd.services.pc2mqtt-audio-session = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl try-restart pc2mqtt.service";
    };
  };

  # Keep the working per-user ACP profiles and WirePlumber rules together.
  home-manager.users.joseph.xdg.configFile = {
    "wireplumber/wireplumber.conf.d/disable.conf".source =
      ../../../home/dot_config/wireplumber/wireplumber.conf.d/disable.conf;
    "alsa-card-profile/profile-sets/jds-element-iv-digital-only.conf".source =
      ../../../home/dot_config/alsa-card-profile/profile-sets/jds-element-iv-digital-only.conf;
    "alsa-card-profile/profile-sets/shure-mv7-input-only.conf".source =
      ../../../home/dot_config/alsa-card-profile/profile-sets/shure-mv7-input-only.conf;
  };

  # Match the existing JDS serial-control rule, without granting every user access.
  # Set the tag before systemd's 73-seat-late.rules applies session ACLs.
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-jds-labs.rules" ''
      SUBSYSTEM=="tty", KERNEL=="ttyACM*", ATTRS{idVendor}=="152a", ATTRS{idProduct}=="88fa", TAG+="uaccess"
    '')
  ];
}
