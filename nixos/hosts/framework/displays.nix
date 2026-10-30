{
  lib,
  pkgs,
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
  home.activation.configureDockDisplays = lib.hm.dag.entryAfter [ "configureDms" ] ''
    run ${lib.getExe configureDisplays} ${profiles}
  '';
}
