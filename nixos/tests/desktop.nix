{
  pkgs,
  inputs,
  configurations,
}:
let
  inherit (pkgs) lib;
  hosts =
    map
      (
        name:
        let
          osConfig = configurations.${name}.config;
          config = osConfig.home-manager.users.joseph;
          activation = import ../home/dms-activation.nix {
            inherit
              config
              osConfig
              lib
              ;
            pkgs = configurations.${name}.pkgs;
            dmsSource = inputs.dms;
            dmsCommonSource = inputs.dms.inputs.dank-qml-common;
          };
          niriFiles = lib.filterAttrs (name: _: lib.hasPrefix "niri/" name) config.xdg.configFile;
        in
        assert lib.assertMsg (
          lib.hasInfix (builtins.unsafeDiscardStringContext (lib.getExe activation.configureDms)) config.home.activation.configureDms.data
          && lib.hasInfix (builtins.unsafeDiscardStringContext (lib.getExe activation.configurePlugins)) config.home.activation.configureDmsPlugins.data
        ) "${name}: test the configurators wired into Home Manager activation";
        assert lib.assertMsg (
          builtins.elem "linkGeneration" config.home.activation.configureDms.after
          && builtins.elem "configureDms" config.home.activation.configureDmsPlugins.after
        ) "${name}: preserve DMS settings/plugin activation order";
        {
          inherit name;
          configure = lib.getExe activation.configureDms;
          plugins = lib.getExe activation.configurePlugins;
          pluginSettings = activation.pluginSettings;
          settings = activation.dmsSettings;
          niri = lib.getExe osConfig.programs.niri.package;
          files = lib.mapAttrs (
            fileName: file:
            toString (
              builtins.path {
                path = file.source;
                name = builtins.baseNameOf fileName;
              }
            )
          ) niriFiles;
        }
      )
      [
        "rocket"
        "framework"
      ];
  manifest = pkgs.writeText "desktop-test-manifest.json" (builtins.toJSON hosts);
  frameworkDms = configurations.framework.config.programs.dms-shell.package;
in
pkgs.runCommand "desktop-activation-settings"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.nodejs
    ];
  }
  ''
    # configure-dms's native postCheck covers activation, settings and GTK for each host.
    python3 ${../../tests/test_desktop.py} ${manifest}
    # Source-level state logic only: this does not simulate a Wayland session.
    node ${../../tests/test_dms_screen_idle.mjs} ${frameworkDms}/share/quickshell/dms/Services/IdleService.qml
    touch "$out"
  ''
