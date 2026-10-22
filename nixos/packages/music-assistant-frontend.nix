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
  # Matches homelab's Music Assistant 2.10.6 (API schema 65).
  version = "2.17.297";
  src = fetchurl {
    name = "music-assistant-frontend-${finalAttrs.version}.tar.gz";
    url = "https://codeload.github.com/music-assistant/frontend/tar.gz/e779b9d359e47cd210c2801f16a0ce6263571903";
    hash = "sha256-C83T+UkVHqJD25YvzvTY0Iso4GFTRPHOZSqQWuF9Pws=";
  };
  patches = [
    ../patches/music-assistant/provider-links.patch
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
    hash = "sha256-Es4R4/gyWuA848cgLnbN0HiONWmovrQe2mEtRCzU4O4=";
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
