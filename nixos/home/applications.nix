{
  dotfilesPackages,
  lib,
  pkgs,
  pkgsMaster,
  pkgsUnstable,
  ...
}:
let
  # Other source-code types inherit text/plain; list structured data explicitly.
  textMimeTypes = [
    "text/plain"
    "text/markdown"
    "text/csv"
    "text/tab-separated-values"
    "text/x-log"
    "text/x-ini"
    "application/json"
    "application/yaml"
    "application/toml"
    "application/xml"
    "application/x-shellscript"
    "application/x-zerosize"
  ];
in
{
  home.packages = with pkgs; [
    tiny-rdm
    rustdesk-flutter
    jetbrains.rider
    # Match the preserved Discord profile until nixpkgs catches up.
    (pkgsMaster.discord.override {
      source = builtins.fromJSON (builtins.readFile ../packages/discord-source.json);
    })
    dotfilesPackages.dotnet-sdk
    (symlinkJoin {
      name = "${pkgsUnstable.proton-pass-cli.name}-desktop";
      paths = [ pkgsUnstable.proton-pass-cli ];
      nativeBuildInputs = [ makeWrapper ];
      # Persist the local encryption key in the login-unlocked Secret Service.
      postBuild = ''
        wrapProgram "$out/bin/pass-cli" --set-default PROTON_PASS_LINUX_KEYRING dbus
      '';
    })
    dotfilesPackages.pulumi-cli
    dotfilesPackages.pulumi-language-dotnet
    awscli2
    kubectl
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
  ];

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    DOTNET_ROOT = "${dotfilesPackages.dotnet-sdk}/share/dotnet";
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

  xdg.mimeApps = {
    defaultApplications = lib.genAttrs textMimeTypes (_: [ "dev.zed.Zed.desktop" ]);
    associations.added =
      lib.genAttrs (
        textMimeTypes
        ++ [
          "text/html"
          "application/x-x509-ca-cert"
        ]
      ) (_: [ "dev.zed.Zed.desktop" ])
      // lib.genAttrs [ "text/plain" "text/markdown" ] (_: [
        "dev.zed.Zed.desktop"
        "dev.duxlabs.shell.notepad.desktop"
      ]);
  };
}
