import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / 'home/dot_local/share/homelab-dns/resolv-conf.sh'
BASE = 'nameserver 127.0.0.2\nsearch personal.ts.net\noptions timeout:2 attempts:2\n'


class ResolverTests(unittest.TestCase):
  def publish(self, root, base=BASE):
    root = Path(root)
    (root / 'base.conf').write_text(base)
    target = root / 'resolv.conf'
    subprocess.run(['bash', str(SOURCE), str(root / 'base.conf'), str(target),
                    str(root / 'search-domain.json')], check=True,
                   env=dict(os.environ, LC_ALL='C'))
    self.assertEqual(target.stat().st_mode & 0o777, 0o644)
    self.assertEqual(list(root.glob('resolv.conf.*')), [])
    return target.read_text()

  def test_connect_disconnect_and_domain_changes_preserve_personal_dns(self):
    with tempfile.TemporaryDirectory() as root:
      path = Path(root) / 'search-domain.json'
      self.assertEqual(self.publish(root), BASE)
      for domain in ('work.ts.net', 'renamed.ts.net'):
        path.write_text(json.dumps(domain))
        result = self.publish(root)
        self.assertEqual(result, BASE.replace('search personal.ts.net', 'search personal.ts.net ' + domain))
        self.assertEqual(self.publish(root, result), result)
      path.write_text('null')
      self.assertEqual(self.publish(root), BASE)

  def test_invalid_search_metadata_is_ignored(self):
    with tempfile.TemporaryDirectory() as root:
      path = Path(root) / 'search-domain.json'
      for value in ([], {}, 12, 'work.ts.net\nnameserver 1.2.3.4', 'bad suffix', '',
                    '-bad.ts.net', 'x' * 64 + '.ts.net'):
        path.write_text(json.dumps(value))
        self.assertEqual(self.publish(root), BASE)
      path.write_text('invalid JSON')
      self.assertEqual(self.publish(root), BASE)

  def test_unchanged_resolver_is_not_replaced(self):
    with tempfile.TemporaryDirectory() as root:
      self.publish(root)
      target = Path(root) / 'resolv.conf'
      before = target.stat()
      self.publish(root)
      self.assertEqual(target.stat().st_ino, before.st_ino)
      self.assertEqual(target.stat().st_mtime_ns, before.st_mtime_ns)
