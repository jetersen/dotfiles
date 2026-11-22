"""Declared agent settings preserve private/user fields and remain idempotent."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("agent_config", ROOT / "nixos/hosts/rocket/agent-observability/merge_config.py")
config = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(config)


class ConfigTests(unittest.TestCase):
  def test_merge_preserves_unmanaged_nested_settings_and_is_idempotent(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      target, template = root / "config.toml", root / "declared.toml"
      target.write_text('auth_token = "fixture-only"\n[vector]\nenabled = false\n[vector.embeddings]\nmodel = "old"\nuser_setting = "keep"\n')
      template.write_text('[vector]\nenabled = true\n[vector.embeddings]\nmodel = "nomic-embed-text"\n')
      config.configure(target, template)
      first = target.read_text()
      parsed = config.tomlkit.parse(first)
      self.assertEqual(parsed["auth_token"], "fixture-only")
      self.assertEqual(parsed["vector"]["embeddings"]["user_setting"], "keep")
      self.assertEqual(parsed["vector"]["embeddings"]["model"], "nomic-embed-text")
      self.assertTrue(parsed["vector"]["enabled"])
      self.assertEqual(target.stat().st_mode & 0o777, 0o600)
      config.configure(target, template)
      self.assertEqual(target.read_text(), first)

  def test_fresh_configuration_matches_declared_values(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      target, template = root / "config.toml", root / "declared.toml"
      template.write_text('[vector]\nenabled = true\n')
      config.configure(target, template)
      self.assertEqual(config.tomlkit.parse(target.read_text()), config.tomlkit.parse(template.read_text()))


if __name__ == "__main__":
  unittest.main()
