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
      emojiExpansion = {
        enabled = c.services.espanso.enable;
        wayland = c.services.espanso.package.waylandSupport;
        capabilities = c.security.wrappers.espanso.capabilities;
        configDirectory = c.systemd.user.services.espanso.environment.ESPANSO_CONFIG_DIR;
        layoutDependency = builtins.elem "espanso-layout.service" c.systemd.user.services.espanso.requires;
        layoutReadiness = c.systemd.user.services.espanso-layout.serviceConfig.Type;
        matches = home.xdg.configFile."espanso/match/emoji.yml".enable;
      };
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
        appPath = c.systemd.user.services.dfiles.environment.PATH;
        legacyApps = builtins.filter (
          name:
          builtins.elem name [
            "dolphin"
            "ark"
          ]
        ) (map lib.getName c.environment.systemPackages);
        textDefaults = home.xdg.mimeApps.defaultApplications;
        textHandlers = home.xdg.mimeApps.associations.added;
        notepadHidden = home.xdg.desktopEntries."dev.duxlabs.shell.notepad".noDisplay;
      };
      aspire = {
        installed = builtins.any (p: (p.pname or "") == "aspire-cli") home.home.packages;
        manualInstallOnPath = builtins.elem "${home.home.homeDirectory}/.aspire/bin" home.home.sessionPath;
        bundleLoader = c.programs.nix-ld.enable;
        bundleIcu = builtins.elem configurations.${host}.pkgs.icu c.programs.nix-ld.libraries;
      };
      upgrade = {
        enabled = c.system.autoUpgrade.enable;
        nixConfig = c.systemd.services.nixos-upgrade.environment.NIX_CONFIG;
        script = c.systemd.services.nixos-upgrade.script;
        retention = c.systemd.services.nixos-cache-retention.serviceConfig.ExecStart;
        retentionTimer = c.systemd.timers.nixos-cache-retention.timerConfig;
        flake = c.system.autoUpgrade.flake;
        autoReboot = c.system.autoUpgrade.allowReboot;
        upgradeInputs = c.system.autoUpgrade.upgrade;
        persistent = c.system.autoUpgrade.persistent;
        restartIfChanged = c.systemd.services.nixos-upgrade.restartIfChanged;
        stopOnRemoval = c.systemd.services.nixos-upgrade.unitConfig.X-StopOnRemoval;
        post = c.systemd.services.nixos-upgrade.serviceConfig.ExecStopPost;
        resultDirectory = c.systemd.services.nixos-upgrade.serviceConfig.StateDirectory;
        retiredComin = c.systemd.services.comin.serviceConfig;
        cominWanted = c.systemd.services.comin.wantedBy;
        handover = c.systemd.services.comin.unitConfig.OnSuccess;
        retireDesktop = c.systemd.services.retire-comin-desktop.serviceConfig.ExecStart;
        compatMachineId = c.services.comin.machineId;
      };
      gc = {
        automatic = c.nix.gc.automatic;
        dates = c.nix.gc.dates;
        options = c.nix.gc.options;
        preStart = c.systemd.services.nix-gc.preStart;
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
  rocket = configurations.rocket.config;
  runner = rocket.systemd.services.forgejo-runner;
  assertions = [
    {
      assertion =
        rocket.fileSystems."/home/joseph/.cache/go-build".device == "/media/games/cache/go-build"
        && builtins.elem "bind" rocket.fileSystems."/home/joseph/.cache/go-build".options
        && !(builtins.elem "nofail" rocket.fileSystems."/home/joseph/.cache/go-build".options)
        &&
          rocket.fileSystems."/home/joseph/.cache/go-build".depends == [
            "/home"
            "/media/games"
          ]
        && builtins.elem "home-joseph-.cache-go\\x2dbuild.mount" rocket.systemd.services.go-build-cache-directory.requiredBy
        && builtins.elem "home-joseph-.cache-go\\x2dbuild.mount" rocket.systemd.services.go-build-cache-directory.before
        &&
          rocket.systemd.services.go-build-cache-directory.unitConfig.RequiresMountsFor == [
            "/media/games"
            "/nix"
          ]
        && !rocket.systemd.services.go-build-cache-directory.unitConfig.DefaultDependencies;
      message = "Rocket: prepare the Go cache on the mounted SSD before binding its existing path";
    }
    {
      assertion = lib.all (
        host:
        host.gc.automatic
        && host.gc.dates == [ "weekly" ]
        && host.gc.options == ""
        && lib.hasInfix "prune-system-generations.py" host.gc.preStart
      ) (builtins.attrValues hosts);
      message = "Weekly GC must prune only system history before collecting unrooted paths";
    }
    {
      assertion = lib.all (c: !c.programs.openvpn3.enable && !(c.systemd.services ? homelab-dns-vpn)) [
        rocket
        framework
      ];
      message = "Both hosts must retire OpenVPN and its DNS bridge";
    }
    {
      assertion =
        rocket.home-manager.users.joseph.systemd.user.startServices
        && rocket.home-manager.users.joseph.systemd.user.services.t3code.Unit.X-SwitchMethod == "keep-old"
        &&
          rocket.home-manager.users.joseph.systemd.user.services.t3code-idle-update.Service.Type == "oneshot"
        &&
          rocket.home-manager.users.joseph.systemd.user.timers.t3code-idle-update.Timer.OnUnitActiveSec
          == "1min";
      message = "Rocket: stage T3 server updates and retry when agents are idle";
    }
    {
      assertion = lib.all (
        host:
        host.emojiExpansion == {
          enabled = true;
          wayland = true;
          capabilities = "cap_dac_override+p";
          configDirectory = "%t/espanso-niri";
          layoutDependency = true;
          layoutReadiness = "notify";
          matches = true;
        }
      ) (builtins.attrValues hosts);
      message = "Both desktops need Wayland Espanso, its capability wrapper, emoji matches and layout readiness.";
    }
    {
      assertion =
        lib.all
          (
            name:
            let
              service = rocket.systemd.services.${name};
            in
            service.unitConfig.StartLimitIntervalSec == 0
            && service.serviceConfig.RestartSec == 5
            && service.serviceConfig.Restart == "always"
          )
          [
            "prometheus-node-exporter"
            "prometheus-process-exporter"
          ];
      message = "Rocket: LAN-bound exporters must survive delayed network availability";
    }
    {
      assertion =
        lib.hasInfix "timeout 120" runner.serviceConfig.ExecStartPre
        && runner.serviceConfig.TimeoutStartSec == 420;
      message = "Rocket: wait for cache DNS before starting the NFS-backed runner";
    }
    {
      assertion =
        rocket.services.prometheus.exporters.node.enable
        && builtins.elem "drm" rocket.services.prometheus.exporters.node.enabledCollectors
        && rocket.services.prometheus.exporters.process.enable
        && !rocket.services.prometheus.exporters.node.openFirewall
        && !rocket.services.prometheus.exporters.process.openFirewall
        && rocket.services.prometheus.exporters.process.user == "root"
        && builtins.elem "-gather-smaps=true" rocket.services.prometheus.exporters.process.extraFlags
        && !framework.services.prometheus.exporters.process.enable;
      message = "Rocket: collect host GPU and proportional process memory without opening exporters globally or enabling them on Framework";
    }
    {
      assertion =
        rocket.systemd.services."user@1000".serviceConfig.OOMScoreAdjust == -1000
        && !rocket.systemd.services."user@1000".restartIfChanged
        && lib.hasInfix "DefaultOOMScoreAdjust=200" rocket.systemd.user.extraConfig
        && rocket.home-manager.users.joseph.systemd.user.services.t3code.Service.OOMScoreAdjust == -1000
        &&
          rocket.home-manager.users.joseph.systemd.user.services.t3code.Service.ManagedOOMPreference == "omit"
        && rocket.home-manager.users.joseph.systemd.user.services.t3code.Service.OOMPolicy == "continue";
      message = "Rocket: protect the T3 server without making ordinary user services immune or restarting the desktop manager";
    }
    {
      assertion =
        rocket.systemd.slices.system.sliceConfig.MemoryMin == "1G"
        &&
          lib.all
            (
              name:
              let
                service = rocket.systemd.services.${name}.serviceConfig;
              in
              service.OOMScoreAdjust == -1000
              && service.ManagedOOMPreference == "omit"
              && service.MemoryMin == (if name == "tailscale-multi-profile" then "512M" else "128M")
            )
            [
              "sshd"
              "tailscale-multi-profile"
              "NetworkManager"
            ];
      message = "Rocket: reserve memory throughout the remote-access hierarchy and protect its services from OOM selection";
    }
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
      assertion =
        let
          socket = "/run/user/${toString rocket.users.users.joseph.uid}/pipewire-0";
          service = rocket.systemd.services.pc2mqtt;
        in
        !(service.environment ? PC2MQTT_AUDIO_SOCKET)
        && service.serviceConfig.ProtectHome == "tmpfs"
        && service.serviceConfig.BindReadOnlyPaths == [ "-${socket}" ]
        && rocket.systemd.paths.pc2mqtt-audio-session.pathConfig.PathChanged == socket;
      message = "Rocket: request-only audio must retain the narrow PipeWire socket bind and session restart watcher";
    }
    {
      assertion =
        let
          services = framework.systemd.services;
          daemon = services.tailscale-multi-profile;
        in
        lib.hasInfix "--experimental-multi-profile --encrypt-state=false" daemon.serviceConfig.ExecStart
        && daemon.wantedBy == [ "multi-user.target" ]
        && daemon.serviceConfig.StateDirectory == "tailscale-multi-profile-test"
        && daemon.serviceConfig.RuntimeDirectory == "tailscale"
        && daemon.serviceConfig.Restart == "no"
        && builtins.elem (toString configurations.framework.pkgs.getent) (map toString daemon.path)
        && !framework.services.tailscale.enable
        && !framework.services.resolved.enable
        && framework.networking.networkmanager.dns == "none"
        && !framework.networking.networkmanager.settings.connectivity.enabled
        && framework.environment.etc."resolv.conf".source == "/run/NetworkManager/no-stub-resolv.conf"
        && !(services ? tailscale-multinet-portal-mode)
        && !(services ? tailscaled-work)
        && !(services ? dnsdist)
        && !(services ? homelab-portal-dns)
        && !(services ? tailscale-multinet-recover)
        && framework.dotfiles.gitops.prepareSwitch != null
        && rocket.dotfiles.gitops.prepareSwitch != null;
      message = "Framework must retain its authenticated multinet state and simple DNS ownership";
    }
    {
      assertion =
        lib.all
          (
            host:
            let
              c = configurations.${host}.config;
              daemon = c.systemd.services.tailscale-multi-profile;
              stateFile = "/var/lib/${c.dotfiles.tailscaleMultinet.stateDirectory}/tailscaled.state";
            in
            c.dotfiles.tailscaleMultinet.enable
            && !c.dotfiles.workTailnet.enable
            && !c.services.tailscale.enable
            && !c.services.resolved.enable
            && !(c.systemd.services ? tailscaled)
            && !(c.systemd.services ? tailscaled-work)
            && !(c.systemd.services ? homelab-dns-reconcile)
            && builtins.elem "tailscaled.service" daemon.aliases
            && builtins.elem "tailscaled-work.service" daemon.conflicts
          && builtins.elem "tailscaled-work.service" daemon.after
            && lib.hasSuffix "/bin/test -s ${stateFile}" daemon.serviceConfig.ExecStartPre
            && lib.hasInfix "--state=${stateFile}" daemon.serviceConfig.ExecStart
            && lib.hasInfix "--tun=${c.dotfiles.tailscaleMultinet.interfaceName}" daemon.serviceConfig.ExecStart
            && c.systemd.services.NetworkManager-wait-online.enable
            && c.networking.networkmanager.dns == "none"
            && !c.networking.networkmanager.settings.connectivity.enabled
            && c.environment.etc."resolv.conf".source == "/run/NetworkManager/no-stub-resolv.conf"
            && toString c.services.tailscale.package == toString framework.services.tailscale.package
          )
          [
            "rocket"
            "framework"
          ];
      message = "Both hosts must use one pinned daemon, existing provisioned state, compatible unit alias and native DNS handover";
    }
    {
      assertion =
        rocket.dotfiles.tailscaleMultinet.stateDirectory == "tailscale-multi-profile"
        && rocket.dotfiles.tailscaleMultinet.interfaceName == "tailscale0"
        && framework.dotfiles.tailscaleMultinet.stateDirectory == "tailscale-multi-profile-test"
        && framework.dotfiles.tailscaleMultinet.interfaceName == "tailscale-mp";
      message = "Rocket must import into separate state while preserving its T3 firewall interface; Framework must retain its current state and tunnel";
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
              lib.hasInfix "/etc/profiles/per-user/%u/bin" c.fileManager.appPath
              && lib.hasInfix "/run/current-system/sw/bin" c.fileManager.appPath
              && c.fileManager.legacyApps == [ ]
              && !c.fileManager.notepadHidden
              && builtins.all (mime: c.fileManager.textDefaults.${mime} == [ "dev.zed.Zed.desktop" ]) [
                "text/plain"
                "text/markdown"
                "application/json"
                "application/yaml"
                "application/toml"
              ]
              && builtins.elem "dev.zed.Zed.desktop" c.fileManager.textHandlers."application/x-x509-ca-cert"
              && builtins.elem "dev.duxlabs.shell.notepad.desktop" c.fileManager.textHandlers."text/markdown";
            message = "${host}: Dux Files must find installed apps and offer Zed and DMS Notepad without Dolphin or Ark";
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
            assertion =
              c.upgrade.enabled
              && lib.hasInfix "max-jobs = 0" c.upgrade.nixConfig
              && lib.hasInfix "always-allow-substitutes = true" c.upgrade.nixConfig
              && lib.hasInfix "builders =" c.upgrade.nixConfig
              && lib.hasInfix "nixos-cache-policy upgrade" c.upgrade.script
              && lib.hasInfix "--host ${host}" c.upgrade.script
              && lib.hasInfix "nixos-cache-policy refresh" c.upgrade.retention
              && c.upgrade.retentionTimer.OnCalendar == "daily"
              && c.upgrade.retentionTimer.Persistent
              && !c.upgrade.autoReboot
              && !c.upgrade.upgradeInputs
              && c.upgrade.persistent
              && !c.upgrade.restartIfChanged
              && !c.upgrade.stopOnRemoval
              && c.upgrade.flake == "git+https://forgejo.jetersen.dev/jetersen/dotfiles.git?ref=main#${host}"
              && lib.any (lib.hasSuffix "pc2mqtt --report-update-result") (lib.toList c.upgrade.post)
              && c.upgrade.resultDirectory == "pc2mqtt"
              && c.upgrade.retiredComin.Type == "oneshot"
              && c.upgrade.retiredComin.Restart == "no"
              && c.upgrade.cominWanted == [ ]
              && c.upgrade.handover == "nixos-upgrade.service"
              && c.upgrade.compatMachineId == null
              && lib.hasInfix "--user --machine=joseph@.host --no-block stop comin-desktop.service" c.upgrade.retireDesktop;
            message = "${host}: use a persistent, non-rebooting oneshot updater with durable MQTT results and no Comin daemon";
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
