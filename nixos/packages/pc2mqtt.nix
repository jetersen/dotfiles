{
  lib,
  craneLib,
  fetchFromGitea,
  cacert,
  pkg-config,
  pipewire,
  source ? null,
}:
let
  revision = "5398f0455727c9cb532abc97ea51cd3c8f899670";
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
        hash = "sha256-HffjKDX6nwBcSUNFHulmACpvDc19SbnhTf5z9ICO8PQ=";
      };
  src = lib.cleanSourceWith {
    src = upstreamSource;
    name = "pc2mqtt-source";
    filter = path: type: craneLib.filterCargoSources path type || lib.hasSuffix ".c" path;
  };
  commonArgs = {
    inherit src;
    pname = "pc2mqtt";
    cargoExtraArgs = "--features pipewire";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ pipewire ];
    # Keep dependency artifact identity independent of the pinned source revision.
    version = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"))).package.version;

    postPatch = ''
      # Build for the Nix platform rather than the upstream workstation's musl target.
      rm -f .cargo/config.toml
    '';
    # Secure transport tests use the same trusted roots as the deployed service.
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  };
  # Crane stubs our Rust sources and build script, retaining dependency manifests
  # and release settings. Rust source edits therefore reuse compiled dependencies.
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
      SERVICE_RESULT=exit-code EXIT_STATUS=1 \
        PC2MQTT_UPDATE_RESULT="$TMPDIR/update-result.json" \
        PC2MQTT_UPDATE_SOCKET="$TMPDIR/no-agent.sock" \
        "$out/bin/pc2mqtt" --report-update-result
      grep -q '"state":"failed"' "$TMPDIR/update-result.json"
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
