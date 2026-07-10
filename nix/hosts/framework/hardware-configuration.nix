{
  # TODO: Replace with the output of nixos-generate-config --show-hardware-config
  # from framework's NixOS installer. Record the exact Framework generation too.
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_ROOT_REPLACE_ME";
    fsType = "ext4";
  };
}
