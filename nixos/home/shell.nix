{
  config,
  lib,
  pkgs,
  powershellModules,
  dotfilesPackages,
  ...
}:
let
  aliases = {
    d = "docker";
    dc = "docker compose";
    g = "git";
    vi = "nvim";
    vim = "nvim";
    ls = "eza --color=always --group-directories-first";
    l = "eza -1 --color=always --group-directories-first --all";
    ll = "eza --binary --group --header --all --long --links --classify --group-directories-first";
    pip = "pip3";
    python = "python3";
    rimraf = "rm -rf";
    myip = "curl -sSfL -w '\\n' https://api.ipify.org";
    myip6 = "curl -sSfL -w '\\n' https://api6.ipify.org";
    cc = "claude --dangerously-skip-permissions";
    cx = "codex --dangerously-bypass-approvals-and-sandbox";
  };
in
{
  home.packages = [
    pkgs.fd
    dotfilesPackages.microfetch
  ];
  home.sessionVariables = {
    SUDO_EDITOR = "nvim";
    PACKAGEOUTPUTPATH = "${config.home.homeDirectory}/.nuget/local";
  };
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/go/bin"
    "${config.home.homeDirectory}/.krew/bin"
    "${config.home.homeDirectory}/.aspire/bin"
  ];
  programs.bash = {
    shellAliases = aliases;
    initExtra = ''
      export CDPATH="$HOME/git"
      source ${./shell/bash.sh}
      if [[ $TERM == alacritty && -t 1 ]]; then
        ${lib.getExe dotfilesPackages.microfetch}
      fi
    '';
  };
  programs.zsh = {
    shellAliases = aliases;
    initContent = ''
      export CDPATH="$HOME/git"
      source ${./shell/bash.sh}
      if [[ $TERM == alacritty && -t 1 ]]; then
        ${lib.getExe dotfilesPackages.microfetch}
      fi
    '';
  };
  programs.fish = {
    enable = true;
    shellAliases = aliases;
    interactiveShellInit = ''
      set -gx CDPATH $HOME/git
      source ${./shell/fish.fish}
      if test "$TERM" = alacritty; and isatty stdout
        ${lib.getExe dotfilesPackages.microfetch}
      end
    '';
  };
  xdg.configFile."powershell/profile.ps1".text = lib.mkBefore (
    builtins.readFile ./shell/profile.ps1
    + ''

      if ($env:TERM -eq 'alacritty' -and -not [Console]::IsOutputRedirected) {
        & '${lib.getExe dotfilesPackages.microfetch}'
      }
    ''
  );
  xdg.dataFile = lib.mapAttrs' (
    name: source: lib.nameValuePair "powershell/Modules/${name}" { inherit source; }
  ) powershellModules;
}
