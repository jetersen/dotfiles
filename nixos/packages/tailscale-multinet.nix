{ runCommand }:
# Private, content-addressed static build. Seed this exact output in the private
# workstation cache before changing the pin; no unpublished source is mirrored.
runCommand "tailscale-multinet-37f739c58"
  {
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-H+FAL/chrYqmbtOuiBkgOJpH7l9RNW9w38aVY3qZmAw=";
    preferLocalBuild = false;
    allowSubstitutes = true;
    meta.mainProgram = "tailscale";
  }
  ''
    echo 'Private multinet artifact missing: restore the pinned output to the workstation cache.' >&2
    exit 1
  ''
