{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  nodejs_24,
  pnpm,
  buildFHSEnv,
}:
let
  manifest = (builtins.fromJSON (builtins.readFile ./workstation-manifest.json)).vite-plus;
  cli = stdenv.mkDerivation (finalAttrs: {
    pname = "vite-plus";
    version = lib.removePrefix "v" manifest.version;
    src = fetchurl {
      url = "https://github.com/voidzero-dev/vite-plus/releases/download/v${finalAttrs.version}/vp-x86_64-unknown-linux-gnu.tar.gz";
      sha256 = manifest.sha256;
    };
    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = [ stdenv.cc.cc.lib ];
    sourceRoot = ".";
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 vp "$out/bin/vp"
      # Avoid the upstream first-run installer replacing the Nix-owned executable.
      touch "$out/bin/.vp-setup-complete"
      wrapProgram "$out/bin/vp" \
        --suffix PATH : ${
          lib.makeBinPath [
            nodejs_24
            pnpm
          ]
        } \
        --set VP_NO_UPDATE_CHECK 1
      runHook postInstall
    '';
    meta = {
      description = "Vite+ global CLI";
      homepage = "https://viteplus.dev";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "vp";
    };
  });
in
buildFHSEnv {
  name = "vp";
  targetPkgs = pkgs: [
    pkgs.nodejs_24
    pkgs.pnpm
  ];
  runScript = "${cli}/bin/vp";
  meta = cli.meta;
}
