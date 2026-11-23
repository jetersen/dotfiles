{ runCommand }:
# Private, content-addressed static build. Seed this exact output in the private
# workstation cache before changing the pin; no unpublished source is mirrored.
runCommand "tailscale-multinet-438f66072"
  {
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-dUWV0VcwwVW4zqv9LEZMTfME18U+DWVtyX8fzTZ54wI=";
    preferLocalBuild = false;
    allowSubstitutes = true;
    meta.mainProgram = "tailscale";
  }
  ''
    echo 'Private multinet artifact missing: restore the pinned output to the workstation cache.' >&2
    exit 1
  ''
