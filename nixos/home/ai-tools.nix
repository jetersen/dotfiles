{ aiPkgs, pkgs, ... }:
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
}
