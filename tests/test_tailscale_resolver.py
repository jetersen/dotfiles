from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / 'nixos/modules/tailscale-resolver-init.sh'


class TailscaleResolverTests(unittest.TestCase):
  def initialize(self, resolver, fallback):
    subprocess.run(['bash', str(SOURCE), str(resolver), str(fallback)], check=True)

  def test_fallback_tracks_dhcp_and_survives_tailscale_handover(self):
    with tempfile.TemporaryDirectory() as root:
      root = Path(root)
      resolver = root / 'resolv.conf'
      fallback = root / 'dhcp.conf'
      fallback.write_text('nameserver 10.45.0.1\n')
      self.initialize(resolver, fallback)
      self.assertEqual(resolver.readlink(), fallback)
      backup = root / 'resolv.pre-tailscale.conf'
      resolver.rename(backup)
      managed = 'nameserver 127.0.0.3\nsearch personal.ts.net work.ts.net\n'
      resolver.write_text(managed)
      inode = resolver.stat().st_ino
      fallback.write_text('nameserver 192.168.1.2\n')
      self.initialize(resolver, fallback)
      self.assertEqual(resolver.read_text(), managed)
      self.assertEqual(resolver.stat().st_ino, inode)
      resolver.unlink()
      backup.rename(resolver)
      self.assertEqual(resolver.read_text(), fallback.read_text())
      self.initialize(resolver, fallback)
      self.assertEqual(resolver.readlink(), fallback)

  def test_preserves_dangling_link_before_dhcp_is_ready(self):
    with tempfile.TemporaryDirectory() as root:
      root = Path(root)
      resolver = root / 'resolv.conf'
      fallback = root / 'dhcp.conf'
      resolver.symlink_to(fallback)
      inode = resolver.lstat().st_ino
      self.initialize(resolver, fallback)
      self.assertEqual(resolver.lstat().st_ino, inode)
