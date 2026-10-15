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
  xdg.portal = {
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
    config.niri."org.freedesktop.impl.portal.FileChooser" = lib.mkForce "kde";
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
      user = "greeter";
    };
  };

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
    kdePackages.dolphin
    kdePackages.polkit-kde-agent-1
    satty
    udiskie
    wl-clipboard
  ];
}
