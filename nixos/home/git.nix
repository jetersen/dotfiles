{
  config,
  lib,
  pkgs,
  pkgsUnstable,
  ...
}:
let
  personalEmail = "me@jetersen.dev";
  workEmail = "jop@moviestarplanet.com";
  signingKey = lib.trim (builtins.readFile ../keys/joseph.pub);
in
{
  home.packages = [ pkgs.forgejo-cli ];

  # The private key is provisioned from Proton Pass outside the Nix store.
  home.file.".ssh/id_ed25519.pub".source = ../keys/joseph.pub;
  xdg.configFile."git/aliases".source = ../../home/dot_config/git/aliases;
  xdg.configFile."git/gitignore".source = ../../home/dot_config/git/gitignore;
  # gh writes settings after authentication, so its config must remain writable.
  xdg.configFile."gh/config.yml".enable = lib.mkForce false;
  home.activation.configureGh = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe config.programs.gh.package} config set git_protocol \
      ${lib.escapeShellArg config.programs.gh.settings.git_protocol}
    run ${lib.getExe config.programs.gh.package} config set editor \
      ${lib.escapeShellArg config.programs.gh.settings.editor}
  '';

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing = {
      format = "ssh";
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    includes = [
      { path = "~/.config/git/aliases"; }
    ]
    ++
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
      alias = {
        home = "config user.email ${personalEmail}";
        work = "config user.email ${workEmail}";
      };
      help.autocorrect = 1;
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
    # The matching upstream skill requires the current stacked-PR commands.
    extensions = [ pkgsUnstable.gh-stack ];
    settings = {
      git_protocol = "ssh";
      editor = "zeditor --wait";
    };
  };
}
