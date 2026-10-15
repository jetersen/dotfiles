{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "aws-codeartifact-nuget-credential-provider";
  version = "1.0.2";

  src = fetchurl {
    url = "https://d12ov9682v6hj.cloudfront.net/codeartifact-nuget-credentialprovider-v1.0.2.zip";
    hash = "sha256-GW6we0+UcBwdgNCLXEd4sYaHReVauyAmMzQCGXPSNPk=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/nuget/plugins/netcore"
    cp -r netcore/AWS.CodeArtifact.NuGetCredentialProvider "$out/lib/nuget/plugins/netcore/"
    runHook postInstall
  '';

  meta = {
    description = "AWS CodeArtifact credential provider for NuGet";
    homepage = "https://docs.aws.amazon.com/codeartifact/latest/ug/nuget-cli.html";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
  };
}
