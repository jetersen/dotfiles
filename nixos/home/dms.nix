{
  config,
  lib,
  pkgs,
  osConfig,
  dmsSource,
  dmsCommonSource,
  storageMonitorSource,
  ...
}:
let
  emojiShortcodes = pkgs.callPackage ../packages/emoji-shortcodes.nix { };
  expansionControl = pkgs.callPackage ./emoji-expansion-control.nix { };
  emojiPickerSource = pkgs.fetchFromGitHub {
    owner = "hthienloc";
    repo = "dms-plugins";
    rev = "57b8796638d8045105735e50d26af34d131db2db";
    hash = "sha256-5eQ2lyHfkIYwlSsapK291VqGA221LdkWOsGVo7iECfY=";
  };
  emojiPicker = pkgs.runCommand "dms-emoji-picker" { } ''
    cp -r ${emojiPickerSource}/emojiPicker "$out"
    chmod -R u+w "$out"
    ${pkgs.patch}/bin/patch -d "$out" -p1 < ${../packages/dms-emoji-search.patch}
    cp ${emojiShortcodes}/EmojiShortcodes.js "$out/EmojiShortcodes.js"
    cp ${emojiShortcodes}/LICENSE-gemoji "$out/LICENSE-gemoji"
    substituteInPlace "$out/EmojiPicker.qml" \
      --replace-fail '@EXPANSION_CONTROL@' '${lib.getExe expansionControl}'
    ${pkgs.nodejs}/bin/node ${../../tests/test_emoji_search.mjs} "$out"
    # Resolve entrypoints through the immutable store URL, as for storageMonitor.
    ${pkgs.python3}/bin/python3 - "$out" <<'PYTHON'
    import json
    from pathlib import Path
    import sys
    root = Path(sys.argv[1])
    entrypoints = root / root.name
    entrypoints.mkdir()
    manifest = json.loads((root / "plugin.json").read_text())
    for key, component in (("component", "EmojiPicker"), ("settings", "EmojiPickerSettings")):
        wrapper = entrypoints / (component + ".qml")
        wrapper.write_text(f'import QtQuick\nimport "file:{root}" as Packaged\nPackaged.{component} {{}}\n')
        manifest[key] = "./" + str(wrapper.relative_to(root))
    (root / "plugin.json").write_text(json.dumps(manifest) + "\n")
    PYTHON
  '';
  storageMonitor = pkgs.runCommand "dms-storage-monitor" { } ''
    cp -r ${storageMonitorSource} "$out"
    chmod -R u+w "$out"
    # Standard Python validates state; udisksctl handles actions and authorization.
    substituteInPlace "$out/services/StorageService.qml" \
      --replace-fail '"python3"' '"${pkgs.python3}/bin/python3"'
    substituteInPlace "$out/services/storage_backend.py" \
      --replace-fail '"lsblk"' '"${pkgs.util-linux}/bin/lsblk"' \
      --replace-fail '"findmnt"' '"${pkgs.util-linux}/bin/findmnt"' \
      --replace-fail '"busctl"' '"${pkgs.systemd}/bin/busctl"' \
      --replace-fail '"udisksctl"' '"${pkgs.udisks2}/bin/udisksctl"'
    # Qt can cache both entrypoints and sibling types behind HM's stable symlink,
    # even when Dux changes the entrypoint's query string. Version the wrapper
    # filenames and import the entire plugin through its immutable store URL.
    ${pkgs.python3}/bin/python3 - "$out" <<'PYTHON'
    import json
    from pathlib import Path
    import sys
    root = Path(sys.argv[1])
    entrypoints = root / root.name
    entrypoints.mkdir()
    manifest = json.loads((root / "plugin.json").read_text())
    for key, component in (("component", "StorageMonitorWidget"), ("settings", "StorageMonitorSettings")):
        wrapper = entrypoints / (component + ".qml")
        wrapper.write_text(f'import QtQuick\nimport "file:{root}" as Packaged\nPackaged.{component} {{}}\n')
        manifest[key] = "./" + str(wrapper.relative_to(root))
    (root / "plugin.json").write_text(json.dumps(manifest) + "\n")
    PYTHON
    PYTHONDONTWRITEBYTECODE=1 ${pkgs.python3}/bin/python3 -m unittest discover -s "$out/tests" -v
    ${pkgs.nodejs}/bin/node "$out/tests/test_power_off_ui.mjs"
  '';
  kdePaletteTemplate = pkgs.writeText "kdeglobals-template.colors" (
    builtins.readFile "${dmsSource}/quickshell/matugen/templates/kcolorscheme.colors"
    + ''

      [Icons]
      Theme=Papirus-Dark
    ''
  );
  activation = import ./dms-activation.nix {
    inherit
      config
      lib
      pkgs
      osConfig
      dmsSource
      dmsCommonSource
      ;
  };

in
{
  home.activation.configureDms = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe activation.configureDms}
  '';

  home.activation.configureDmsPlugins = lib.hm.dag.entryAfter [ "configureDms" ] ''
    run ${lib.getExe activation.configurePlugins}
  '';

  xdg.configFile = {
    "DankMaterialShell/plugins/emojiPicker".source = emojiPicker;
    "DankMaterialShell/plugins/storageMonitor" = lib.mkIf osConfig.dotfiles.work.enable {
      source = storageMonitor;
    };
    "matugen/config.toml".source = (pkgs.formats.toml { }).generate "matugen-config.toml" {
      config = { };
      templates.kdeglobals = {
        input_path = "${kdePaletteTemplate}";
        output_path = "${config.xdg.configHome}/kdeglobals";
        post_hook = "${pkgs.dbus}/bin/dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0";
      };
    };
    "DankMaterialShell/themes/catppuccin/theme.json".source =
      ../../home/dot_config/DankMaterialShell/themes/catppuccin/theme.json;

  };
}
