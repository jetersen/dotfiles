{
  stdenvNoCC,
  fetchurl,
  nodejs_24,
  pnpm,
  fetchPnpmDeps,
  pnpmConfigHook,
  releaseClient,
}:
let
  # Rebase the source patch and refresh the dependency hash with release updates.
  version = "0.1.1";
  src = fetchurl {
    name = "t3code-${version}.tar.gz";
    url = "https://codeload.github.com/pingdotgg/t3code/tar.gz/fe27e8e3dc12dcbb108e9a28fd9b8cb65f34ae92";
    hash = "sha256-F4osH/y7/CYb5JCOf8PZpNjxMMIjHfm87FeklRjgzwo=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "t3code-web";
  inherit version src;
  patches = [
    ../patches/t3code/shared-browser-runtime.patch
    ../patches/t3code/offline-notices.patch
  ];
  nativeBuildInputs = [
    nodejs_24
    pnpm
    pnpmConfigHook
  ];
  pnpmWorkspaces = [ "@t3tools/web..." ];
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    fetcherVersion = 4;
    hash = "sha256-QyhQ85h/dkD2s7vkKiGTeiXhJzlCHNDSwsUI18d+nHE=";
  };
  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    APP_VERSION = version;
    T3CODE_WEB_SOURCEMAP = "0";
    T3CODE_BUNDLED_LICENSES = "${releaseClient}/third-party-licenses.json";
  };
  preBuild = ''
    cp .env.example .env
  '';
  buildPhase = ''
    runHook preBuild
    pnpm --filter @t3tools/web exec vp build
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    pnpm --filter @t3tools/web exec vp test run --project unit src/browser/previewRuntime.test.ts
    runHook postCheck
  '';
  installPhase = ''
    cp -r apps/web/dist "$out"
  '';
})
