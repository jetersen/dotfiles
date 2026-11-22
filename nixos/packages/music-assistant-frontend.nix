{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
  pnpm,
  fetchPnpmDeps,
  pnpmConfigHook,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "music-assistant-frontend";
  # Matches the frontend bundled with server nightly 2.11.0.dev2026112203.
  version = "2.17.378";
  src = fetchurl {
    name = "music-assistant-frontend-${finalAttrs.version}.tar.gz";
    url = "https://codeload.github.com/music-assistant/frontend/tar.gz/refs/tags/${finalAttrs.version}";
    hash = "sha256-pxP4kIkc81U+dhBny8epXZCIWf0wgt6MdMQC5sBBiFc=";
  };
  patches = [
    ../patches/music-assistant/offline-fonts.patch
  ];
  nativeBuildInputs = [
    nodejs
    pnpm
    pnpmConfigHook
  ];
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 4;
    hash = "sha256-Dgml6+0lA09Dw4ztZiE42NUBB+RiXwKeFIdxncna/ZI=";
  };
  env.HUSKY = "0";
  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    pnpm test:run
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    cp -r music_assistant_frontend "$out"
    runHook postInstall
  '';
  meta = {
    description = "Music Assistant frontend with public provider link sharing";
    homepage = "https://github.com/music-assistant/frontend";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
})
