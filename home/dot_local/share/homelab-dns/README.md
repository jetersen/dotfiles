# Homelab DNS

These Linux services provide two host DNS modes. Install them explicitly as
root; copying the dotfiles alone does not change networking. The installer
records replaced files and the previous Tailscale DNS preference in a private
backup and prints its location. It does not restart Tailscale or NetworkManager.

## Stationary workstation

`reconcile.py` maintains the Tailscale link's MagicDNS suffix in systemd-resolved.
It retries after link creation and resolver restarts. NetworkManager and the
work VPN retain ownership of their other DNS links.

With Tailscale DNS management already disabled:

```sh
sudo python3 ~/.local/share/homelab-dns/install.py magic-only
```

This enables `homelab-dns-reconcile.service`. Rerun the installer after changing
the tailnet suffix.

## Roaming laptop

`dnsdist` listens on loopback at `127.0.0.2:53` and owns system DNS. Ordinary
queries use the cluster DNS address or the NAS through Tailscale. Health checks
query a local authoritative record every two seconds. Public Cloudflare Security
DNS over HTTPS becomes eligible only after both home resolvers fail their health
checks. NXDOMAIN, REFUSED and SERVFAIL responses do not trigger public retries.
Recovery requires two successful checks. These thresholds mean transitions take
several seconds, rather than happening immediately for each client query.

No dnsdist packet cache is enabled. Public fallback answers have a maximum
one-second TTL to limit caching after recovery. Applications can retain their
own state or connections beyond DNS expiry. Home and reverse names never use
public fallback. Known work domains return REFUSED when their VPN is absent.

The [OpenVPN plugin](https://github.com/jetersen/dms-openvpn3) supports a selectable
`dnsdist` backend; its default remains `resolved`. It exports domains and tunnel
interface identity as user-owned JSON. The root `vpn_bridge.py` validates that
intent against the live kernel interface and obtains resolver addresses from
OpenVPN's D-Bus API. It publishes root-owned Lua data that dnsdist reloads without
restarting. Previously learned work domains remain private after disconnection.

Prerequisites: dnsdist, Python with dbus-python, bind tools (`dig`), Tailscale,
NetworkManager, OpenVPN 3 Linux, Avahi, and nss-mdns. Enable the plugin's dnsdist
backend while the work VPN is connected, then stage and test:

```sh
sudo python3 ~/.local/share/homelab-dns/install.py dnsdist --stage --uid "$(id -u)"
dig @127.0.0.2 example.com
dig @127.0.0.2 doubleclick.net
# Also query a known internal work hostname through 127.0.0.2.
```

Disconnect the work VPN, activate, and reconnect it:

```sh
sudo python3 ~/.local/share/homelab-dns/install.py dnsdist --uid "$(id -u)"
```

Activation assigns `/etc/resolv.conf` to dnsdist, stops and masks resolved and
its sockets, disables NetworkManager DNS management, disables Tailscale's DNS
management, and preserves `.local` lookup through Avahi/NSS. OpenVPN uses its
native file backend with a dedicated resolver file, so it retains DNS metadata
without overwriting `/etc/resolv.conf` or restarting resolved. VPN reconnection
is necessary to start the native backend with the new configuration.

Rerun activation with the VPN disconnected after changing these service files.
Changing backend while a VPN is active requires disconnecting first so the
previous resolver's interface state can be removed safely.

## Rollback

Keep the installer backup from the activation being reversed. Its
`manifest.json` lists target files and whether each existed beforehand. Restore
existing files from the corresponding path within the backup, preserving
symlinks and metadata; remove targets recorded as previously absent.

For MagicDNS-only rollback, stop and disable `homelab-dns-reconcile.service`,
restore its files, and run `systemctl daemon-reload`. Existing link settings
remain valid until the next link or resolver restart.

For laptop rollback:

1. Disconnect the work VPN and set the plugin backend to `resolved`.
2. Unmask resolved and its sockets, restore the activation backup's files, and
   run `systemctl daemon-reload`.
3. Enable and start `systemd-resolved.service`, then run
   `nmcli general reload conf`. Restore the saved Tailscale `CorpDNS` preference
   with `tailscale set --accept-dns=true` or `false`, as recorded.
4. Restart the OpenVPN network configuration process while no VPN interfaces
   exist, then reconnect the work VPN. Check public, home, MagicDNS, and work
   resolution before disabling `homelab-dns` and `homelab-dns-vpn`.

The native OpenVPN config editor is documented in
[OpenVPN's administration manual](https://github.com/OpenVPN/openvpn3-linux/blob/master/docs/man/openvpn3-admin-netcfg-service.8.rst).

## Checks

Run `python3 -B -m unittest discover -s tests -v` from this directory. The tests
start real dnsdist against isolated loopback DNS servers, covering blocking
responses, one/both home resolvers failing, recovery, public-answer TTLs, private
names, live VPN route changes, interface reuse, and routing-intent validation.
They do not alter the host's DNS settings.
