{
  hostSpec,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  desktop = hostSpec.desktop;
  workspaceOn = output: lib.optionalAttrs (output != null) { open-on-output = output; };
  dmsCall =
    args:
    [
      (lib.getExe pkgs.dms-shell)
      "ipc"
      "call"
    ]
    ++ args;
  dmsBind =
    title: args:
    {
      action.spawn = dmsCall args;
    }
    // lib.optionalAttrs (title != null) { hotkey-overlay.title = title; };
  lockedDmsBind =
    args:
    (dmsBind null args)
    // {
      allow-when-locked = true;
    };
in
{
  imports = [ inputs.niri.homeModules.config ];

  home = {
    sessionVariables = {
      BROWSER = "firefox";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      MOZ_ENABLE_WAYLAND = "1";
      QT_QPA_PLATFORM = "wayland";
    };
    packages = with pkgs; [
      firefox
      freerdp
      kdePackages.dolphin
      localsend
      meld
      mpv
      pear-desktop
      yt-dlp
      zed-editor
    ];
  };

  programs.niri = {
    # niri-flake owns configuration and validation; nixpkgs stable owns the package.
    package = pkgs.niri;
    settings = {
      input = {
        keyboard.xkb = {
          layout = "us,dk";
          options = "grp:alt_space_toggle";
        };
        touchpad.tap = true;
        focus-follows-mouse.enable = true;
        warp-mouse-to-focus.enable = true;
        workspace-auto-back-and-forth = true;
      };

      outputs = lib.optionalAttrs (desktop.internalDisplay != null) {
        ${desktop.internalDisplay.name} = {
          mode = {
            inherit (desktop.internalDisplay) width height refresh;
          };
          inherit (desktop.internalDisplay) scale;
        };
      };

      workspaces = {
        browser = workspaceOn desktop.dockOutput;
        chat = workspaceOn desktop.dockOutput;
        music = workspaceOn desktop.musicOutput;
      };

      layout = {
        gaps = 0;
        center-focused-column = "never";
        always-center-single-column = true;
        background-color = "transparent";
        preset-column-widths = [
          { proportion = 0.33333; }
          { proportion = 0.5; }
          { proportion = 0.66667; }
          { proportion = 1.0; }
        ];
        focus-ring.enable = false;
        border.enable = false;
        shadow.enable = false;
      };

      animations.enable = false;
      prefer-no-csd = true;
      screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

      environment = {
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
        QT_QPA_PLATFORM = "wayland";
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        XDG_SESSION_TYPE = "wayland";
        XDG_CURRENT_DESKTOP = "niri";
        QT_QPA_PLATFORMTHEME = "gtk3";
      };

      config-notification.disable-failed = true;
      debug.honor-xdg-activation-with-invalid-serial = [ ];
      hotkey-overlay.skip-at-startup = true;
      overview.workspace-shadow.enable = false;
      gestures.hot-corners.enable = false;
      xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;

      spawn-at-startup = [
        {
          argv = [
            "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
          ];
        }
        { argv = [ (lib.getExe' pkgs.udiskie "udiskie") ]; }
        {
          sh = "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --watch ${lib.getExe' pkgs.wl-clipboard "wl-copy"} --primary";
        }
        { argv = [ (lib.getExe pkgs.firefox) ]; }
      ]
      ++ lib.optionals hostSpec.isWork [
        { sh = "systemctl --user import-environment"; }
        { sh = "dbus-update-activation-environment --systemd"; }
      ];

      binds = {
        "Ctrl+Alt+Delete" = dmsBind "Task Manager" [
          "processlist"
          "focusOrToggle"
        ];
        "Ctrl+XF86AudioLowerVolume" = lockedDmsBind [
          "mpris"
          "decrement"
          "3"
        ];
        "Ctrl+XF86AudioRaiseVolume" = lockedDmsBind [
          "mpris"
          "increment"
          "3"
        ];
        "Mod+Alt+L" = dmsBind "Lock Screen" [
          "lock"
          "lock"
        ];
        "Mod+Comma" = dmsBind "Settings" [
          "settings"
          "focusOrToggle"
        ];
        "Mod+N" = dmsBind "Notification Center" [
          "notifications"
          "toggle"
        ];
        "Mod+Shift+N" = dmsBind "Notepad" [
          "notepad"
          "toggle"
        ];
        "Mod+Shift+W" = dmsBind "Create window rule" [
          "window-rules"
          "toggle"
        ];
        "Mod+Space" = dmsBind "Application Launcher" [
          "spotlight"
          "toggle"
        ];
        "Mod+V" = dmsBind "Clipboard Manager" [
          "clipboard"
          "toggle"
        ];
        "Mod+Y" = dmsBind "Browse Wallpapers" [
          "dankdash"
          "wallpaper"
        ];
        "Super+L" = dmsBind "Lock Screen" [
          "lock"
          "lock"
        ];
        "Super+X" = dmsBind "Power Menu: Toggle" [
          "powermenu"
          "toggle"
        ];
        "XF86AudioLowerVolume" = lockedDmsBind [
          "audio"
          "decrement"
          "3"
        ];
        "XF86AudioMicMute" = lockedDmsBind [
          "audio"
          "micmute"
        ];
        "XF86AudioMute" = lockedDmsBind [
          "audio"
          "mute"
        ];
        "XF86AudioNext" = lockedDmsBind [
          "mpris"
          "next"
        ];
        "XF86AudioPause" = lockedDmsBind [
          "mpris"
          "playPause"
        ];
        "XF86AudioPlay" = lockedDmsBind [
          "mpris"
          "playPause"
        ];
        "XF86AudioPrev" = lockedDmsBind [
          "mpris"
          "previous"
        ];
        "XF86AudioRaiseVolume" = lockedDmsBind [
          "audio"
          "increment"
          "3"
        ];
        "XF86MonBrightnessDown" = lockedDmsBind [
          "brightness"
          "decrement"
          "5"
          ""
        ];
        "XF86MonBrightnessUp" = lockedDmsBind [
          "brightness"
          "increment"
          "5"
          ""
        ];
        "Mod+Return" = {
          hotkey-overlay.title = "Open Terminal: Alacritty";
          action.spawn = [ (lib.getExe pkgs.alacritty) ];
        };
        "Mod+B" = {
          hotkey-overlay.title = "Open Browser: Firefox";
          action.spawn = [ (lib.getExe pkgs.firefox) ];
        };
        "Mod+E" = {
          hotkey-overlay.title = "File Manager: Dolphin";
          action.spawn = [ (lib.getExe pkgs.kdePackages.dolphin) ];
        };
        "Mod+M" = {
          hotkey-overlay.title = "Pear Desktop";
          action.spawn = [ (lib.getExe pkgs.pear-desktop) ];
        };
        "Mod+Print" = {
          hotkey-overlay.title = "Annotate Clipboard Screenshot: Satty";
          action.spawn-sh = "${lib.getExe' pkgs.wl-clipboard "wl-paste"} --type image/png | ${lib.getExe pkgs.satty} -f - --copy-command ${lib.getExe' pkgs.wl-clipboard "wl-copy"} --early-exit";
        };
      };

      window-rules = [
        {
          geometry-corner-radius = {
            top-left = 0.0;
            top-right = 0.0;
            bottom-left = 0.0;
            bottom-right = 0.0;
          };
          clip-to-geometry = true;
        }
        {
          matches = [ { app-id = "firefox$"; } ];
          open-on-workspace = "browser";
        }
        {
          matches = [ { app-id = "Slack"; } ];
          open-on-workspace = "chat";
        }
        {
          matches = [ { app-id = "^com\\.github\\.th_ch\\.youtube_music$"; } ];
          open-on-workspace = "music";
        }
        {
          matches = [
            {
              app-id = "firefox$";
              title = "^Picture-in-Picture$";
            }
            { app-id = "zoom"; }
          ];
          open-floating = true;
        }
        {
          matches = [ { app-id = "explorer.exe"; } ];
          open-floating = true;
          open-focused = false;
          default-column-width.fixed = 1;
          default-window-height.fixed = 1;
          default-floating-position = {
            x = 0;
            y = 0;
            relative-to = "bottom-right";
          };
        }
        {
          matches = [
            { app-id = "org.quickshell$"; }
            { app-id = "com.danklinux.dms$"; }
          ];
          open-floating = true;
        }
      ];

      layer-rules = [
        {
          matches = [ { namespace = "^quickshell$"; } ];
          place-within-backdrop = true;
        }
      ];
    };
  };

  xdg.configFile = {
    "alacritty/alacritty.toml".source = ../../../home/dot_config/alacritty/alacritty.toml;
    "foot/foot.ini".source = ../../../home/dot_config/foot/foot.ini;
    "zed/settings.json".source = ../../../home/dot_config/zed/settings.json;
    "zed/themes/dank-zed-theme.json".source = ../../../home/dot_config/zed/themes/dank-zed-theme.json;
  };

  services.kanshi.enable = hostSpec.isWork;
}
