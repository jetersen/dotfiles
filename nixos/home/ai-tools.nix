{
  agentSkillSources,
  config,
  dotfilesPackages,
  lib,
  osConfig,
  pkgs,
  pkgsUnstable,
  ...
}:
let
  workEnabled = osConfig.dotfiles.work.enable;
  personalInstructions = builtins.replaceStrings [ "@AI_WORK_INSTRUCTIONS@" ] [ "" ] (
    builtins.readFile ../assets/ai-instructions.md
  );
  mcpPython = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  mcpPolicy = {
    remove = [
      "rea"
      "codegraph"
    ]
    ++ lib.optional (!workEnabled) "victorialogs";
    servers = lib.optionalAttrs workEnabled {
      victorialogs = {
        type = "http";
        urlFile = osConfig.sops.secrets.victorialogs-mcp-url.path;
      };
    };
  };
  configureAiMcp = pkgs.writeShellApplication {
    name = "configure-ai-mcp";
    text = ''
      exec ${mcpPython}/bin/python3 ${./configure-ai-mcp.py} ${lib.escapeShellArg (builtins.toJSON mcpPolicy)}
    '';
  };
  t3FontFamily = "Inter Variable, Noto Color Emoji";
  t3Typography = {
    fontFamilyComposer = t3FontFamily;
    fontFamilySans = t3FontFamily;
  };
  configureT3Typography = pkgs.writeShellApplication {
    name = "configure-t3-typography";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      umask 077
      directory="$HOME/.t3/userdata"
      mkdir -p "$directory"
      settings="$directory/client-settings.json"
      input=/dev/stdin
      if [[ -s "$settings" ]]; then input="$settings"; fi
      temporary=$(mktemp "$directory/.typography.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq --argjson typography ${lib.escapeShellArg (builtins.toJSON t3Typography)} \
        '. + $typography' "$input" <<< '{}' > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi
    '';
  };
  instructions =
    if workEnabled then
      {
        source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates.ai-instructions.path;
      }
    else
      {
        text = personalInstructions;
      };
in
{
  home.packages = [
    dotfilesPackages.claude-code
    dotfilesPackages.codex
    dotfilesPackages.t3code
  ];

  home.activation.configureAiMcp = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureAiMcp}
  '';
  home.activation.configureT3Typography = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureT3Typography}
  '';

  # Both clients discover the same immutable, pinned skill directories.
  home.file =
    lib.foldlAttrs
      (
        files: name: source:
        files
        // {
          ".agents/skills/${name}".source = source;
          ".claude/skills/${name}".source = source;
        }
      )
      {
        ".codex/AGENTS.md" = instructions;
        ".claude/CLAUDE.md" = instructions;
        ".config/ai/AGENTS.md" = instructions;
      }
      (
        agentSkillSources
        // {
          gh-stack = pkgsUnstable.gh-stack.src + "/skills/gh-stack";
          t3-remote-thread = ../assets/skills/t3-remote-thread;
          t3-completion-notifier = ../assets/skills/t3-completion-notifier;
          work-tailnet = ../assets/skills/work-tailnet;
          full-send = ../assets/skills/full-send;
          full-stop = ../assets/skills/full-stop;
          sol-loop = ../assets/skills/sol-loop;
          file-pr = ../assets/skills/file-pr;
          babysit-pr = ../assets/skills/babysit-pr;
          leaving-pr-comments = ../assets/skills/leaving-pr-comments;
        }
      );
}
