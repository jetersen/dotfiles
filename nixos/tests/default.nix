{
  pkgs,
  pkgsUnstable,
  inputs,
}:
let
  configurations = inputs.self.nixosConfigurations;
in
{
  files-ui-dependency =
    let
      files = inputs.dux-files;
      releaseLock = builtins.fromJSON (builtins.readFile "${files}/flake.lock");
    in
    assert pkgs.lib.assertMsg (
      files.inputs.dank-qml-common.rev == releaseLock.nodes.dank-qml-common.locked.rev
    ) "Files must use the shared UI revision tested by its release";
    pkgs.runCommand "files-ui-dependency" { } ''
      test -f ${files.inputs.dank-qml-common}/DCommon/Common/FontSource.qml
      touch "$out"
    '';
  boot-profile = import ./boot-profile.nix { inherit pkgs configurations; };
  t3-browser-libraries = import ./browser.nix { inherit pkgs configurations; };
  desktop-activation = import ./desktop.nix { inherit pkgs inputs configurations; };
  dns-routing = import ./dns.nix { inherit pkgs pkgsUnstable; };
  tooling-unit = import ./tooling.nix { inherit pkgs; };
  keyring-unlock = import ./keyring.nix { inherit pkgs; };
  module-contracts = import ./modules.nix {
    inherit pkgs pkgsUnstable configurations;
    pc2mqtt = inputs.self.packages.x86_64-linux.pc2mqtt;
  };
  # These exact packages already run their native suites during system builds.
  # Referencing them here also makes a standalone flake check execute the tests,
  # with Nix sharing/substituting the same outputs rather than running them twice.
  native-lanzaboote = configurations.framework.config.boot.lanzaboote.package;
  native-pc2mqtt = inputs.self.packages.x86_64-linux.pc2mqtt;
  native-music-assistant-frontend = inputs.self.packages.x86_64-linux.music-assistant-frontend;
}
