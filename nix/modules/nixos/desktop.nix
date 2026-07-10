{
  hostSpec,
  lib,
  pkgs,
  ...
}:
{
  programs = {
    niri.enable = true;
    dconf.enable = true;
    dms-shell = {
      enable = true;
      systemd = {
        enable = true;
        restartIfChanged = true;
      };
      enableSystemMonitoring = true;
      enableVPN = true;
      enableDynamicTheming = true;
      enableAudioWavelength = true;
      enableCalendarEvents = true;
      enableClipboardPaste = true;
    };
  };

  services = {
    displayManager = lib.mkMerge [
      {
        dms-greeter = {
          enable = true;
          compositor.name = "niri";
          configHome = "/home/joseph";
        };
      }
      (lib.mkIf (hostSpec.hostName == "rocket") {
        autoLogin = {
          enable = true;
          user = "joseph";
        };
        defaultSession = "niri";
      })
    ];
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
    udisks2.enable = true;
  };

  security = {
    polkit.enable = true;
    rtkit.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  fonts.packages = with pkgs; [
    inter
    jetbrains-mono
    nerd-fonts.jetbrains-mono
  ];

  environment = {
    sessionVariables.NIXOS_OZONE_WL = "1";
    systemPackages = with pkgs; [
      alacritty
      kdePackages.dolphin
      kdePackages.polkit-kde-agent-1
      satty
      udiskie
      wl-clipboard
      xwayland-satellite
    ];
  };

  systemd.user.services.niri.enableDefaultPath = false;
}
