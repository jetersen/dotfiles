{
  config,
  lib,
  pkgs,
  osConfig,
  dmsSource,
  ...
}:
let
  pearSettings = pkgs.writeText "pear-settings.json" (
    builtins.toJSON {
      options = {
        tray = true;
        appVisible = false;
        autoUpdates = false;
        # Open the home page so YouTube Music can restore the latest device queue.
        resumeOnStart = false;
      };
      plugins = {
        video-toggle = {
          enabled = true;
          hideVideo = true;
          forceHide = true;
        };
        discord.enabled = true;
        shortcuts.enabled = true;
        api-server.enabled = false;
      };
    }
  );
  configurePear = pkgs.writeShellApplication {
    name = "configure-pear";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/YouTube Music"
      mkdir -p "$config_dir"
      settings="$config_dir/config.json"
      current=/dev/stdin
      if [[ -s "$settings" ]]; then current="$settings"; fi
      temporary=$(mktemp "$config_dir/.config.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq --slurpfile overlay ${pearSettings} '. * $overlay[0]' \
        "$current" <<< '{}' > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi
    '';
  };
  kdePaletteTemplate = pkgs.writeText "kdeglobals-template.colors" (
    builtins.readFile "${dmsSource}/quickshell/matugen/templates/kcolorscheme.colors"
    + ''

      [Icons]
      Theme=Papirus-Dark
    ''
  );
  factoryBinds = pkgs.runCommand "niri-factory-binds.kdl" { } ''
    substitute ${dmsSource}/core/internal/config/embedded/niri-binds.kdl "$out" \
      --replace-fail '{{TERMINAL_COMMAND}}' alacritty
  '';
  dmsAppIdDefaults =
    pkgs.runCommand "dms-app-id-defaults.json" { nativeBuildInputs = [ pkgs.nodejs ]; }
      ''
        node - '${dmsSource}/quickshell/Common/settings/SettingsSpec.js' > "$out" <<'JS'
        const fs = require("node:fs");
        const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\s*\.(pragma|import)\b.*$/gm, "");
        const defaults = new Function(source + "\nreturn SPEC.appIdSubstitutions.def;")();
        process.stdout.write(JSON.stringify(defaults));
        JS
      '';
  dmsSettings = pkgs.writeText "dms-settings.json" (
    builtins.toJSON (
      (import ./dms-settings.nix {
        enableFprint = osConfig.services.fprintd.enable;
        extraRightWidgets =
          lib.optional osConfig.programs.openvpn3.enable "openvpn3"
          ++ lib.optional osConfig.dotfiles.work.enable "storageMonitor";
      })
      // {
        customThemeFile = "${config.xdg.configHome}/DankMaterialShell/themes/catppuccin/theme.json";
      }
    )
  );
  configureDms = pkgs.writeShellApplication {
    name = "configure-dms";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}"
      mkdir -p "$config_dir/DankMaterialShell" "$config_dir/niri/dms"
      settings="$config_dir/DankMaterialShell/settings.json"
      current=/dev/stdin
      if [[ -s "$settings" ]]; then current="$settings"; fi
      temporary=$(mktemp "$config_dir/DankMaterialShell/.settings.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq --slurpfile overlay ${dmsSettings} --slurpfile appIdDefaults ${dmsAppIdDefaults} \
        -f ${./merge-dms-settings.jq} \
        "$current" <<< '{}' > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi

      if [[ -s "$config_dir/gtk-3.0/dank-colors.css" && -s "$config_dir/gtk-4.0/dank-colors.css" ]]; then
        export XDG_DATA_DIRS="${pkgs.adw-gtk3}/share:''${XDG_DATA_DIRS:-/run/current-system/sw/share}"
        ${pkgs.bash}/bin/bash ${dmsSource}/quickshell/scripts/gtk.sh "$config_dir" apply false
        ${pkgs.bash}/bin/bash ${dmsSource}/quickshell/scripts/gtk.sh "$config_dir" patch false
      fi

      # Seed writable bindings from DMS's own factory template once.
      if [[ ! -s "$config_dir/niri/dms/binds.kdl" ]]; then
        install -m 644 ${factoryBinds} "$config_dir/niri/dms/binds.kdl"
      fi
    '';
  };
in
{
  home.activation.configurePear = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configurePear}
  '';

  home.activation.configureDms = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureDms}
  '';

  gtk = {
    enable = true;
    iconTheme.name = "Papirus-Dark";
    gtk3.theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
  };

  home.packages = [
    (pkgs.callPackage ../packages/music-assistant-desktop.nix { })
    pkgs.pear-desktop
    (pkgs.writeShellApplication {
      name = "focus-music-assistant";
      runtimeInputs = [
        pkgs.niri
        pkgs.jq
        pkgs.systemd
        (pkgs.callPackage ../packages/music-assistant-desktop.nix { })
      ];
      text = ''
        exec ${pkgs.bash}/bin/bash ${../../home/dot_local/bin/executable_focus-music-assistant} "$@"
      '';
    })
  ];

  programs.mpv.enable = true;

  xdg.userDirs.enable = true;
  xdg.userDirs.createDirectories = true;
  home.file."Pictures/Wallpapers".source = import ./wallpapers.nix { inherit pkgs; };
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${pkgs.kdePackages.dolphin}/bin/dolphin --daemon
  '';
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      lib.genAttrs [
        "image/png"
        "image/jpeg"
        "image/webp"
        "image/avif"
        "image/gif"
        "image/bmp"
        "image/tiff"
        "image/svg+xml"
        "image/heic"
        "image/heif"
      ] (_: [ "org.kde.gwenview.desktop" ])
      // lib.genAttrs [
        "video/mp4"
        "video/x-matroska"
        "video/webm"
        "video/quicktime"
        "video/x-msvideo"
        "video/mpeg"
        "video/ogg"
        "video/mp2t"
        "video/x-flv"
      ] (_: [ "mpv.desktop" ])
      // lib.genAttrs [
        "application/zip"
        "application/x-7z-compressed"
        "application/vnd.rar"
        "application/x-rar"
        "application/x-rar-compressed"
        "application/x-tar"
        "application/gzip"
        "application/x-gzip"
        "application/x-bzip2"
        "application/x-xz"
        "application/zstd"
        "application/x-zstd"
        "application/x-compressed-tar"
        "application/x-bzip-compressed-tar"
        "application/x-xz-compressed-tar"
        "application/x-zstd-compressed-tar"
      ] (_: [ "org.kde.ark.desktop" ])
      // {
        "application/pdf" = [ "zen-beta.desktop" ];
        "text/html" = [ "zen-beta.desktop" ];
        "x-scheme-handler/http" = [ "zen-beta.desktop" ];
        "x-scheme-handler/https" = [ "zen-beta.desktop" ];
        "inode/directory" = [ "org.kde.dolphin.desktop" ];
      };
  };

  xdg.configFile = {
    "matugen/config.toml".source = (pkgs.formats.toml { }).generate "matugen-config.toml" {
      config = { };
      templates.kdeglobals = {
        input_path = "${kdePaletteTemplate}";
        output_path = "${config.xdg.configHome}/kdeglobals";
        post_hook = "${pkgs.dbus}/bin/dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0";
      };
    };
    "alacritty/alacritty.toml".source = ../../home/dot_config/alacritty/alacritty.toml;
    "DankMaterialShell/themes/catppuccin/theme.json".source =
      ../../home/dot_config/DankMaterialShell/themes/catppuccin/theme.json;

  };
}
