# Homelab DNS

NixOS configures these services through `nixos/modules/roaming-dns.nix` and
`nixos/hosts/rocket/services.nix`. See the root [README](../../../../README.md#work-access-and-dns)
for DNS routing behavior. The installer below is for other Linux systems;
copying dotfiles alone does not configure DNS.

## Manual installation

Requires Tailscale and NetworkManager. The dnsdist mode also needs dnsdist,
Python with dbus-python, bind tools (`dig`), OpenVPN 3 Linux, Avahi, and nss-mdns.
The installer prints a backup directory containing replaced files and the
previous Tailscale DNS preference. Keep it for rollback.

For MagicDNS with systemd-resolved, disable Tailscale DNS management first:

```sh
sudo tailscale set --accept-dns=false
sudo python3 ~/.local/share/homelab-dns/install.py magic-only
```

For dnsdist, select the `dnsdist` backend in the
[OpenVPN plugin](https://github.com/jetersen/dms-openvpn3), connect the VPN,
then stage and check resolution:

```sh
sudo python3 ~/.local/share/homelab-dns/install.py dnsdist --stage --uid "$(id -u)"
dig @127.0.0.2 example.com
# Also check a home hostname and a work hostname.
```

Disconnect the work VPN before activation, then reconnect afterward:

```sh
sudo python3 ~/.local/share/homelab-dns/install.py dnsdist --uid "$(id -u)"
```

Activation replaces system DNS with dnsdist, disables systemd-resolved and
NetworkManager/Tailscale DNS management, and configures OpenVPN to leave the
system resolver alone. `.local` lookup uses Avahi. Rerun installation after
changing service files or the tailnet suffix. Disconnect the VPN before changing
its DNS backend.

## Rollback for manual installations

Use the backup from the installation being reversed. Its `manifest.json` records
which files to restore and which previously absent files to remove. Preserve
symlinks and metadata when restoring.

For MagicDNS-only mode, stop and disable `homelab-dns-reconcile.service`, restore
the backup, and run `systemctl daemon-reload`.

For dnsdist mode:

1. Disconnect the work VPN and select the plugin's `resolved` backend.
2. Unmask systemd-resolved and its sockets, restore the backup, and run
   `systemctl daemon-reload`.
3. Start and enable systemd-resolved, run `nmcli general reload conf`, and restore
   Tailscale's saved DNS preference with `tailscale set --accept-dns=true` or `false`.
4. Restart OpenVPN's network configuration process with no VPN interfaces active,
   then reconnect. Check public, home, MagicDNS, and work resolution before
   disabling `homelab-dns` and `homelab-dns-vpn`.
