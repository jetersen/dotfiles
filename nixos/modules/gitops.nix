{ config, ... }:
{
  sops.secrets.nix-cache-netrc = {
    owner = "joseph";
    mode = "0600";
  };

  nix.settings = {
    substituters = [ "https://nix-cache.jetersen.dev/workstations" ];
    trusted-public-keys = [ "workstations:DVP/4iu54FicWbjvEU44a+Y7izu351Ty7+fbvaiNFas=" ];
    netrc-file = config.sops.secrets.nix-cache-netrc.path;
  };

  services.comin = {
    enable = true;
    desktop.enable = true;
    remotes = [
      {
        name = "forgejo";
        url = "https://forgejo.jetersen.dev/jetersen/dotfiles.git";
        branches.main.name = "deploy/${config.networking.hostName}";
      }
    ];
    exporter.listen_address = "127.0.0.1";
  };

  # CI publishes the deployment branch only after uploading the complete closure.
  # Restrict this service to substitutes; interactive Nix builds remain available.
  systemd.services.comin.environment.NIX_CONFIG = ''
    max-jobs = 0
    fallback = false
  '';
}
