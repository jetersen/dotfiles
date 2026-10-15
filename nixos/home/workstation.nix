{
  pkgs,
  pulumiCli,
  pulumiDotnet,
  ...
}:
{
  home.packages = with pkgs; [
    slack
    discord
    dotnet-sdk_10
    proton-pass-cli
    pulumiCli
    pulumiDotnet
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
    package = pkgs.zed-editor.fhs;
    extraPackages = with pkgs; [
      nixd
      nixfmt
    ];
    extensions = [
      "csharp"
      "nix"
    ];
    userSettings = {
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
