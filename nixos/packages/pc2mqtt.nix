{
  lib,
  craneLib,
  fetchFromGitea,
  cacert,
  protobuf,
  source ? null,
}:
let
  revision = "11fcbf4d9dd1b9a8dbfd5f0746d816c010da1348";
  shortRevision = builtins.substring 0 7 revision;
  # Keep the revision pinned; source can be overridden for isolated local builds.
  upstreamSource =
    if source != null then
      source
    else
      fetchFromGitea {
        domain = "forgejo.jetersen.dev";
        owner = "jetersen";
        repo = "pc2mqtt";
        rev = revision;
        hash = "sha256-rhbRGvlDQJ7bznKilj0BkU5MlX7MKrukAJkltyvo4As=";
      };
  src = lib.cleanSourceWith {
    src = upstreamSource;
    name = "pc2mqtt-source";
    filter = path: type: craneLib.filterCargoSources path type || lib.hasSuffix ".proto" path;
  };
  commonArgs = {
    inherit src;
    pname = "pc2mqtt";
    # Keep dependency artifact identity independent of the pinned source revision.
    version = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"))).package.version;

    nativeBuildInputs = [ protobuf ];
    PROTOC = "${protobuf}/bin/protoc";
    postPatch = ''
      # Build for the Nix platform rather than the upstream workstation's musl target.
      rm -f .cargo/config.toml
    '';
    # Secure transport tests use the same trusted roots as the deployed service.
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  };
  # Crane stubs our Rust sources and build script, retaining dependency manifests
  # and release settings. Rust/protocol edits therefore reuse compiled dependencies.
  cargoArtifacts = craneLib.buildDepsOnly (
    commonArgs
    // {
      # Crane discovers declared Cargo targets itself. Preserve autodiscovered
      # integration targets too, so their dependency feature/profile variants cache.
      extraDummyScript =
        lib.concatMapStringsSep "\n"
          (name: ''
            mkdir -p "$out/tests"
            printf '%s\n' 'fn main() {}' > "$out"/${lib.escapeShellArg "tests/${name}"}
          '')
          (
            builtins.attrNames (
              lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".rs" name) (
                builtins.readDir (src + "/tests")
              )
            )
          );
    }
  );
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;
    version = shortRevision;

    postPatch = commonArgs.postPatch + ''
      # Source archives have no .git directory. Keep build.rs stamping the pinned revision.
      substituteInPlace build.rs \
        --replace-fail "could not determine git SHA; using 'unknown'" "using pinned source revision" \
        --replace-fail '"unknown".to_string()' '"${shortRevision}".to_string()'
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
)
