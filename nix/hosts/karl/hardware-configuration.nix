{
  # TODO: Replace with the output of nixos-generate-config --show-hardware-config
  # from karl's NixOS installer. Add accelerator-specific configuration separately.
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_ROOT_REPLACE_ME";
    fsType = "ext4";
  };
}
