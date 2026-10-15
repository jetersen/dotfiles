{
  config,
  lib,
  pkgs,
  ...
}:
let
  personalEmail = "me@jetersen.dev";
  workEmail = "jop@moviestarplanet.com";
  signingKey = lib.trim (builtins.readFile ../keys/joseph.pub);
  ghDefaults = (pkgs.formats.yaml { }).generate "gh-defaults.yaml" (
    { version = "1"; } // config.programs.gh.settings
  );
  configureGh = pkgs.writeShellApplication {
    name = "configure-gh";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.yq-go
    ];
    text = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/gh"
      mkdir -p "$config_dir"
      settings="$config_dir/config.yml"
      current="$settings"
      if [[ ! -s "$current" ]]; then current=${ghDefaults}; fi
      temporary=$(mktemp "$config_dir/.config.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "$current" ${ghDefaults} > "$temporary"
      chmod 600 "$temporary"
      mv "$temporary" "$settings"
    '';
  };
in
{
  home.packages = [ pkgs.forgejo-cli ];

  # The private key is provisioned from Proton Pass outside the Nix store.
  home.file.".ssh/id_ed25519.pub".source = ../keys/joseph.pub;
  xdg.configFile."git/gitignore".source = ../../home/dot_config/git/gitignore;
  # gh writes settings after authentication, so its config must remain writable.
  xdg.configFile."gh/config.yml".enable = lib.mkForce false;
  home.activation.configureGh = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureGh}
  '';

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing = {
      format = "ssh";
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    includes =
      lib.concatMap
        (
          organization:
          map
            (prefix: {
              condition = "hasconfig:remote.*.url:${prefix}${organization}/**";
              contents.user.email = workEmail;
            })
            [
              "git@github.com:"
              "https://github.com/"
            ]
        )
        [
          "moviestarplanet"
          "moviestarplanet-archives"
        ];
    settings = {
      user = {
        name = "Joseph Petersen";
        email = personalEmail;
      };
      core = {
        autocrlf = "input";
        editor = "zeditor --wait";
        excludesFile = "~/.config/git/gitignore";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      push = {
        autoSetupRemote = true;
        default = "simple";
        followTags = true;
      };
      fetch.prune = true;
      rebase = {
        autoStash = true;
        autoSquash = true;
      };
      merge = {
        conflictStyle = "diff3";
        ff = "only";
      };
      diff.colorMoved = "default";
      gpg.ssh.allowedSignersFile = toString (
        pkgs.writeText "git-allowed-signers" ''
          ${personalEmail},${workEmail} namespaces="git" ${signingKey}
        ''
      );
      tag.forceSignAnnotated = true;
      url."git@github.com:".insteadOf = "https://github.com/";
      diff.sopsdiffer.textconv = "sops decrypt";
      lfs.concurrenttransfers = 20;
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      light = false;
      navigate = true;
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      editor = "zeditor --wait";
    };
  };
}
