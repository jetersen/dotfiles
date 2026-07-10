{
  pkgs,
  ...
}:
let
  g = pkgs.writeShellApplication {
    name = "g";
    runtimeInputs = [ pkgs.git ];
    text = ''
      exec git "$@"
    '';
  };
  ride = pkgs.writeShellApplication {
    name = "ride";
    runtimeInputs = [
      pkgs.fd
      pkgs.jetbrains.rider
    ];
    text = ''
      dir="''${1:-.}"
      file=""

      for ext in slnx sln csproj; do
        file=$(fd --ignore-case --no-ignore --absolute-path --max-depth 3 --max-results 1 --threads 1 --type file --extension "$ext" . "$dir")
        [[ -n "$file" ]] && break
      done

      target="''${file:-.}"
      echo "$target"
      nohup rider "$target" >/dev/null 2>&1 &
    '';
  };
  pulumi-language-dotnet = pkgs.callPackage ../../packages/pulumi-language-dotnet.nix { };
  whisper-model = pkgs.callPackage ../../packages/whisper-cpp-model-large-v3-turbo.nix { };
in
{
  home = {
    username = "joseph";
    homeDirectory = "/home/joseph";
    stateVersion = "26.05";
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      CDPATH = "$HOME/git/code:$HOME/git/work";
      PACKAGEOUTPUTPATH = "$HOME/.nuget/local";
      WHISPER_MODEL = "${whisper-model}/share/whisper.cpp-model-large-v3-turbo/ggml-large-v3-turbo.bin";
    };
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/.npm-global/bin"
      "$HOME/.cargo/bin"
      "$HOME/.krew/bin"
      "$HOME/go/bin"
    ];
    packages =
      (with pkgs; [
        age
        argocd
        awscli2
        bitwarden-cli
        btop
        bun
        chezmoi
        claude-code
        delta
        docker-compose
        eza
        fastfetch
        fd
        fluxcd
        fzf
        gh
        git-lfs
        go
        helm
        jdk21
        jq
        just
        kubectl
        kubectx
        kustomize
        maven
        mise
        neovim
        oh-my-posh
        pulumi
        pulumi-language-dotnet
        ripgrep
        sops
        talhelper
        talosctl
        tmux
        unzip
        whisper-cpp-vulkan
        whisper-model
        yq-go
        zip
      ])
      ++ [
        g
        ride
      ];
  };

  xdg.enable = true;

  programs = {
    home-manager.enable = true;
    bat.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    fish = {
      enable = true;
      shellAliases = {
        d = "docker";
        dc = "docker compose";
        k = "kubectl";
        l = "eza -1 --color=always --group-directories-first --all";
        ll = "eza --binary --group --header --all --long --links --classify --group-directories-first --git";
        vi = "nvim";
        vim = "nvim";
      };
      interactiveShellInit = ''
        set -gx SESSIONDEFAULTUSER $USER
        set -gx DOTNET_ROOT $HOME/.dotnet
      '';
    };
    git = {
      enable = true;
      lfs.enable = true;
      settings = {
        user = {
          name = "Joseph Petersen";
          email = "me@jetersen.dev";
        };
        init.defaultBranch = "main";
        core = {
          editor = "nvim";
          hooksPath = "~/.githooks";
        };
        pull.rebase = true;
        push.autoSetupRemote = true;
        fetch.prune = true;
      };
      includes = [
        {
          condition = "gitdir:~/git/work/";
          contents.user.email = "jop@moviestarplanet.com";
        }
      ];
    };
    mise = {
      enable = true;
      enableFishIntegration = true;
    };
    oh-my-posh = {
      enable = true;
      enableFishIntegration = true;
      settings = builtins.fromJSON (
        builtins.readFile ../../../home/dot_config/oh-my-posh/jetersen.omp.json
      );
    };
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*" = {
        AddKeysToAgent = "yes";
        ServerAliveInterval = 60;
      };
    };
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  services.ssh-agent.enable = true;

  home.file = {
    ".githooks/commit-msg" = {
      source = ../../../home/dot_githooks/executable_commit-msg;
      executable = true;
    };
    ".local/bin/cmd-screenshot" = {
      source = ../../../home/dot_local/bin/executable_cmd-screenshot;
      executable = true;
    };
    ".local/bin/cmd-whisper" = {
      source = ../../../home/dot_local/bin/executable_cmd-whisper;
      executable = true;
    };
    ".local/bin/git-bootstrap" = {
      source = ../../../home/dot_local/bin/executable_git-bootstrap;
      executable = true;
    };
    ".local/bin/git-dirty" = {
      source = ../../../home/dot_local/bin/executable_git-dirty;
      executable = true;
    };
    ".local/bin/git-remote-sidecars" = {
      source = ../../../home/dot_local/bin/executable_git-remote-sidecars;
      executable = true;
    };
    ".local/bin/niri-focus-self" = {
      source = ../../../home/dot_local/bin/executable_niri-focus-self;
      executable = true;
    };
  };
}
