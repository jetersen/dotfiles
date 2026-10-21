{
  pkgs,
  pkgsUnstable,
  configurations,
  pc2mqtt,
}:
let
  inherit (pkgs) lib;
  hosts = lib.genAttrs [ "framework" "rocket" ] (
    host:
    let
      c = configurations.${host}.config;
    in
    {
      tailscaleOperator = builtins.elem "--operator=joseph" c.services.tailscale.extraSetFlags;
      comin = {
        checks = c.services.comin.package.doCheck;
        main = (builtins.head c.services.comin.remotes).branches.main.name;
        rewrittenMain = c.systemd.services.comin.environment.COMIN_ALLOW_REWRITTEN_MAIN;
      };
      mqtt = {
        credential = c.systemd.services.pc2mqtt.serviceConfig.LoadCredential;
        config = c.systemd.services.pc2mqtt.environment.PC2MQTT_CONFIG;
        privateRuntime = c.systemd.services.pc2mqtt.serviceConfig.RuntimeDirectoryMode;
      };
    }
  );
  framework = configurations.framework.config;
  dns = framework.systemd.services.dnsdist;
  bridge = framework.systemd.services.homelab-dns-vpn;
  runner = configurations.rocket.config.systemd.services.forgejo-runner;
  assertions = [
    {
      assertion =
        builtins.elem "docker.service" runner.wantedBy
        && builtins.elem "docker.service" runner.partOf
        && builtins.elem "docker.service" runner.requires
        && builtins.elem "docker.service" runner.after
        && !runner.restartIfChanged;
      message = "Runner must recover with Docker without restarting for unrelated unit edits";
    }
    {
      assertion = pc2mqtt.doCheck && pc2mqtt.doInstallCheck;
      message = "pc2mqtt native and installed-binary tests must stay enabled";
    }
    {
      assertion = configurations.framework.pkgs.dnsdist.drvPath == pkgsUnstable.dnsdist.drvPath;
      message = "DNS tests and service must use the selected DNS package";
    }
    {
      assertion =
        builtins.elem "homelab-dns-vpn.service" dns.requires
        && builtins.elem "homelab-dns-vpn.service" dns.after;
      message = "DNS must require the ready VPN bridge";
    }
    {
      assertion =
        bridge.serviceConfig.Type == "notify" && bridge.serviceConfig.StateDirectory == "homelab-dns";
      message = "VPN bridge must signal readiness and own persistent route state";
    }
    {
      assertion =
        framework.environment.etc."resolv.conf".text
        == "nameserver 127.0.0.2\nsearch rockhopper-bleak.ts.net\noptions timeout:2 attempts:2\n";
      message = "Framework must resolve through local split DNS";
    }
  ]
  ++
    lib.concatMap
      (
        host:
        let
          c = hosts.${host};
        in
        [
          {
            assertion = c.tailscaleOperator;
            message = "${host}: joseph must be able to manage Tailscale Serve";
          }
          {
            assertion = c.comin.checks;
            message = "${host}: Comin native regression tests must stay enabled";
          }
          {
            assertion = c.comin.main == "main" && c.comin.rewrittenMain == "1";
            message = "${host}: preserve the shared main deployment policy";
          }
          {
            assertion =
              c.mqtt.config == "%d/config.json"
              && c.mqtt.privateRuntime == "0700"
              &&
                c.mqtt.credential
                == "config.json:${configurations.${host}.config.sops.secrets.pc2mqtt-config.path}";
            message = "${host}: MQTT must use a private runtime and systemd credential";
          }
        ]
      )
      [
        "framework"
        "rocket"
      ];
  failed = map (a: a.message) (builtins.filter (a: !a.assertion) assertions);
in
assert lib.assertMsg (failed == [ ]) (lib.concatStringsSep "\n" failed);
pkgs.runCommand "module-contract-checks"
  {
    # Only selected evaluated properties enter the derivation, never the flake path,
    # revision, system closure or secret contents. This does not execute systemd.
    contracts = builtins.toJSON {
      inherit hosts;
      dnsPackage = configurations.framework.pkgs.dnsdist.version;
    };
  }
  ''
    printf '%s\n' "$contracts" > "$out"
  ''
