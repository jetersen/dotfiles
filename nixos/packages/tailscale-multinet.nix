{ runCommand }:
# Private, content-addressed static build. Seed this exact output in the private
# workstation cache before changing the pin; no unpublished source is mirrored.
runCommand "tailscale-multinet-2c01a6a89"
  {
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-uBmNTjlYk2xbxBlBJjORqYpc1OfJHgeJ98SDUI+4p5Y=";
    preferLocalBuild = false;
    allowSubstitutes = true;
    meta.mainProgram = "tailscale";
  }
  ''
    echo 'Private multinet artifact missing: restore the pinned output to the workstation cache.' >&2
    exit 1
  ''
