{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:

buildGoModule rec {
  pname = "pulumi-language-dotnet";
  version = "3.107.3";

  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-dotnet";
    tag = "v${version}";
    hash = "sha256-HzdQVmIafCn3n2Ia5k89CRz2SYMItOfGlKNPQsizLxg=";
  };

  sourceRoot = "${src.name}/pulumi-language-dotnet";
  vendorHash = "sha256-NwyxvljOoHVErV/KqWV3QYyXWtVZBpxeEDGqrzNEKHY=";

  # Upstream's Go tests exercise the language host against the dotnet CLI.
  # Keep this package focused on building the standalone host executable.
  doCheck = false;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/pulumi/pulumi-dotnet/pkg/v3/version.Version=${version}"
  ];

  meta = {
    description = ".NET language host for Pulumi";
    homepage = "https://github.com/pulumi/pulumi-dotnet";
    license = lib.licenses.asl20;
    mainProgram = "pulumi-language-dotnet";
    platforms = lib.platforms.linux;
  };
}
