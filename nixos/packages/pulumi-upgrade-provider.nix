{
  lib,
  buildGoModule,
  go_1_27,
  source,
}:
(buildGoModule.override { go = go_1_27; }) {
  pname = "pulumi-upgrade-provider";
  version = "0-unstable-${source.shortRev}";
  src = source;
  vendorHash = "sha256-/Lhvgg6SwL7lTD/+I5Vk6PRsuXy0AUpKP3WFPKI7EDE=";
  subPackages = [ "." ];
  ldflags = [
    "-s"
    "-w"
  ];
  doCheck = false;
  meta = {
    description = "Upgrade Pulumi Terraform providers";
    homepage = "https://github.com/pulumi/upgrade-provider";
    license = lib.licenses.asl20;
    mainProgram = "upgrade-provider";
  };
}
