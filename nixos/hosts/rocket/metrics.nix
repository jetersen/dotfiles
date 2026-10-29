{ lib, ... }:
{
  # Only the homelab scraper may reach these unauthenticated LAN listeners.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -i enp10s0 -s 192.168.1.10 -p tcp -m multiport --dports 9100,9256 -j nixos-fw-accept
  '';
  services.prometheus.exporters = {
    node = {
      enable = true;
      listenAddress = "192.168.1.128";
      enabledCollectors = [
        "drm"
        "systemd"
        "processes"
      ];
    };
    process = {
      enable = true;
      listenAddress = "192.168.1.128";
      # Read smaps/IO across users, without exporting arguments or PID labels.
      user = "root";
      extraFlags = [
        "-threads=false"
        "-children=false"
        "-gather-smaps=true"
      ];
      settings.process_names = [
        {
          name = "t3-server";
          cmdline = [ "(^|/)t3 serve( |$)" ];
        }
        {
          name = "chrome-{{.Matches.Role}}";
          comm = [ "chrome-headless" ];
          cmdline = [ "--type=(?P<Role>renderer|gpu-process|utility|zygote)( |$)" ];
        }
        {
          name = "chrome-browser";
          comm = [ "chrome-headless" ];
        }
        {
          name = "{{.Comm}}";
          cmdline = [ ".+" ];
        }
      ];
    };
  };
  systemd.services.prometheus-process-exporter.serviceConfig.CapabilityBoundingSet = lib.mkForce [
    "CAP_SYS_PTRACE"
  ];
  # LAN addresses can arrive well after login. Retry without slowing desktop boot
  # or exhausting systemd's start limit while the Ethernet link negotiates.
  imports = [
    {
      systemd.services = lib.genAttrs [ "prometheus-node-exporter" "prometheus-process-exporter" ] (_: {
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig.RestartSec = 5;
      });
    }
  ];
}
