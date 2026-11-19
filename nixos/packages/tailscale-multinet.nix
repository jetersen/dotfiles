{ runCommand }:
# Private, content-addressed static build. Seed this exact output in the private
# workstation cache before changing the pin; no unpublished source is mirrored.
runCommand "tailscale-multinet-3dc0f9b6f"
  {
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-ZuV3vjcRB8+mxci3jxT4fU4NYkwZxHllPTNM9yZElZE=";
    preferLocalBuild = false;
    allowSubstitutes = true;
    meta.mainProgram = "tailscale";
  }
  ''
    echo 'Private multinet artifact missing: restore the pinned output to the workstation cache.' >&2
    exit 1
  ''
