{
  lib,
  pkgs,
  osConfig,
  dmsSource,
  ...
}:
let
  panel = "China Star Optoelectronics Technology Co., Ltd MND508ZB1-1 Unknown";
  laptopOutput = {
    mode = "2880x1920@120.000";
    position = {
      x = 0;
      y = 0;
    };
    scale = 1.5;
    transform = "Normal";
    vrr = false;
    disabled = false;
    niri = { };
  };
  externalOutput = x: {
    mode = "2560x1440@99.946";
    position = {
      inherit x;
      y = 0;
    };
    scale = 1;
    transform = "Normal";
    vrr = false;
    disabled = false;
    niri = { };
  };
  profiles = pkgs.writeText "framework-display-profiles.json" (
    builtins.toJSON [
      {
        id = "framework-work-dock";
        name = "Work dock";
        outputs = {
          ${panel} = laptopOutput // {
            disabled = true;
          };
          "Dell Inc. DELL P2725D 24CRZ64" = externalOutput 0;
          "Dell Inc. DELL P2725D 3S5S864" = externalOutput 2560;
        };
      }
      {
        id = "framework-laptop";
        name = "Laptop";
        outputs.${panel} = laptopOutput;
      }
    ]
  );
  panelPolicy = pkgs.runCommand "framework-panel-policy" { } ''
    cp -r ${./panel-policy} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/FrameworkPanel.qml" \
      --replace-fail '@NIRI@' '${lib.getExe osConfig.programs.niri.package}'
    ${pkgs.nodejs}/bin/node ${../../../tests/test_framework_panel.mjs} "$out/FrameworkPanel.qml"
  '';
  configureDisplays = pkgs.writeShellApplication {
    name = "configure-framework-displays";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.jq
    ];
    derivationArgs.postCheck = ''
      ${pkgs.nodejs}/bin/node ${../../../tests/test_dms_displays.mjs} \
        ${dmsSource}/quickshell/Modules/Settings/DisplayConfig/DisplayConfigState.qml \
        ${profiles} "$target" ${dmsSource}/quickshell/Common/OutputModel.js
    '';
    text = builtins.readFile ./configure-displays.sh;
  };
in
{
  xdg.configFile."DankMaterialShell/plugins/frameworkPanel".source = panelPolicy;
  home.activation.configureDockDisplays = lib.hm.dag.entryAfter [ "configureDms" ] ''
    run ${lib.getExe configureDisplays} ${profiles}
  '';
}
