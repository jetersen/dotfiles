{
  lib,
  rustPlatform,
  pkg-config,
  sqlite,
}:

rustPlatform.buildRustPackage {
  pname = "t3code-idle-update";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./t3code-idle-update;
    fileset = lib.fileset.unions [
      ./t3code-idle-update/Cargo.toml
      ./t3code-idle-update/Cargo.lock
      ./t3code-idle-update/src
    ];
  };
  cargoLock.lockFile = ./t3code-idle-update/Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ sqlite ];

  meta = {
    description = "Check whether Rocket's T3 Code server has active runs";
    mainProgram = "t3code-idle-update";
    platforms = lib.platforms.linux;
  };
}
