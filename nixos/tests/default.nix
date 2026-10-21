{
  pkgs,
  pkgsUnstable,
  inputs,
}:
let
  configurations = inputs.self.nixosConfigurations;
in
{
  boot-profile = import ./boot-profile.nix { inherit pkgs configurations; };
  t3-browser-libraries = import ./browser.nix { inherit pkgs configurations; };
  desktop-activation = import ./desktop.nix { inherit pkgs inputs configurations; };
  dns-routing = import ./dns.nix { inherit pkgs pkgsUnstable; };
  tooling-unit = import ./tooling.nix { inherit pkgs; };
  module-contracts = import ./modules.nix {
    inherit pkgs pkgsUnstable configurations;
    pc2mqtt = inputs.self.packages.x86_64-linux.pc2mqtt;
  };
  # These exact packages already run their native suites during system builds.
  # Referencing them here also makes a standalone flake check execute the tests,
  # with Nix sharing/substituting the same outputs rather than running them twice.
  native-comin = configurations.framework.config.services.comin.package;
  native-pc2mqtt = inputs.self.packages.x86_64-linux.pc2mqtt;
}
