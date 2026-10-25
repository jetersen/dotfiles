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
        "home/dot_agents/skills/t3-completion-notifier/scripts"
        "home/dot_agents/skills/t3-remote-thread/scripts"
        "tests/test_ci_graph.py"
        "nixos/ci/build-graph.py"
        "nixos/ci/build-systems.sh"
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
      (pkgs.python3.withPackages (p: [ p.websocket-client ]))
      pkgs.openssl
      pkgs.bash
      pkgs.jq
    ];
  }
  ''
    cp -rL ${sources} source
    chmod -R u+w source
    cd source
    python3 -m unittest discover -s tests -p 'test_*.py' -v
    python3 -B -m unittest discover -s home/dot_agents/skills/t3-completion-notifier/scripts -p 'test_poll.py' -v
    python3 -B -m unittest discover -s home/dot_agents/skills/t3-remote-thread/scripts -p 'test_t3_remote.py' -v
    touch "$out"
  ''
