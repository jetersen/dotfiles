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
    pkgs.worktrunk
    dotfilesPackages.microfetch
  ];
  home.activation.removeGitSyncHelpers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/rm -f -- \
      ${config.home.homeDirectory}/.local/bin/git-bootstrap \
      ${config.home.homeDirectory}/.local/bin/git-remote-sidecars \
      ${config.home.homeDirectory}/git/.stignore
  '';
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
    enable = true;
    shellAliases = aliases;
    initExtra = ''
      export CDPATH="$HOME/git"
      source ${./shell/bash.sh}
      eval "$(${lib.getExe pkgs.worktrunk} config shell init bash)"
      if [[ $TERM == alacritty && -t 1 ]]; then
        ${lib.getExe dotfilesPackages.microfetch}
      fi
    '';
  };
  programs.zsh = {
    enable = true;
    shellAliases = aliases;
    initContent = ''
      export CDPATH="$HOME/git"
      source ${./shell/bash.sh}
      eval "$(${lib.getExe pkgs.worktrunk} config shell init zsh)"
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
      ${lib.getExe pkgs.worktrunk} config shell init fish | source
      if test "$TERM" = alacritty; and isatty stdout
        ${lib.getExe dotfilesPackages.microfetch}
      end
    '';
  };
  xdg.configFile."powershell/profile.ps1".text = lib.mkBefore (
    builtins.readFile ./shell/profile.ps1
    + ''
      & '${lib.getExe pkgs.worktrunk}' config shell init powershell | Out-String | Invoke-Expression

      if ($env:TERM -eq 'alacritty' -and -not [Console]::IsOutputRedirected) {
        & '${lib.getExe dotfilesPackages.microfetch}'
      }
    ''
  );
  xdg.configFile."shell/clone.bash".source = ../../home/dot_config/shell/clone.bash;
  xdg.configFile."shell/clone.fish".source = ../../home/dot_config/shell/clone.fish;
  xdg.configFile."shell/clone.ps1".source = ../../home/dot_config/shell/clone.ps1;
  xdg.dataFile = lib.mapAttrs' (
    name: source: lib.nameValuePair "powershell/Modules/${name}" { inherit source; }
  ) powershellModules;
}
