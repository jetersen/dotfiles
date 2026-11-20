{ runCommand }:
# Private, content-addressed static build. Seed this exact output in the private
# workstation cache before changing the pin; no unpublished source is mirrored.
runCommand "tailscale-multinet-d140890f9"
  {
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-L833siExghoIDGU2C33epTDy7R41Rt7Sm6w0V/s39Ks=";
    preferLocalBuild = false;
    allowSubstitutes = true;
    meta.mainProgram = "tailscale";
  }
  ''
    echo 'Private multinet artifact missing: restore the pinned output to the workstation cache.' >&2
    exit 1
  ''
