{ lib, pkgs, ... }:
let
  whisper = pkgs.whisper-cpp-vulkan;
  model = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin";
    sha256 = "1qm7zxamlvac564c3270wqqqks5wc7532q3fqi01zbfmkiq22hir";
  };
  dictate = pkgs.writeShellApplication {
    name = "dictate";
    runtimeInputs = [
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      # Serialize rapid repeated key presses without relying on stale PID files.
      exec 9>"$XDG_RUNTIME_DIR/dictation-toggle.lock"
      flock 9
      if systemctl --user is-active --quiet dictation.service; then
        systemctl --user kill --kill-whom=main --signal=SIGINT dictation.service
      else
        systemctl --user start dictation.service
      fi
    '';
  };
in
{
  home-manager.users.joseph = {
    home.packages = [ dictate ];
    dotfiles.niri.extraConfig = ''
      binds {
        Mod+Shift+D repeat=false hotkey-overlay-title="Start / finish dictation" { spawn "${lib.getExe dictate}"; }
      }
    '';
    systemd.user.services.dictation = {
      Unit = {
        Description = "Local GPU microphone dictation";
        After = [ "pipewire.service" ];
      };
      Service = {
        Type = "exec";
        ExecStart = "${pkgs.python3}/bin/python3 ${./dictation.py} ${model}";
        Environment = [
          "PATH=${
            lib.makeBinPath [
              whisper
              pkgs.pipewire
              pkgs.libnotify
              pkgs.wl-clipboard
            ]
          }"
          # Expose only Rocket's discrete Radeon, excluding the integrated GPU.
          "DRI_PRIME=pci-0000_03_00_0!"
        ];
        UMask = "0077";
        RuntimeMaxSec = 600;
      };
    };
  };
}
