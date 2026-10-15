{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.optimise.automatic = true;

  time.timeZone = "Europe/Copenhagen";
  i18n.defaultLocale = "en_DK.UTF-8";
  i18n.extraLocaleSettings = {
    LC_NUMERIC = "en_IE.UTF-8";
    LC_TIME = "en_IE.UTF-8";
    LC_MONETARY = "en_IE.UTF-8";
    LC_MEASUREMENT = "en_IE.UTF-8";
    LC_PAPER = "en_IE.UTF-8";
  };
  console.keyMap = "dk-latin1";

  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";
  services.resolved.enable = true;
  services.tailscale = {
    enable = true;
    # Use the homelab's advertised host routes when away from the LAN.
    extraSetFlags = [ "--accept-routes=true" ];
  };
  services.fwupd.enable = true;
  services.fstrim.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  programs.fish.enable = true;
  programs.localsend.enable = true;
  programs.mosh = {
    enable = true;
    openFirewall = false;
  };
  networking.firewall.interfaces.tailscale0.allowedUDPPortRanges = [
    {
      from = 60000;
      to = 61000;
    }
  ];
  users.users.joseph = {
    isNormalUser = true;
    description = "Joseph Petersen";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keyFiles = [ ../keys/joseph.pub ];
  };
  users.users.root.openssh.authorizedKeys.keyFiles = [ ../keys/joseph.pub ];

  # Each host decrypts its secrets with its own persistent SSH host key.
  # Never put private keys or plaintext secrets in Nix expressions or the store.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.gnupg.sshKeyPaths = [ ];

  environment.systemPackages = with pkgs; [
    age
    curl
    git
    jq
    neovim
    sops
    ssh-to-age
  ];
}
