{
  lib,
  rustPlatform,
  makeWrapper,
  git,
  git-lfs,
  openssh,
  btrfs-progs,
  systemd,
  gh,
  coreutils,
  source,
}:
rustPlatform.buildRustPackage {
  pname = "local-git-sync";
  version = (builtins.fromTOML (builtins.readFile "${source}/Cargo.toml")).package.version;
  src = source;
  cargoLock.lockFile = "${source}/Cargo.lock";

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    git
    git-lfs
    coreutils
    systemd
  ];
  # Nix's sandbox disables xattr inspection and has no live /run/systemd.
  # Preservation and native Btrfs coverage runs separately on the devices.
  cargoTestFlags = [ "--lib" ];
  checkFlags =
    lib.concatMap
      (suite: [
        "--skip"
        suite
      ])
      [
        "device::capture::tests::"
        "device::materialize::tests::"
        "policy::local::tests::"
        "device::config::tests::streams_large_hook_and_preserves_local_git_metadata_modes"
        "device::service::tests::systemd_parser_accepts_literal_special_characters_in_executable"
      ];
  preCheck = ''
    export HOME="$TMPDIR/test-home"
    mkdir -p "$HOME"
  '';
  postInstall = ''
    install -Dm644 packaging/local-git-sync.slice \
      "$out/share/local-git-sync/local-git-sync.slice"
  '';
  postFixup = ''
    wrapProgram "$out/bin/local-git-sync" \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          git-lfs
          openssh
          btrfs-progs
          systemd
          gh
          coreutils
        ]
      }
  '';

  meta = {
    description = "Git-aware device continuation with verified immutable checkpoints";
    homepage = "https://github.com/jetersen/local-git-sync";
    mainProgram = "local-git-sync";
    platforms = lib.platforms.linux;
  };
}
