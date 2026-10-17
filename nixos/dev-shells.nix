{
  pkgs,
  pkgsUnstable,
  dotfilesPackages,
}:
let
  previewSdk = pkgsUnstable.dotnet-sdk_11;
in
{
  dotnet-preview = pkgs.mkShell {
    packages = [ previewSdk ];
    DOTNET_ROOT = "${previewSdk}/share/dotnet";
    # Override the stable SDK's inherited DOTNET_ROOT when entering this shell.
    shellHook = ''
      export DOTNET_ROOT=${previewSdk}/share/dotnet
    '';
  };
  python = pkgs.mkShellNoCC {
    packages = with pkgs; [
      (python3.withPackages (p: [ p.debugpy ]))
      uv
      ruff
      pyright
    ];
  };
  rust = pkgs.mkShell {
    packages = with pkgs; [
      rustc
      cargo
      rustfmt
      clippy
      cargo-audit
      cargo-bloat
      cargo-machete
      cargo-nextest
      trunk
      pkg-config
    ];
  };
  go = pkgs.mkShell {
    packages = with pkgs; [
      go
      golangci-lint
    ];
  };
  jvm = pkgs.mkShellNoCC {
    packages = [
      pkgs.jdk21
      (pkgs.maven.override { jdk_headless = pkgs.jdk21; })
      (pkgs.gradle.override { java = pkgs.jdk21; })
    ];
    JAVA_HOME = pkgs.jdk21.home;
  };
  pulumi = pkgs.mkShell {
    packages = with pkgs; [
      go_1_27
      git
      gh
      pulumictl
      dotfilesPackages.pulumi-cli
      dotfilesPackages.pulumi-schema-tools
      dotfilesPackages.pulumi-upgrade-provider
    ];
  };
}
