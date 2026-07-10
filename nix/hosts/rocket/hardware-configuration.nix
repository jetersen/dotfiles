{
  # TODO: Replace with the output of nixos-generate-config --show-hardware-config
  # from rocket's NixOS installer. Add CPU and GPU modules in this host directory.
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_ROOT_REPLACE_ME";
    fsType = "ext4";
  };
}
