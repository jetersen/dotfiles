{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.prompt;
  remoteVariables = [
    "SSH_CONNECTION"
    "SSH_CLIENT"
    "SSH_TTY"
    "SUDO_USER"
  ];
  settings = {
    add_newline = false;
    scan_timeout = 30;
    command_timeout = 500;
    format = lib.concatStrings [
      "($username$hostname )$directory$git_branch$git_commit$git_state$git_status"
      "$dotnet$nodejs$python$nix_shell"
      "$battery"
      "$cmd_duration$status$line_break$character"
    ];
    username = {
      show_always = false;
      detect_env_vars = remoteVariables;
      format = "[$user]($style)";
      style_user = "bold #cba6f7";
      style_root = "bold #f38ba8";
    };
    hostname = {
      ssh_only = false;
      detect_env_vars = remoteVariables;
      format = "[@$hostname](bold #cba6f7)";
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
    battery = {
      disabled = !cfg.showBattery;
      # The state symbol contains the percentage, so empty symbols hide the
      # whole segment while charging, full, or reporting an unknown state.
      format = "[$symbol]($style)";
      discharging_symbol = "Bat $percentage ";
      empty_symbol = "Bat $percentage ";
      charging_symbol = "";
      full_symbol = "";
      unknown_symbol = "";
      display = [
        {
          threshold = 20;
          style = "bold #f38ba8";
        }
        {
          threshold = 100;
          style = "#f9e2af";
        }
      ];
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
    programs.bash.enable = true;
    programs.zsh.enable = true;
    # Home Manager has no PowerShell module. Use its all-hosts user profile.
    xdg.configFile."powershell/profile.ps1".text = ''
      $env:STARSHIP_CONFIG = '${config.programs.starship.configPath}'
      if ($env:TERM -ne 'dumb') {
        & '${lib.getExe config.programs.starship.package}' init powershell | Out-String | Invoke-Expression
      }
    '';
  };
}
