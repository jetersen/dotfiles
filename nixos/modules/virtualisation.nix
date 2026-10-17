{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  users.users.joseph.extraGroups = [
    "libvirtd"
    "kvm"
  ];
  # Use libvirt's standard NAT network for new local VMs.
  systemd.tmpfiles.rules = [
    "L+ /var/lib/libvirt/qemu/networks/autostart/default.xml - - - - ../default.xml"
  ];

  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
}
