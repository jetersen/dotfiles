{
  lib,
  rustPlatform,
  fetchFromGitea,
  source ? null,
}:
let
  revision = "1ffb0f7566cfb046e2ef754f453043e16b607cc0";
  shortRevision = builtins.substring 0 7 revision;
in
rustPlatform.buildRustPackage {
  pname = "pc2mqtt";
  version = shortRevision;

  # Keep the revision pinned; source can be overridden for isolated local builds.
  src =
    if source != null then
      source
    else
      fetchFromGitea {
        domain = "forgejo.jetersen.dev";
        owner = "jetersen";
        repo = "pc2mqtt";
        rev = revision;
        hash = "sha256-XblJbW4IquMCPkr+tmv1QPqh/NsjybuCnB39nSQZLx8=";
      };
  cargoHash = "sha256-tSROtXAlLDTK7Yig+rBNwqaa4Wjbwi1dpMNwje5BjRs=";

  postPatch = ''
    # Source archives have no .git directory. Keep build.rs stamping the pinned revision.
    substituteInPlace build.rs \
      --replace-fail "could not determine git SHA; using 'unknown'" "using pinned source revision" \
      --replace-fail '"unknown".to_string()' '"${shortRevision}".to_string()'
    # Build for the Nix platform rather than the upstream workstation's musl target.
    rm .cargo/config.toml
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/pc2mqtt" --version)" = "pc2mqtt ${shortRevision}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Home Assistant MQTT power state and system control for Linux PCs";
    homepage = "https://forgejo.jetersen.dev/jetersen/pc2mqtt";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "pc2mqtt";
  };
}
