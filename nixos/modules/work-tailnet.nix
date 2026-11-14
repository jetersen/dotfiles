{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.workTailnet;
  tailscale = config.services.tailscale.package;
  runtime = [
    tailscale
    pkgs.iproute2
    pkgs.networkmanager
    pkgs.systemd
  ];
  control = pkgs.writeShellApplication {
    name = "work-tailnet";
    runtimeInputs = runtime ++ [ pkgs.python3 ];
    text = ''exec python3 ${./work-tailnet/control.py} "$@"'';
  };
  configure = pkgs.writeShellApplication {
    name = "configure-work-tailnet";
    runtimeInputs = [ tailscale ];
    text = builtins.readFile ./work-tailnet/configure.sh;
  };
  netns = pkgs.writeShellApplication {
    name = "work-tailnet-netns";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.iptables
      pkgs.procps
      pkgs.gnugrep
    ];
    text = builtins.readFile ./work-tailnet/netns.sh;
  };
  socket = "/run/work-tailnet/tailscaled.sock";
  peerDnsPython = pkgs.python3.withPackages (p: [ p.dnspython ]);
  # These rules let the namespace reach coordination/DERP endpoints. Work
  # application traffic is NATed separately inside the namespace, to its node IP.
  firewallRules = [
    "-t nat POSTROUTING -s 192.168.77.2/32 ! -o wt-host -j MASQUERADE"
    # Insertions run in this order, so the specific allowances precede the drops.
    "FORWARD -i wt-host -j DROP"
    "FORWARD -o wt-host -j DROP"
    "FORWARD -i wt-host -s 192.168.77.2/32 -j ACCEPT"
    "FORWARD -o wt-host -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
    "INPUT -i wt-host -m conntrack --ctstate NEW -j DROP"
  ];
  firewallCommand =
    operation: rule:
    let
      parts = lib.splitString " " rule;
      table = if builtins.head parts == "-t" then "-t nat " else "";
      rest = if table == "" then rule else lib.concatStringsSep " " (lib.drop 2 parts);
    in
    "iptables -w ${table}${operation} ${rest}";
in
{
  options.dotfiles.workTailnet = {
    enable = lib.mkEnableOption "an isolated, optional work tailnet alongside homelab";
    defaultMode = lib.mkOption {
      type = lib.types.enum [
        "off"
        "auto"
      ];
      default = "off";
      description = "Initial mode; subsequent choices persist locally.";
    };
    officeSsids = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Active Wi-Fi SSIDs that enable the work tailnet in Auto mode.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ control ];
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    # Only the isolated daemon uses these bootstrap resolvers. Host DNS stays intact.
    environment.etc."netns/work-tailnet/resolv.conf".text = ''
      nameserver 1.1.1.1
      nameserver 9.9.9.9
    '';
    networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (
      rule: "${firewallCommand "-C" rule} 2>/dev/null || ${firewallCommand "-I" rule}"
    ) firewallRules;
    networking.firewall.extraStopCommands = lib.concatMapStringsSep "\n" (
      rule: "${firewallCommand "-D" rule} 2>/dev/null || true"
    ) firewallRules;
    systemd.tmpfiles.rules = [
      "d /run/work-tailnet 0755 root root -"
      "f /run/work-tailnet/dnsmasq.servers 0644 root root -"
      "f /run/work-tailnet/peer-dns.json 0644 root root - {}"
      "f /run/work-tailnet/exported-routes.json 0644 root root - []"
      "d /var/lib/work-tailnet 0700 root root -"
    ];
    systemd.services.work-tailnet-netns = {
      description = "Isolated work tailnet network stack";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "firewall.service"
      ];
      before = [ "tailscaled-work.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe netns} start";
        ExecStop = "${lib.getExe netns} stop";
      };
    };
    systemd.services.tailscaled-work = {
      description = "Work Tailscale (separate from the personal connection)";
      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "work-tailnet-netns.service" ];
      after = [
        "work-tailnet-netns.service"
        "network-online.target"
      ];
      wants = [
        "network-online.target"
        "work-tailnet.service"
      ];
      partOf = [ "work-tailnet-netns.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/work-tailnet";
        BindReadOnlyPaths = [ "/etc/netns/work-tailnet/resolv.conf:/etc/resolv.conf" ];
        StateDirectory = "tailscale-work";
        StateDirectoryMode = "0700";
        ExecStart = "${tailscale}/bin/tailscaled --state=/var/lib/tailscale-work/tailscaled.state --socket=${socket} --tun=tailscale-work --port=41642";
        ExecStartPost = lib.getExe configure;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
    systemd.services.work-tailnet-peer-dns = {
      description = "Work app-connector DNS over HTTP bridge";
      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "work-tailnet-netns.service" ];
      after = [ "work-tailnet-netns.service" ];
      partOf = [ "work-tailnet-netns.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/work-tailnet";
        ExecStart = "${peerDnsPython}/bin/python3 ${./work-tailnet}/peer_dns.py";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
    systemd.services.work-tailnet-dns = {
      description = "Work-only MagicDNS forwarder";
      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "work-tailnet-netns.service" ];
      requires = [ "work-tailnet-peer-dns.service" ];
      after = [
        "work-tailnet-netns.service"
        "work-tailnet-peer-dns.service"
      ];
      partOf = [ "work-tailnet-netns.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/work-tailnet";
        ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --conf-file=/dev/null --no-resolv --no-hosts --cache-size=0 --bind-interfaces --listen-address=192.168.77.2 --server=100.100.100.100 --servers-file=/run/work-tailnet/dnsmasq.servers --user=nobody --group=nogroup --pid-file=";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
    systemd.services.work-tailnet = {
      description = "Work tailnet mode, location, routes and split DNS";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "tailscaled-work.service"
        "work-tailnet-dns.service"
      ];
      after = [
        "tailscaled-work.service"
        "work-tailnet-dns.service"
        "NetworkManager.service"
      ]
      ++ lib.optional config.services.resolved.enable "systemd-resolved.service";
      partOf = [
        "tailscaled-work.service"
        "work-tailnet-netns.service"
      ];
      path = runtime;
      serviceConfig = {
        ExecStart =
          "${lib.getExe control} --serve --uid ${toString config.users.users.joseph.uid} --default-mode ${cfg.defaultMode} "
          + lib.concatMapStringsSep " " (ssid: "--office-ssid ${lib.escapeShellArg ssid}") cfg.officeSsids
          + lib.optionalString config.services.resolved.enable " --resolved";
        ExecStopPost =
          "${lib.getExe control} --cleanup"
          + lib.optionalString config.services.resolved.enable " --resolved";
        Restart = "always";
        RestartSec = 5;
        UMask = "0022";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [
          "/var/lib/work-tailnet"
          "/run/work-tailnet"
        ];
      };
    };
    home-manager.users.joseph.xdg.configFile."DankMaterialShell/plugins/workTailnet".source =
      pkgs.runCommand "dms-work-tailnet" { }
        ''
          mkdir -p "$out"
          cp ${../home/work-tailnet/plugin.json} "$out/plugin.json"
          widget="WorkTailnet-$(basename "$out").qml"
          substitute ${../home/work-tailnet/WorkTailnet.qml} "$out/$widget" \
            --replace-fail '@work-tailnet@' '${lib.getExe control}' \
            --replace-fail '@auto-available@' '${
              lib.boolToString (cfg.defaultMode == "auto" || cfg.officeSsids != [ ])
            }' \
            --replace-fail '@terminal@' '${pkgs.alacritty}/bin/alacritty'
          substituteInPlace "$out/plugin.json" \
            --replace-fail './WorkTailnet.qml' "./$widget"
        '';
  };
}
