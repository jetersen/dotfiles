{
  dotfilesPackages,
  lib,
  pkgs,
  pkgsMaster,
  pkgsUnstable,
  ...
}:
{
  home.packages = with pkgs; [
    tiny-rdm
    rustdesk-flutter
    jetbrains.rider
    discord
    dotnet-sdk_10
    pkgsUnstable.proton-pass-cli
    dotfilesPackages.pulumi-cli
    dotfilesPackages.pulumi-language-dotnet
    awscli2
    kubectl
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
  ];

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    DOTNET_ROOT = "${pkgs.dotnet-sdk_10}/share/dotnet";
  };

  programs.zed-editor = {
    enable = true;
    # Keep the editor compatible with the preserved workstation profile.
    package = pkgsMaster.zed-editor.fhs;
    extraPackages = with pkgs; [
      nixd
      nixfmt
    ];
    extensions = [
      "csharp"
      "nix"
      "powershell"
    ];
    userSettings =
      lib.recursiveUpdate
        (builtins.fromJSON (builtins.readFile ../../home/dot_config/zed/private_settings.json))
        {
          auto_update = false;
          ui_font_size = 16;
          buffer_font_size = 15;
          buffer_font_family = "JetBrainsMono Nerd Font";
          theme = {
            mode = "system";
            dark = "DankShell Dark";
            light = "DankShell Light";
          };
          languages.CSharp.language_servers = [ "roslyn" ];
          languages.Nix.language_servers = [ "nixd" ];
          languages.Nix.formatter.external.command = "nixfmt";
        };
  };

  xdg.mimeApps.defaultApplications = {
    "text/plain" = [ "dev.zed.Zed.desktop" ];
    "application/json" = [ "dev.zed.Zed.desktop" ];
  };
}
