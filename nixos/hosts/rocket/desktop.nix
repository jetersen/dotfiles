# Import into Rocket's host once its hardware and installation layout are ready.
{ ... }:
{
  services.input-remapper = {
    enable = true;
    # Keep remapping opt-in, matching the current disabled service and empty autoload list.
    serviceWantedBy = [ ];
  };

  home-manager.users.joseph.dotfiles.niri = {
    workspaceOutputs.music = "Lenovo Group Limited LEN P27h-10 0x344D3533";
    extraConfig = ''
      window-rule {
        match app-id="sc2_x64.exe"
        open-on-output "DP-1"
      }
    '';
  };
}
