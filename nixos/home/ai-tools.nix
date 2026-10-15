{
  agentSkillSources,
  aiPkgs,
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  claudeCode = pkgs.claude-code.override {
    manifest = builtins.fromJSON (builtins.readFile ../packages/claude-code-manifest.json);
  };
in
{
  # Claude follows upstream directly; Codex and T3 use the faster Nixpkgs branch.
  home.packages = [
    claudeCode
    aiPkgs.codex
    (aiPkgs.t3code.override {
      enableClaude = true;
      claude-code = claudeCode;
      inherit (pkgs) git gh;
    })
  ];

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
        ".codex/AGENTS.md".source =
          config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates.ai-instructions.path;
        ".claude/CLAUDE.md".source =
          config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates.ai-instructions.path;
        ".config/ai/AGENTS.md".source =
          config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates.ai-instructions.path;
      }
      (
        agentSkillSources
        // {
          gh-stack = aiPkgs.gh-stack.src + "/skills/gh-stack";
        }
      );
}
