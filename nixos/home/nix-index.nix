{ nixIndexPackages, ... }:
{
  programs.nix-index = {
    enable = true;
    # Command discovery only needs executables, not the full file index.
    package = nixIndexPackages.nix-index-with-small-db;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    # Both wrappers use their pinned store database directly.
    symlinkToCacheHome = false;
  };
  programs.nix-index-database.comma.enable = true;
}
