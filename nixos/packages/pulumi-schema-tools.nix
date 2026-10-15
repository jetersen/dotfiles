{
  lib,
  buildGoModule,
  source,
  version,
}:
buildGoModule {
  pname = "pulumi-schema-tools";
  inherit version;
  src = source;
  vendorHash = "sha256-AzbG5bZYdAChV2xEOcGsgE7hIrt2N/6yeDGVe61KOFc=";
  subPackages = [ "." ];
  ldflags = [
    "-s"
    "-w"
  ];
  doCheck = false;
  meta = {
    description = "Pulumi provider schema tools";
    homepage = "https://github.com/pulumi/schema-tools";
    license = lib.licenses.asl20;
    mainProgram = "schema-tools";
  };
}
