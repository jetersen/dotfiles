{ pkgs, ... }:
{
  imports = [ ./desktop.nix ];
  home.username = "joseph";
  home.homeDirectory = "/home/joseph";
  home.stateVersion = "26.05";

  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "zen-browser";
  };

  programs.fish = {
    enable = true;
    shellAliases = {
      vi = "nvim";
      vim = "nvim";
      ls = "eza --color=always --group-directories-first";
      l = "eza -1 --color=always --group-directories-first --all";
      ll = "eza --binary --group --header --all --long --links --classify --group-directories-first";
    };
    interactiveShellInit = ''
      fish_add_path ~/.local/bin
      set -gx CDPATH $HOME/git
    '';
  };

  home.packages = with pkgs; [
    eza
    ripgrep
  ];

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Joseph Petersen";
        email = "me@jetersen.dev";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      fetch.prune = true;
      rebase.autoStash = true;
      merge.conflictStyle = "diff3";
    };
  };
}
