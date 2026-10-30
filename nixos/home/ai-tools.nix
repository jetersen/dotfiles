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
    builtins.readFile ../../home/.chezmoitemplates/ai-instructions.md
  );
  mcpPython = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  configureAiMcp = pkgs.writeShellApplication {
    name = "configure-ai-mcp";
    text = ''
      exec ${mcpPython}/bin/python3 ${./configure-ai-mcp.py} ${lib.optionalString workEnabled (lib.escapeShellArg osConfig.sops.secrets.victorialogs-mcp-url.path)}
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
  claudeCode = pkgs.claude-code.override {
    manifest = builtins.fromJSON (builtins.readFile ../packages/claude-code-manifest.json);
  };
in
{
  # Claude and T3 use upstream release pins; Codex uses nixpkgs master.
  home.packages = [
    claudeCode
    dotfilesPackages.codex
    dotfilesPackages.t3code
  ];

  home.activation.configureAiMcp = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureAiMcp}
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
          t3-remote-thread = ../../home/dot_agents/skills/t3-remote-thread;
          t3-completion-notifier = ../../home/dot_agents/skills/t3-completion-notifier;
          full-send = ../../home/dot_agents/skills/full-send;
          full-stop = ../../home/dot_agents/skills/full-stop;
          sol-loop = ../../home/dot_agents/skills/sol-loop;
          file-pr = ../../home/dot_agents/skills/file-pr;
          babysit-pr = ../../home/dot_agents/skills/babysit-pr;
          leaving-pr-comments = ../../home/dot_agents/skills/leaving-pr-comments;
        }
      );
}
