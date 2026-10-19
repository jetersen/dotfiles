{ pkgs }:
let
  # Keep fixture layout without making unrelated repository edits invalidate tests.
  sources = pkgs.linkFarm "tooling-test-sources" (
    map
      (path: {
        name = path;
        path = ../../. + "/${path}";
      })
      [
        "tests/test_package_updates.py"
        "tests/test_wayland_clipboard.py"
        "nixos/home/wayland-clipboard.py"
        "nixos/packages/update-claude-code.sh"
        "nixos/packages/update-t3code.sh"
        "nixos/packages/claude-code-manifest.json"
        "nixos/packages/workstation-manifest.json"
      ]
  );
in
pkgs.runCommand "tooling-unit-checks"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.bash
      pkgs.jq
    ];
  }
  ''
    cp -rL ${sources} source
    chmod -R u+w source
    cd source
    python3 -m unittest discover -s tests -p 'test_*.py' -v
    touch "$out"
  ''
