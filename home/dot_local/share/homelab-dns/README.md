# Homelab DNS

These files provide an optional, manually installed DNS setup for other Linux
systems. Copying dotfiles alone does not configure DNS. Framework's NixOS setup
uses its shared Tailscale daemon for DNS and NetworkManager DNS when stopped;
it does not install these services. See the root
[README](../../../../README.md#work-access-and-dns) for NixOS networking.

## Manual installation

Requires Tailscale and NetworkManager. The dnsdist mode also needs dnsdist,
Python, bind tools (`dig`), Avahi, and nss-mdns.
The installer prints a backup directory containing replaced files and the
previous Tailscale DNS preference. Keep it for rollback.

For MagicDNS with systemd-resolved, disable Tailscale DNS management first:

```sh
sudo tailscale set --accept-dns=false
sudo python3 ~/.local/share/homelab-dns/install.py magic-only
```

For dnsdist, stage and check public, home and MagicDNS resolution:

```sh
sudo python3 ~/.local/share/homelab-dns/install.py dnsdist --stage
dig @127.0.0.2 example.com
```

Activate after checking the staged resolver:

```sh
sudo python3 ~/.local/share/homelab-dns/install.py dnsdist
```

Activation replaces system DNS with dnsdist and disables systemd-resolved and
NetworkManager/Tailscale DNS management. `.local` lookup uses Avahi. Rerun
installation after changing service files or the tailnet suffix.

## Rollback for manual installations

Use the backup from the installation being reversed. Its `manifest.json` records
which files to restore and which previously absent files to remove. Preserve
symlinks and metadata when restoring.

For MagicDNS-only mode, stop and disable `homelab-dns-reconcile.service`, restore
the backup, and run `systemctl daemon-reload`.

For dnsdist mode, unmask systemd-resolved and its sockets, restore the backup,
and run `systemctl daemon-reload`. Start and enable systemd-resolved, run
`nmcli general reload conf`, and restore Tailscale's saved DNS preference with
`tailscale set --accept-dns=true` or `false`. Verify resolution before disabling
`homelab-dns.service`.
