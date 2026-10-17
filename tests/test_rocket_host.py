"""Evaluate preservation and deployment boundaries; never mount or alter filesystems."""

import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXPRESSION = r'''
let
  flake = builtins.getFlake (toString ./.);
  c = flake.nixosConfigurations.rocket.config;
in {
  filesystems = builtins.mapAttrs (_: fs: { inherit (fs) device fsType options; }) c.fileSystems;
  hasDisko = c ? disko;
  user = { inherit (c.users.users.joseph) uid group; gid = c.users.groups.joseph.gid; };
  work = c.dotfiles.work.enable;
  secrets = builtins.attrNames c.sops.secrets;
  tailscale = c.services.tailscale.package.version;
  automaticComin = c.systemd.services.comin.wantedBy;
  automaticFetch = c.systemd.services.comin-fetch.wantedBy;
  docker = c.virtualisation.docker.enable;
  rootlessDocker = c.virtualisation.docker.rootless.enable;
  managedHomeTargets = map (v: v.target) (builtins.filter (v: v.enable) (builtins.attrValues c.home-manager.users.joseph.home.file));
  runnerPrerequisites = c.systemd.services.forgejo-runner.unitConfig.ConditionPathExists;
}
'''


class RocketHostTests(unittest.TestCase):
  @classmethod
  def setUpClass(cls):
    cls.config = json.loads(subprocess.check_output([
      'nix', '--extra-experimental-features', 'nix-command flakes', 'eval',
      '--impure', '--json', '--expr', EXPRESSION,
    ], cwd=ROOT))

  def test_existing_devices_and_separate_new_root(self):
    c = self.config
    self.assertFalse(c['hasDisko'])
    fs = c['filesystems']
    self.assertIn('subvol=@nixos', fs['/']['options'])
    self.assertIn('subvol=@home', fs['/home']['options'])
    self.assertIn('subvol=@nixos-snapshots', fs['/.snapshots']['options'])
    self.assertNotIn('subvol=@/.snapshots', fs['/.snapshots']['options'])
    self.assertEqual(fs['/media/games']['device'], '/dev/disk/by-uuid/d49e4cc0-be81-4381-924a-6891cc37c982')
    self.assertEqual(fs['/home/joseph/.local/share/Steam']['device'], '/media/games/Steam')
    self.assertEqual(c['user'], {'uid': 1000, 'group': 'joseph', 'gid': 1000})

  def test_personal_host_waits_for_explicit_deployment_and_runner_migration(self):
    c = self.config
    self.assertFalse(c['work'])
    self.assertEqual(set(c['secrets']), {'joseph-password', 'nix-cache-netrc'})
    self.assertEqual(c['automaticComin'], [])
    self.assertEqual(c['automaticFetch'], [])
    self.assertGreaterEqual(tuple(map(int, c['tailscale'].split('.'))), (1, 104, 1))
    self.assertTrue(c['docker'])
    self.assertFalse(c['rootlessDocker'])
    self.assertIn('/var/lib/forgejo-runner/migration-ready', c['runnerPrerequisites'])

  def test_ai_session_trees_are_not_home_manager_targets(self):
    targets = [str(Path(p)) for p in self.config['managedHomeTargets']]
    for target in targets:
      self.assertFalse(target == '.t3' or target.startswith('.t3/'), target)
      self.assertFalse(target == '.config/t3code-v2' or target.startswith('.config/t3code-v2/'), target)
      if target == '.codex' or target.startswith('.codex/'):
        self.assertEqual(target, '.codex/AGENTS.md')
      if target == '.claude' or target.startswith('.claude/'):
        self.assertTrue(target == '.claude/CLAUDE.md' or target.startswith('.claude/skills/'), target)


if __name__ == '__main__':
  unittest.main()
