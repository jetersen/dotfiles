{ inputs, pkgs }:
let
  # Keep the release input and its Rust dependencies pinned. Only backport the
  # profile PR, its booted-system protection prerequisite and a VM fixture fix.
  source = pkgs.applyPatches {
    name = "lanzaboote-1.2.0-system-profiles-source";
    src = inputs.lanzaboote;
    patches = [
      ../patches/lanzaboote/protected-system.patch
      ../patches/lanzaboote/system-profiles.patch
      ../patches/lanzaboote/nixos-test-image.patch
    ];
  };
in
import source {
  inherit pkgs;
  system = pkgs.stdenv.hostPlatform.system;
  rust-overlay = inputs.lanzaboote.inputs.rust-overlay;
  crane = inputs.crane.mkLib pkgs;
}
