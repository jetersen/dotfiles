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
      if [[ $(id -u) == 0 ]]; then
        exec timeout --kill-after=1s 3s runuser -u ${lib.escapeShellArg user.name} -- \
          env XDG_RUNTIME_DIR=/run/user/${toString user.uid} ${lib.getExe audioControl} "$@"
      fi
      [[ $(id -u) == ${toString user.uid} ]]
      exec timeout --kill-after=1s 3s env XDG_RUNTIME_DIR=/run/user/${toString user.uid} \
        ${lib.getExe audioControl} "$@"
    '';
  };
in
{
  systemd.services.pc2mqtt.environment.PC2MQTT_AUDIO_COMMAND = lib.getExe audioAdapter;

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
