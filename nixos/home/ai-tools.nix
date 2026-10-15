{
  agentSkillSources,
  config,
  lib,
  osConfig,
  pkgs,
  pkgsUnstable,
  ...
}:
let
  codegraph = pkgsUnstable.codegraph;
  mcpPython = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  configureAiMcp = pkgs.writeShellApplication {
    name = "configure-ai-mcp";
    text = ''
      exec ${mcpPython}/bin/python3 ${./configure-ai-mcp.py} ${lib.getExe codegraph} ${osConfig.sops.secrets.victorialogs-mcp-url.path}
    '';
  };
  claudeCode = pkgs.claude-code.override {
    manifest = builtins.fromJSON (builtins.readFile ../packages/claude-code-manifest.json);
  };
in
{
  # Claude follows upstream directly; Codex and T3 use the faster Nixpkgs branch.
  home.packages = [
    claudeCode
    pkgsUnstable.codex
    codegraph
    (pkgsUnstable.t3code.override {
      enableClaude = true;
      claude-code = claudeCode;
      inherit (pkgs) git gh;
    })
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
          gh-stack = pkgsUnstable.gh-stack.src + "/skills/gh-stack";
        }
      );
}
