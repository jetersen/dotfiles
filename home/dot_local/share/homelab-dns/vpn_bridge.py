#!/usr/bin/env python3
"""Validate unprivileged VPN routing intent and publish dnsdist backends."""
import ipaddress
import json
import logging
import os
import re
import socket
import time
from pathlib import Path

import reconcile

NETCFG = 'net.openvpn.v3.netcfg'
DOMAIN = re.compile(r'(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\Z')


def read_intent(uid):
    path = f'/run/user/{uid}/dms-openvpn3-dns/dnsdist-routes.json'
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return {}
    with os.fdopen(descriptor) as stream:
        assert os.fstat(stream.fileno()).st_uid == uid, 'Unexpected intent file owner'
        text = stream.read(1024 * 1024 + 1)
    assert len(text) <= 1024 * 1024
    data = json.loads(text)
    assert isinstance(data, dict) and len(data) <= 16
    for device, record in data.items():
        assert re.fullmatch(r'tun[0-9]+', device)
        assert type(record['index']) is int and record['index'] > 0
        assert isinstance(record['domains'], list) and len(record['domains']) <= 4096
        for domain, route_only in record['domains']:
            assert route_only is True and DOMAIN.fullmatch(domain)
    return data


def live_devices(bus):
    import dbus
    manager = dbus.Interface(bus.get_object(NETCFG, '/net/openvpn/v3/netcfg'), NETCFG)
    result = {}
    for path in manager.FetchInterfaceList():
        properties = dbus.Interface(bus.get_object(NETCFG, path), 'org.freedesktop.DBus.Properties')
        device = str(properties.Get(NETCFG, 'device_name'))
        # Current OpenVPN exposes no `active` property despite older API docs.
        # Connected plugin intent plus a matching live kernel ifindex gates use.
        if not re.fullmatch(r'tun[0-9]+', device):
            continue
        servers = [str(ipaddress.ip_address(str(x))) for x in properties.Get(NETCFG, 'dns_name_servers')]
        if servers:
            result[device] = servers[:8]
    return result


def routes(intent, devices, ifindex=socket.if_nametoindex):
    result = []
    for device, record in intent.items():
        try:
            if device not in devices or ifindex(device) != record['index']:
                continue
        except OSError:
            continue
        result.append({'device': device, 'pool': f'vpn_{device}_{record["index"]}',
                       'servers': devices[device], 'domains': [d for d, _ in record['domains']]})
    return result


def render(entries):
    # All values have been validated; JSON string quoting is also valid Lua here.
    quote = json.dumps
    return 'return {\n' + ''.join(
        '  {device=' + quote(x['device']) + ',pool=' + quote(x['pool']) +
        ',servers={' + ','.join(quote(s) for s in x['servers']) +
        '},domains={' + ','.join(quote(d) for d in x['domains']) + '}},\n'
        for x in entries) + '}\n'


def publish(path, text):
    if path.exists() and path.read_text() == text:
        return
    temporary = path.with_suffix('.tmp')
    temporary.write_text(text)
    temporary.chmod(0o644)
    temporary.replace(path)


def main():
    import dbus
    config = json.loads(Path('/etc/homelab-dns/config.json').read_text())
    uid = config['uid']
    assert type(uid) is int and uid > 0
    root = Path('/var/lib/homelab-dns')
    root.mkdir(parents=True, exist_ok=True)
    bus = dbus.SystemBus()
    previous_error = None
    while True:
        try:
            intent = read_intent(uid)
            reconcile.retain_domains(root / 'work-domains', {d for item in intent.values() for d, _ in item['domains']})
            entries = routes(intent, live_devices(bus))
            previous_error = None
        except Exception as error:
            # Never retain an unverified active route after a disconnect or API error.
            entries = []
            message = type(error).__name__
            if message != previous_error:
                logging.warning('VPN DNS bridge will retry: %s', message)
            previous_error = message
        publish(root / 'vpn-routes.lua', render(entries))
        time.sleep(2)


if __name__ == '__main__':
    main()
