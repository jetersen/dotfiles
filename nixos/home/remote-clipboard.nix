{ lib, pkgs, osConfig, ... }:
{
  home.packages = [
    # Keep the standard command names available to clipboard-detecting apps.
    # Absolute paths avoid recursion through these wrappers.
    (lib.hiPrio (pkgs.writeShellScriptBin "wl-copy" ''
      export PATH="${lib.makeBinPath [ pkgs.systemd ]}:$PATH"
      exec ${pkgs.python3}/bin/python3 ${./wayland-clipboard.py} ${pkgs.wl-clipboard}/bin/wl-copy "$@"
    ''))
    (lib.hiPrio (pkgs.writeShellScriptBin "wl-paste" ''
      export PATH="${lib.makeBinPath [ pkgs.systemd ]}:$PATH"
      exec ${pkgs.python3}/bin/python3 ${./wayland-clipboard.py} ${pkgs.wl-clipboard}/bin/wl-paste "$@"
    ''))
    (pkgs.writeShellApplication {
      name = "remote-clip";
      runtimeInputs = [
        pkgs.openssh
        osConfig.services.tailscale.package
        pkgs.wl-clipboard
        pkgs.systemd
      ];
      text = ''
        exec ${pkgs.python3}/bin/python3 ${../../home/dot_local/bin/executable_remote-clip} "$@"
      '';
    })
  ];
}
