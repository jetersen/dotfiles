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
        "nixos/assets/skills/t3-completion-notifier/scripts"
        "tests/test_agent_backup.py"
        "tests/test_agent_search.py"
        "tests/test_agent_config.py"
        "nixos/hosts/rocket/agent-observability"
        "tests/test_dictation.py"
        "tests/test_emoji_expansion.py"
        "nixos/home/espanso-layout.py"
        "nixos/home/emoji-expansion-control.sh"
        "nixos/packages/generate-emoji-shortcodes.py"
        "nixos/assets/config/niri/cfg/input.kdl"
        "tests/test_work_tailnet.py"
        "tests/test_dns_resolver.py"
        "nixos/assets/homelab-dns/resolv-conf.sh"
        "tests/test_work_tailnet_peer_dns.py"
        "nixos/modules/work-tailnet/netns.sh"
        "nixos/assets/homelab-dns/dnsdist.conf"
        "nixos/modules/work-tailnet/control.py"
        "nixos/modules/work-tailnet/peer_dns.py"
        "nixos/hosts/rocket/dictation.py"
        "tests/test_ci_graph.py"
        "tests/test_cache_policy.py"
        "tests/test_multinet_state.py"
        "tests/test_multinet_dirs.py"
        "nixos/ops/multinet_state.py"
        "nixos/ops/multinet_dirs.py"
        "nixos/ci/cache-policy.py"
        "nixos/ci/build-graph.py"
        "nixos/ci/build-systems.sh"
        "tests/test_wayland_clipboard.py"
        "tests/test_t3code_idle_update.py"
        "nixos/hosts/rocket/t3code-idle-update.py"
        "nixos/home/wayland-clipboard.py"
      ]
  );
in
pkgs.runCommand "tooling-unit-checks"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (p: [
        p.tomlkit
        p.websocket-client
        p.dnspython
      ]))
      pkgs.openssl
      pkgs.bash
      pkgs.util-linux
      pkgs.sox
      pkgs.jq
      pkgs.gawk
    ];
  }
  ''
    cp -rL ${sources} source
    chmod -R u+w source
    cd source
    python3 -m unittest discover -s tests -p 'test_*.py' -v
    python3 -B -m unittest discover -s nixos/assets/skills/t3-completion-notifier/scripts -p 'test_poll.py' -v
    touch "$out"
  ''
