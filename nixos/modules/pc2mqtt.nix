{ config, pkgs, ... }:
{
  sops.secrets.pc2mqtt-config = {
    sopsFile = ../secrets/pc2mqtt-${config.networking.hostName}.json;
    format = "binary";
    restartUnits = [ "pc2mqtt.service" ];
  };

  systemd.services.pc2mqtt = {
    description = "Home Assistant MQTT power control";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.systemd
    ];
    environment = {
      PC2MQTT_CONFIG = "%d/config.json";
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    serviceConfig = {
      ExecStart = "${pkgs.callPackage ../packages/pc2mqtt.nix { }}/bin/pc2mqtt";
      LoadCredential = "config.json:${config.sops.secrets.pc2mqtt-config.path}";
      Restart = "always";
      RestartSec = 5;
      RuntimeDirectory = "pc2mqtt";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
