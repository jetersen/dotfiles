{ pkgs, ... }:
{
  home-manager.users.joseph =
    {
      config,
      lib,
      osConfig,
      dotfilesPackages,
      ...
    }:
    let
      assets = ./agent-observability;
      dataDir = "/media/games/agent-observability/search";
      modelRoot = dotfilesPackages.nomic-embed-text.modelRoot;
      python = pkgs.python3.withPackages (p: [ p.tomlkit ]);
      protected = {
        UMask = "0077";
        CPUWeight = 20;
        IOWeight = 20;
      };
      mounted = {
        ConditionPathIsMountPoint = "/media/games";
      };
    in
    {
      home.packages = [
        dotfilesPackages.agentsview
        pkgs.kopia
      ];
      home.file =
        lib.genAttrs
          (map (name: ".kenn/embeddings/${modelRoot}/${name}") [
            "model.onnx"
            "tokenizer.json"
          ])
          (name: {
            source = "${dotfilesPackages.nomic-embed-text}/${modelRoot}/${builtins.baseNameOf name}";
          });
      home.activation.configureAgentSearch =
        lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ]
          ''
            run ${python}/bin/python3 ${assets}/merge_config.py \
              --target ${dataDir}/config.toml --template ${assets}/config.toml --mountpoint /media/games
          '';
      systemd.user.services = {
        agent-embeddings = {
          Unit = {
            Description = "Local Nomic embeddings for agent session search";
            After = [ "network.target" ];
            X-SwitchMethod = "keep-old";
          };
          Service = protected // {
            Type = "simple";
            ExecStart = "${dotfilesPackages.kennembed}/bin/kennembed -data-dir %h/.kenn/embeddings -listen 127.0.0.1:18121";
            Restart = "on-failure";
            RestartSec = 5;
            NoNewPrivileges = true;
            Nice = 10;
            CPUWeight = 10;
            IOWeight = 10;
            MemoryHigh = "3G";
            MemoryMax = "4G";
          };
          Install.WantedBy = [ "default.target" ];
        };
        agentsview = {
          Unit = mounted // {
            Description = "Private agent session search and archive";
            After = [
              "network-online.target"
              "agent-embeddings.service"
            ];
            Wants = [ "agent-embeddings.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = protected // {
            Type = "simple";
            Environment = [
              "AGENTSVIEW_TELEMETRY_ENABLED=0"
              "GOMEMLIMIT=1500MiB"
              "AGENTSVIEW_DATA_DIR=${dataDir}"
            ];
            ExecStart = "${dotfilesPackages.agentsview}/bin/agentsview serve --host 127.0.0.1 --port 8120 --no-browser --no-update-check --public-url https://rocket.rockhopper-bleak.ts.net --base-path /sessions";
            Restart = "on-failure";
            RestartSec = 10;
            NoNewPrivileges = true;
            MemoryHigh = "2G";
            MemoryMax = "4G";
          };
          Install.WantedBy = [ "default.target" ];
        };
        t3-search = {
          Unit = mounted // {
            Description = "Refresh T3 conversations in private session search";
            After = [ "agentsview.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = protected // {
            Type = "oneshot";
            Environment = [ "AGENTSVIEW_DATA_DIR=${dataDir}" ];
            ExecStart = "${pkgs.python3}/bin/python3 ${assets}/t3_search.py";
            MemoryMax = "2G";
            TimeoutStartSec = "30min";
          };
        };
        agent-backup = {
          Unit = mounted // {
            Description = "Encrypted offsite agent sessions and consistent T3 database backup";
            After = [ "network-online.target" ];
            X-SwitchMethod = "keep-old";
          };
          Service = protected // {
            Type = "oneshot";
            WorkingDirectory = "${config.home.homeDirectory}/git/homelab";
            Environment = [
              "BACKUP_S3_CONFIGURED=true"
              "KOPIA_BIN=${pkgs.kopia}/bin/kopia"
            ];
            ExecStart = "${dotfilesPackages.varlock}/bin/varlock run --filter BACKUP_* -- ${pkgs.python3}/bin/python3 ${assets}/agent_backup.py";
            MemoryHigh = "3G";
            MemoryMax = "4G";
            TimeoutStartSec = "2h";
          };
        };
        agent-session-route = {
          Unit = {
            Description = "Private session search path on shared Tailscale HTTPS listener";
            After = [
              "t3code.service"
              "agentsview.service"
            ];
            PartOf = [ "t3code.service" ];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${osConfig.services.tailscale.package}/bin/tailscale serve --bg --https=443 --set-path=/sessions http://127.0.0.1:8120/sessions";
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
      systemd.user.timers = {
        t3-search = {
          Unit.Description = "Keep T3 conversation search current";
          Timer = {
            OnBootSec = "3min";
            OnUnitInactiveSec = "5min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
        agent-backup = {
          Unit.Description = "Back up agent session history";
          Timer = {
            OnBootSec = "10min";
            OnUnitInactiveSec = "6h";
            RandomizedDelaySec = "5min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
