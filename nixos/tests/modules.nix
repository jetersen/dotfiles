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
      home = c.home-manager.users.joseph;
    in
    {
      tailscaleOperator = builtins.elem "--operator=joseph" c.services.tailscale.extraSetFlags;
      ssh = {
        linked = home.home.file.".ssh/config".enable;
        generated = home.home.file.".ssh/config".text;
        activation = home.home.activation.configureSsh;
      };
      fileManager = {
        enabled = c.programs.dux-files.enable && c.programs.dux-files.systemd.enable;
        gvfs = c.services.gvfs.enable;
        folders = home.xdg.mimeApps.defaultApplications."inode/directory";
        dbus = home.xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text;
        executable = builtins.unsafeDiscardStringContext (lib.getExe c.programs.dux-files.package);
        portal = c.xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser";
        archives = home.xdg.mimeApps.defaultApplications."application/zip";
        qtPortal = c.environment.variables.QT_QPA_PLATFORMTHEME;
      };
      aspire = {
        installed = builtins.any (p: (p.pname or "") == "aspire-cli") home.home.packages;
        manualInstallOnPath = builtins.elem "${home.home.homeDirectory}/.aspire/bin" home.home.sessionPath;
        bundleLoader = c.programs.nix-ld.enable;
        bundleIcu = builtins.elem configurations.${host}.pkgs.icu c.programs.nix-ld.libraries;
      };
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
      workEnvironment = {
        schemaFile = baseNameOf c.sops.secrets.varlock-work-schema.sopsFile;
        schemaMode = c.sops.secrets.varlock-work-schema.mode;
        schemaOwner = c.sops.secrets.varlock-work-schema.owner;
        schemaTarget = c.home-manager.users.joseph.home.file.".config/varlock/work/.env.schema".source;
        packages = map lib.getName c.home-manager.users.joseph.home.packages;
      };
    }
  );
  framework = configurations.framework.config;
  dns = framework.systemd.services.dnsdist;
  bridge = framework.systemd.services.homelab-dns-vpn;
  rocket = configurations.rocket.config;
  runner = rocket.systemd.services.forgejo-runner;
  assertions = [
    {
      assertion =
        lib.hasInfix " serve --no-browser --tailscale-serve --host 0.0.0.0 --port 3773" (
          builtins.head rocket.home-manager.users.joseph.systemd.user.services.t3code.Service.ExecStart
        )
        && builtins.elem 3773 rocket.networking.firewall.interfaces.tailscale0.allowedTCPPorts
        && !builtins.elem 3773 rocket.networking.firewall.allowedTCPPorts
        && !builtins.any (
          range: range.from <= 3773 && range.to >= 3773
        ) rocket.networking.firewall.allowedTCPPortRanges;
      message = "Rocket: T3 must manage Tailscale Serve, retain localhost access and admit its direct listener through the Tailscale firewall only";
    }
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
            assertion =
              !c.ssh.linked
              && lib.hasInfix "Include local.config" c.ssh.generated
              && lib.hasInfix "Host framework" c.ssh.generated
              && lib.hasInfix "/bin/install -m 600" c.ssh.activation.data
              && builtins.elem "linkGeneration" c.ssh.activation.after;
            message = "${host}: install the generated SSH config as a private user-owned file for FHS clients";
          }
          {
            assertion =
              c.fileManager.enabled
              && c.fileManager.gvfs
              && c.fileManager.folders == [ "dev.duxlabs.files.desktop" ]
              && lib.hasInfix "Exec=${c.fileManager.executable} run --hidden --dbus-activated" c.fileManager.dbus
              && c.fileManager.portal == "dfiles"
              && c.fileManager.archives == [ "dev.duxlabs.files.desktop" ]
              && c.fileManager.qtPortal == "xdgdesktopportal";
            message = "${host}: Dux Files must handle folders, archives, reveal requests and portal file dialogs";
          }
          {
            assertion =
              c.aspire.installed && !c.aspire.manualInstallOnPath && c.aspire.bundleLoader && c.aspire.bundleIcu;
            message = "${host}: Aspire must use the managed CLI and support extracted Linux bundles";
          }
          {
            assertion =
              c.workEnvironment.schemaFile == "varlock.yaml"
              && c.workEnvironment.schemaMode == "0600"
              && c.workEnvironment.schemaOwner == "joseph"
              &&
                toString c.workEnvironment.schemaTarget == toString (
                  configurations.${host}.config.home-manager.users.joseph.lib.file.mkOutOfStoreSymlink
                    configurations.${host}.config.sops.secrets.varlock-work-schema.path
                )
              && lib.all (name: builtins.elem name c.workEnvironment.packages) [
                "varlock"
                "bitwarden-cli"
                "workenv"
              ];
            message = "${host}: provide the private work schema and Bitwarden-backed Varlock tools";
          }
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
