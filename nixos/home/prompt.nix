{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.prompt;
  identity = pkgs.writeShellScript "prompt-identity" ''
    if [[ -v SSH_CONNECTION || -v SSH_CLIENT || -v SSH_TTY ]] ||
       (( EUID == 0 )) ||
       [[ -n "''${LOGNAME:-}" && "''${USER:-}" != "$LOGNAME" ]]; then
      printf 1
    fi
  '';
  shellIdentity = ''
    unset DOTFILES_PROMPT_IDENTITY
    if [[ -n "$(${identity})" ]]; then
      export DOTFILES_PROMPT_IDENTITY=1
    fi
  '';
  batteryModule = low: {
    when = cfg.showBattery;
    shell = [
      "${pkgs.bash}/bin/bash"
      "--noprofile"
      "--norc"
    ];
    command = ''
      low=${if low then "1" else "0"}
      ${builtins.readFile ./prompt-battery.sh}
    '';
    format = "([Bat $output]($style) )";
    style = if low then "bold #f38ba8" else "#f9e2af";
  };
  settings = {
    add_newline = false;
    scan_timeout = 30;
    command_timeout = 500;
    format = lib.concatStrings [
      "$username$hostname$directory$git_branch$git_commit$git_state$git_status"
      "$dotnet$nodejs$python$nix_shell"
      "\${custom.battery}\${custom.battery_low}"
      "$cmd_duration$status$line_break$character"
    ];
    username = {
      show_always = false;
      detect_env_vars = [ "DOTFILES_PROMPT_IDENTITY" ];
      format = "[$user]($style)@";
      style_user = "bold #cba6f7";
      style_root = "bold #f38ba8";
    };
    hostname = {
      ssh_only = false;
      detect_env_vars = [ "DOTFILES_PROMPT_IDENTITY" ];
      format = "[$hostname](bold #cba6f7) ";
    };
    directory = {
      format = "[$path]($style)[$read_only]($read_only_style) ";
      style = "bold #89b4fa";
      truncation_length = 3;
      truncate_to_repo = false;
      read_only = " ro";
    };
    git_branch = {
      format = "[$branch]($style) ";
      style = "#a6e3a1";
      truncation_length = 25;
    };
    git_commit.only_detached = true;
    git_status = {
      format = "([$all_status$ahead_behind]($style) )";
      style = "#f9e2af";
      conflicted = "conflict:\${count} ";
      untracked = "?\${count} ";
      stashed = "*\${count} ";
      modified = "!\${count} ";
      staged = "+\${count} ";
      renamed = "r\${count} ";
      deleted = "-\${count} ";
      ahead = "↑\${count}";
      behind = "↓\${count}";
      diverged = "↑\${ahead_count}↓\${behind_count}";
    };
    dotnet.format = "[.NET $version](#89b4fa) ";
    nodejs.format = "[Node $version](#a6e3a1) ";
    python.format = "[Py $version( $virtualenv)](#f9e2af) ";
    nix_shell.format = "[Nix $state](#89dceb) ";
    custom = {
      battery = batteryModule false;
      battery_low = batteryModule true;
    };
    cmd_duration = {
      min_time = 2000;
      format = "[took $duration](#a6adc8) ";
    };
    status = {
      disabled = false;
      format = "[exit $status](bold #f38ba8) ";
    };
    character = {
      success_symbol = "[❯](bold #cba6f7)";
      error_symbol = "[❯](bold #f38ba8)";
    };
  };
  shellPrompt = pkgs.replaceVars ./prompt.fish {
    inherit identity;
  };
in
{
  options.dotfiles.prompt.showBattery = lib.mkEnableOption "unplugged battery status in the prompt";

  config = {
    programs.starship = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      enableTransience = false;
      inherit settings;
    };
    programs.bash = {
      enable = true;
      initExtra = lib.mkBefore shellIdentity;
    };
    programs.zsh = {
      enable = true;
      initContent = lib.mkBefore shellIdentity;
    };
    programs.fish.interactiveShellInit = lib.mkBefore ''
      source ${shellPrompt}
    '';
    # Home Manager has no PowerShell module. Use its all-hosts user profile.
    xdg.configFile."powershell/profile.ps1".text = ''
      Remove-Item Env:DOTFILES_PROMPT_IDENTITY -ErrorAction SilentlyContinue
      if (& '${identity}') {
        $env:DOTFILES_PROMPT_IDENTITY = '1'
      }
      $env:STARSHIP_CONFIG = '${config.programs.starship.configPath}'
      if ($env:TERM -ne 'dumb') {
        & '${lib.getExe config.programs.starship.package}' init powershell | Out-String | Invoke-Expression
      }
    '';
  };
}
