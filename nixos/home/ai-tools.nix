{ aiPkgs, pkgs, ... }:
{
  # These applications release frequently; update their input independently.
  home.packages = [
    aiPkgs.claude-code
    aiPkgs.codex
    (aiPkgs.t3code.override {
      enableClaude = true;
      inherit (pkgs) git gh;
    })
  ];
}
