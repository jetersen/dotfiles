{ pkgs, configurations }:
let
  control = pkgs.lib.findFirst (
    p: (p.name or "") == "work-tailnet"
  ) (throw "missing work-tailnet CLI") configurations.rocket.config.environment.systemPackages;
  resolver = pkgs.writeText "work-dns-fixture.py" ''
    import socket
    import struct
    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind(("100.64.80.2", 53))
    while True:
        data, address = server.recvfrom(4096)
        end = 12
        while data[end]:
            end += data[end] + 1
        question = data[12:end + 5]
        header = data[:2] + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0)
        answer = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 0, 4) + socket.inet_aton("100.64.80.2")
        server.sendto(header + question + answer, address)
  '';
in
pkgs.testers.runNixOSTest {
  name = "work-tailnet-isolation";
  # CI's Docker workers may not expose /dev/kvm; QEMU can fall back to TCG.
  requiredFeatures.kvm = false;
  nodes.machine = { lib, ... }: {
    imports = [ ../modules/work-tailnet.nix ];
    # Home Manager consumes this integration on the actual workstations.
    options.home-manager = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
    config = {
      dotfiles.workTailnet.enable = true;
      systemd.tmpfiles.rules = [
        "f /var/lib/work-tailnet/hostname 0600 root root - test-workstation"
      ];
      users.users.joseph = {
        isNormalUser = true;
        uid = 1000;
      };
      networking.networkmanager.enable = true;
      services.tailscale.enable = true;
      environment.systemPackages = [
        pkgs.curl
        pkgs.python3
        pkgs.dnsutils
        control
      ];
      virtualisation.memorySize = 1024;
    };
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("work-tailnet.service")
    machine.wait_for_unit("work-tailnet-dns.service")
    machine.wait_until_succeeds("su joseph -c 'work-tailnet status'")
    # First sign-in must retain the operator even without Internet/SSO access.
    machine.execute("su joseph -c 'timeout 4 work-tailnet login' >/tmp/work-login.log 2>&1")
    machine.fail("grep -i 'access denied' /tmp/work-login.log")
    machine.succeed("tailscale --socket=/run/work-tailnet/tailscaled.sock debug prefs | grep '\"OperatorUser\": \"joseph\"'")
    machine.succeed("tailscale --socket=/run/work-tailnet/tailscaled.sock debug prefs | grep '\"Hostname\": \"test-workstation\"'")
    # The real LocalAPI must accept resume without waiting for coordination.
    machine.succeed("timeout 2 python3 -c \"import runpy; runpy.run_path('${../modules/work-tailnet/control.py}')['resume']()\"")
    machine.succeed("tailscale --socket=/run/work-tailnet/tailscaled.sock debug prefs | grep '\"Hostname\": \"test-workstation\"'")
    machine.succeed("su joseph -c 'work-tailnet off'")
    machine.succeed("test -z \"$(ip -4 route show table 53)\"")
    # A fake remote work peer exercises the actual veth, policy routes and NAT.
    machine.succeed("systemctl stop tailscaled-work.service")
    machine.succeed("ip netns add remote-work")
    machine.succeed("ip -n work-tailnet link add tailscale-work type veth peer name remote netns remote-work")
    machine.succeed("ip -n work-tailnet addr add 100.64.80.1/30 dev tailscale-work")
    machine.succeed("ip -n work-tailnet link set tailscale-work up")
    machine.succeed("ip -n remote-work link set lo up; ip -n remote-work addr add 100.64.80.2/30 dev remote; ip -n remote-work link set remote up")
    # No default route on the remote: replies require the namespace's source NAT.
    machine.succeed("ip netns exec remote-work python3 -m http.server 8080 --bind 100.64.80.2 >/tmp/work-http.log 2>&1 &")
    machine.succeed("ip -4 route add 100.64.80.2/32 via 169.254.77.2 dev wt-host table 53")
    machine.wait_until_succeeds("curl --fail --max-time 2 http://100.64.80.2:8080/")
    machine.succeed("ip netns exec remote-work python3 ${resolver} >/tmp/work-dns.log 2>&1 &")
    machine.succeed("echo server=/corp.test/100.64.80.2 > /run/work-tailnet/dnsmasq.servers")
    machine.succeed("systemctl kill --kill-whom=main --signal=HUP work-tailnet-dns.service")
    machine.wait_until_succeeds("dig +short +time=1 +tries=1 @169.254.77.2 app.corp.test | grep '^100.64.80.2$'")
    machine.succeed("truncate -s 0 /run/work-tailnet/dnsmasq.servers")
    machine.succeed("systemctl kill --kill-whom=main --signal=HUP work-tailnet-dns.service")
    machine.wait_until_fails("dig +short +time=1 +tries=1 @169.254.77.2 app.corp.test | grep '^100.64.80.2$'")
    machine.succeed("ip -4 route add 100.99.0.1/32 dev lo table 52")
    machine.succeed("ip rule show | grep '5270:.*lookup 52'")
    machine.succeed("ip route get 100.99.0.1 | grep 'dev lo'")
    machine.succeed("ip route get 100.64.80.2 | grep 'via 169.254.77.2'")
    machine.succeed("systemctl restart firewall.service")
    machine.succeed("curl --fail --max-time 2 http://100.64.80.2:8080/")
    machine.succeed("ip -n work-tailnet -6 addr add fd7a:115c:a1e0:80::1/64 dev tailscale-work nodad")
    machine.succeed("ip -n remote-work -6 addr add fd7a:115c:a1e0:80::2/64 dev remote nodad")
    machine.succeed("ip -6 route add fd7a:115c:a1e0:80::2/128 via fd42:77::2 dev wt-host table 53")
    machine.succeed("ip netns exec remote-work python3 -m http.server 8081 --bind fd7a:115c:a1e0:80::2 >/tmp/work-http6.log 2>&1 &")
    machine.wait_until_succeeds("curl --fail --max-time 2 'http://[fd7a:115c:a1e0:80::2]:8081/'")
    machine.succeed("work-tailnet --cleanup")
    machine.wait_until_succeeds("test -z \"$(ip -4 route show table 53)\"")
    machine.succeed("test -z \"$(ip -6 route show table 53)\"")
    machine.fail("curl --fail --max-time 2 http://100.64.80.2:8080/")
    machine.succeed("ip -n work-tailnet link del tailscale-work")
    machine.succeed("systemctl start tailscaled-work.service")
    # Off persists through controller restarts; cleanup leaves homelab rules alone.
    machine.succeed("systemctl restart work-tailnet.service")
    machine.wait_until_succeeds("su joseph -c 'work-tailnet status' | grep '\"mode\": \"off\"'")
    machine.succeed("ip route get 100.99.0.1 | grep 'dev lo'")
    machine.fail("su nobody -s /bin/sh -c 'work-tailnet on'")
    machine.succeed("systemctl stop work-tailnet-netns.service")
    machine.fail("ip link show wt-host")
    machine.succeed("ip route get 100.99.0.1 | grep 'dev lo'")
  '';
}
