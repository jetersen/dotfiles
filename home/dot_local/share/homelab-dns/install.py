#!/usr/bin/env python3
"""Install host DNS services with private backups and an explicit staging mode."""
import argparse
import datetime
import json
import os
import re
import shutil
import signal
import subprocess
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True, timeout=30)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['magic-only', 'dnsdist'])
    parser.add_argument('--stage', action='store_true', help='Test dnsdist alongside the existing resolver')
    parser.add_argument('--uid', type=int, default=int(os.environ.get('PKEXEC_UID', os.environ.get('SUDO_UID', '1000'))))
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run with sudo or pkexec')
    assert args.uid > 0
    source = Path(__file__).resolve().parent
    state = json.loads(run('tailscale', 'status', '--json'))
    suffix = state.get('MagicDNSSuffix', '')
    assert re.fullmatch(r'[a-z0-9-]+\.ts\.net', suffix), 'Tailscale must be connected'
    prefs = json.loads(run('tailscale', 'debug', 'prefs'))
    backup = Path('/var/lib/homelab-dns-backups') / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup.mkdir(parents=True, mode=0o700)
    backup.parent.chmod(0o700)
    files = {
        Path('/usr/local/lib/homelab-dns/reconcile.py'): (source / 'reconcile.py').read_bytes(),
        Path('/etc/homelab-dns/config.json'): (json.dumps({'mode': args.mode, 'magic_suffix': suffix, 'uid': args.uid}) + '\n').encode(),
    }
    units = []
    if args.mode == 'magic-only':
        assert not prefs['CorpDNS'], 'Disable Tailscale DNS management first'
        units = ['homelab-dns-reconcile.service']
    else:
        import vpn_bridge
        import reconcile
        intent = vpn_bridge.read_intent(args.uid)
        assert intent or (not args.stage and Path('/var/lib/homelab-dns/work-domains').exists()), 'Publish VPN domains with the plugin dnsdist backend first'
        reconcile.retain_domains(Path('/var/lib/homelab-dns/work-domains'), {d for item in intent.values() for d, _ in item['domains']})
        run('dnsdist', '--check-config', '-C', str(source / 'dnsdist.conf'))
        files[Path('/usr/local/lib/homelab-dns/vpn_bridge.py')] = (source / 'vpn_bridge.py').read_bytes()
        files[Path('/etc/homelab-dns/dnsdist.conf')] = (source / 'dnsdist.conf').read_text().replace('rockhopper-bleak.ts.net.', suffix + '.').encode()
        units = ['homelab-dns-vpn.service', 'homelab-dns.service']
    for unit in units:
        files[Path('/etc/systemd/system') / unit] = (source / unit).read_bytes()
    old_hook = Path('/etc/systemd/system/tailscaled.service.d/95-split-dns.conf')
    manifest = {}

    def save(target):
        if str(target) not in manifest:
            manifest[str(target)] = target.exists() or target.is_symlink()
            if manifest[str(target)]:
                saved = backup / target.relative_to('/')
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, saved, follow_symlinks=False)
            (backup / 'manifest.json').write_text(json.dumps(manifest))

    def install(target, contents):
        save(target)
        mode = target.stat().st_mode & 0o777 if target.exists() and not target.is_symlink() else 0o644
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink():
            target.unlink()
        if contents is None:
            target.unlink(missing_ok=True)
        else:
            target.write_bytes(contents)
            target.chmod(mode)

    (backup / 'tailscale-dns.json').write_text(json.dumps({'CorpDNS': prefs['CorpDNS']}))
    for target, contents in files.items():
        install(target, contents)
    if args.mode == 'magic-only':
        install(old_hook, None)
    run('systemctl', 'daemon-reload')
    for unit in units:
        run('systemctl', 'enable', '--now', unit)
        run('systemctl', 'restart', unit)
    if args.mode == 'dnsdist' and not args.stage:
        # The staged resolver must answer before changing the system's DNS path.
        answer = run('dig', '@127.0.0.2', 'example.com', 'A', '+time=3', '+tries=2', '+short')
        assert answer.strip(), 'Staged DNS did not answer'
        import dbus
        bus = dbus.SystemBus()
        name = 'net.openvpn.v3.netcfg'
        manager = dbus.Interface(bus.get_object(name, '/net/openvpn/v3/netcfg'), name)
        assert not list(manager.FetchInterfaceList()), 'Disconnect the work VPN for activation, then reconnect afterward'
        # Preserve OpenVPN's DNS metadata through its file backend, without
        # allowing it to overwrite the system resolver or reactivate resolved.
        config_path = Path(str(dbus.Interface(bus.get_object(name, '/net/openvpn/v3/netcfg'), 'org.freedesktop.DBus.Properties').Get(name, 'config_file')))
        assert config_path == Path('/var/lib/openvpn3/netcfg.json')
        assert Path('/usr/lib/libnss_mdns_minimal.so.2').exists()
        # OpenVPN uses JSON with comments; its own editor preserves the format.
        save(config_path)
        run('openvpn3-admin', 'netcfg-service', '--config-unset', 'systemd-resolved')
        run('openvpn3-admin', 'netcfg-service', '--config-set', 'resolv-conf', '/var/lib/openvpn3/dnsdist-resolv.conf')
        install(Path('/var/lib/openvpn3/dnsdist-resolv.conf'), b'nameserver 127.0.0.2\n')
        install(Path('/etc/resolv.conf'), f'nameserver 127.0.0.2\nsearch {suffix} lan.jetersen.dev\noptions timeout:2 attempts:2\n'.encode())
        install(Path('/etc/NetworkManager/conf.d/90-homelab-dns.conf'), b'[main]\ndns=none\nrc-manager=unmanaged\n')
        # Preserve .local lookup through the already-installed Avahi/NSS module.
        nss = Path('/etc/nsswitch.conf')
        text = nss.read_text().replace('resolve [!UNAVAIL=return]', 'mdns_minimal [NOTFOUND=return]')
        install(nss, text.encode())
        run('tailscale', 'set', '--accept-dns=false')
        run('nmcli', 'general', 'reload', 'conf')
        dbus_manager = dbus.Interface(bus.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus'), 'org.freedesktop.DBus')
        pid = int(dbus_manager.GetConnectionUnixProcessID(name))
        assert Path(f'/proc/{pid}/exe').resolve().name == 'openvpn3-service-netcfg'
        os.kill(pid, signal.SIGTERM)
        run('systemctl', 'disable', '--now', 'systemd-resolved.service')
        run('systemctl', 'mask', 'systemd-resolved.service', 'systemd-resolved-varlink.socket', 'systemd-resolved-monitor.socket')
        run('systemctl', 'stop', 'systemd-resolved-varlink.socket', 'systemd-resolved-monitor.socket')
    print('Installed', args.mode, '(staged)' if args.stage else '', 'Backup:', backup)


if __name__ == '__main__':
    main()
