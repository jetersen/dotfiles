{
  pkgs,
  pkgsUnstable,
  inputs,
}:
let
  configurations = inputs.self.nixosConfigurations;
  sharedUiDependency = name: source:
    let
      releaseLock = builtins.fromJSON (builtins.readFile "${source}/flake.lock");
    in
    assert pkgs.lib.assertMsg (
      source.inputs.dank-qml-common.rev == releaseLock.nodes.dank-qml-common.locked.rev
    ) "${name} must use the shared UI revision tested by its release";
    pkgs.runCommand "${name}-ui-dependency" { } ''
      test -f ${source.inputs.dank-qml-common}/DCommon/Common/FontSource.qml
      touch "$out"
    '';
in
{
  dms-ui-dependency = sharedUiDependency "dms" inputs.dms;
  greeter-ui-dependency = sharedUiDependency "greeter" inputs.dank-greeter;
  files-ui-dependency = sharedUiDependency "files" inputs.dux-files;
  quickshell-api = pkgs.runCommand "quickshell-api" { } ''
    mkdir -m 700 "$TMPDIR/runtime"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    export QT_QPA_PLATFORM=offscreen
    quickshell=${pkgs.lib.getExe configurations.rocket.config.programs.dms-shell.quickshell.package}
    # Exercise the executable DMS finds on PATH, including package collisions.
    for profile in ${configurations.rocket.config.system.path} ${configurations.framework.config.system.path}; do
      test "$(readlink -f "$profile/bin/quickshell")" = "$(readlink -f "$quickshell")"
    done
    trap '"$quickshell" kill -p ${./quickshell-api.qml} >/dev/null 2>&1 || true' EXIT
    ${pkgs.coreutils}/bin/timeout 15 \
      "$quickshell" -d -p ${./quickshell-api.qml}
    touch "$out"
  '';
  boot-profile = import ./boot-profile.nix { inherit pkgs configurations; };
  t3-browser-libraries = import ./browser.nix { inherit pkgs configurations; };
  desktop-activation = import ./desktop.nix { inherit pkgs inputs configurations; };
  dns-routing = import ./dns.nix { inherit pkgs pkgsUnstable; };
  tooling-unit = import ./tooling.nix { inherit pkgs; };
  work-tailnet-isolation = import ./work-tailnet.nix { inherit pkgs configurations; };
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
