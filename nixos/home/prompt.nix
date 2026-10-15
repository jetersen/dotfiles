{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.prompt;
  configHome = config.xdg.configHome;
  settings = {
    add_newline = false;
    scan_timeout = 30;
    command_timeout = 500;
    format = lib.concatStrings [
      "$username$hostname$directory$git_branch$git_commit$git_state$git_status"
      "$dotnet$nodejs$python$nix_shell"
      "\${env_var.DOTFILES_PROMPT_BATTERY}"
      "\${env_var.DOTFILES_PROMPT_BATTERY_LOW}"
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
    env_var = {
      DOTFILES_PROMPT_BATTERY.format = "[Bat $env_value](#f9e2af) ";
      DOTFILES_PROMPT_BATTERY_LOW.format = "[Bat $env_value](bold #f38ba8) ";
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
  cloudSettings = settings // {
    format = lib.replaceStrings [ "$cmd_duration" ] [ "$aws$kubernetes$cmd_duration" ] settings.format;
    aws = {
      format = "[AWS ($profile@)$region](bold #f9e2af) ";
      force_display = true;
    };
    kubernetes = {
      disabled = false;
      format = "[K8s $context(/$namespace)]($style) ";
      style = "#89dceb";
      contexts = [
        {
          context_pattern = "eu|us";
          context_alias = "PROD-$0";
          style = "bold #f38ba8";
        }
      ];
    };
  };
  shellContext = pkgs.replaceVars ./shell-context.fish {
    baseConfig = "${configHome}/starship.toml";
    cloudConfig = "${configHome}/starship-cloud.toml";
    homelabConfig = "${configHome}/kube/homelab-context.yaml";
    showBattery = if cfg.showBattery then "1" else "0";
    id = "${pkgs.coreutils}/bin/id";
  };
in
{
  options.dotfiles.prompt.showBattery = lib.mkEnableOption "unplugged battery status in the prompt";

  config = {
    programs.starship = {
      enable = true;
      enableTransience = false;
      inherit settings;
    };
    programs.fish.interactiveShellInit = lib.mkBefore ''
      source ${shellContext}
    '';
    xdg.configFile = {
      "starship-cloud.toml".source = (pkgs.formats.toml { }).generate "starship-cloud.toml" cloudSettings;
      "kube/homelab-context.yaml".text = ''
        apiVersion: v1
        kind: Config
        current-context: homelab
      '';
    };
  };
}
