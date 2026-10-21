{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.niri = {
    enable = true;
    useNautilus = false;
  };
  programs.dms-shell = {
    enable = true;
    enableCalendarEvents = false;
    enableAudioWavelength = false;
  };
  programs.dux-files = {
    enable = true;
    systemd.enable = true;
    portal = {
      enable = true;
      preferred = true;
      desktop = "niri";
    };
  };
  services.gvfs.enable = true;
  xdg.portal = {
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
    config.niri."org.freedesktop.impl.portal.FileChooser" = lib.mkForce [ "dfiles" ];
    config.niri."org.freedesktop.impl.portal.ScreenCast" = "gnome";
  };

  programs.dms-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/joseph";
  };
  services.displayManager.defaultSession = "niri";
  environment.etc."greetd/niri_overrides.kdl".text = ''
    input {
      keyboard {
        xkb {
          layout "dk,us"
          options "grp:alt_space_toggle"
        }
      }
    }
  '';

  security.polkit.enable = true;
  security.pam.services = {
    greetd = {
      # The login password also unlocks the user's login keyring.
      fprintAuth = false;
      enableGnomeKeyring = true;
    };
    # DMS runs fingerprint authentication separately, alongside this password stack.
    dankshell.fprintAuth = false;
    sudo.fprintAuth = config.services.fprintd.enable;
    polkit-1.fprintAuth = config.services.fprintd.enable;
  };
  services.gnome.gnome-keyring.enable = true;
  qt.enable = true;
  environment.variables = {
    QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
    QT_QPA_PLATFORMTHEME_QT6 = "xdgdesktopportal";
    GTK_USE_PORTAL = "1";
  };
  services.udisks2.enable = true;
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  hardware.bluetooth.enable = true;
  hardware.graphics.enable = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];

  environment.systemPackages = with pkgs; [
    alacritty
    xwayland-satellite
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.kio-extras
    kdePackages.gwenview
    kdePackages.ffmpegthumbs
    kdePackages.kdegraphics-thumbnailers
    kdePackages.plasma-integration
    (papirus-icon-theme.override { color = "violet"; })
    satty
    udiskie
    wl-clipboard
  ];
}
