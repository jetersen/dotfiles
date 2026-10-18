{
  lib,
  rustPlatform,
  fetchFromGitea,
  cacert,
  source ? null,
}:
let
  revision = "85261053df4b12081e3e0fe447ff7497e7010af2";
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
        hash = "sha256-UHakZPKOAQP3gW8WtI9U7GJ6PBH8CYuvvwjtHbz3FDo=";
      };
  cargoHash = "sha256-XYBhWumGO+heL4jfEjQFDlJI4zZgZzoenTOHDYH6Gck=";

  postPatch = ''
    # Source archives have no .git directory. Keep build.rs stamping the pinned revision.
    substituteInPlace build.rs \
      --replace-fail "could not determine git SHA; using 'unknown'" "using pinned source revision" \
      --replace-fail '"unknown".to_string()' '"${shortRevision}".to_string()'
    # Build for the Nix platform rather than the upstream workstation's musl target.
    rm .cargo/config.toml
  '';

  # Secure transport tests use the same trusted roots as the deployed service.
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

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
