"""Evaluate host/profile composition and validate rendered Niri files without activation.

Run with python3 tests/test_niri_profiles.py; requires Nix and niri on PATH.
"""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXPRESSION = r'''
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  rocket = flake.nixosConfigurations.rocket.config;
  inspect = system:
    let home = system.home-manager.users.joseph; in {
      files = lib.mapAttrs (_: file:
        if file.text != null then file.text else builtins.readFile file.source
      ) (lib.filterAttrs (name: _: lib.hasPrefix "niri/" name) home.xdg.configFile);
      outputs = home.dotfiles.niri.workspaceOutputs;
      portal = system.xdg.portal.config.niri."org.freedesktop.impl.portal.ScreenCast";
      pipewire = system.services.pipewire.enable;
      satellite = builtins.any (p: (p.pname or "") == "xwayland-satellite") system.environment.systemPackages;
      work = system.dotfiles.work.enable;
      vpn = system.programs.openvpn3.enable;
      steam = system.programs.steam.enable;
      graphics32 = system.hardware.graphics.enable32Bit;
      inputRemapper = system.services.input-remapper.enable;
      inputRemapperWantedBy = system.services.input-remapper.serviceWantedBy;
      gamescope = system.programs.steam.gamescopeSession.enable;
      packages = map (p: p.pname or p.name) home.home.packages;
      protontricks = system.programs.steam.protontricks.enable;
      compatTools = map (p: p.pname or p.name) system.programs.steam.extraCompatPackages;
      secrets = builtins.attrNames system.sops.secrets;
    };
in {
  framework = inspect flake.nixosConfigurations.framework.config;
  rocket = inspect rocket;
}
'''


class NiriProfilesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ['nix', '--extra-experimental-features', 'nix-command flakes',
             'eval', '--impure', '--json', '--expr', EXPRESSION],
            cwd=ROOT, check=True, text=True, capture_output=True,
        )
        cls.profiles = json.loads(result.stdout)

    def test_rendered_configs_validate(self):
        for name, profile in self.profiles.items():
            with self.subTest(host=name), tempfile.TemporaryDirectory() as directory:
                for filename, content in profile['files'].items():
                    path = Path(directory) / filename
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(content)
                subprocess.run(['niri', 'validate', '-c', str(Path(directory) / 'niri/config.kdl')], check=True)

    def test_chezmoi_shared_rules_validate(self):
        # These assets have no Go templates and can be validated without Chezmoi's login hook.
        subprocess.run(['niri', 'validate', '-c', str(ROOT / 'home/dot_config/niri/cfg/rules.kdl')], check=True)

    def test_shared_routing_and_capture_stack(self):
        for name, profile in self.profiles.items():
            with self.subTest(host=name):
                self.assertIn('workspace "chat"', profile['files']['niri/config.kdl'])
                rules = profile['files']['niri/cfg/shared-rules.kdl']
                self.assertIn('match app-id="Slack"', rules)
                self.assertIn('match app-id="discord"', rules)
                self.assertEqual(profile['portal'], 'gnome')
                self.assertTrue(profile['pipewire'])
                self.assertTrue(profile['satellite'])

    def test_host_and_gaming_boundaries(self):
        framework = self.profiles['framework']
        rocket = self.profiles['rocket']
        self.assertTrue(framework['work'])
        self.assertTrue(framework['vpn'])
        self.assertIn('spawn-at-startup "slack" "--ozone-platform=wayland"', framework['files']['niri/config.kdl'])
        self.assertEqual(framework['outputs']['chat'], 'Dell Inc. DELL P2725D 24CRZ64')
        self.assertEqual(framework['outputs']['music'], 'Dell Inc. DELL P2725D 3S5S864')
        self.assertNotIn('niri/cfg/gaming-rules.kdl', framework['files'])
        self.assertFalse(rocket['work'])
        self.assertFalse(rocket['vpn'])
        self.assertNotIn('aws-config', rocket['secrets'])
        self.assertTrue(rocket['steam'])
        self.assertTrue(rocket['graphics32'])
        self.assertTrue(rocket['inputRemapper'])
        self.assertEqual(rocket['inputRemapperWantedBy'], [])
        self.assertFalse(framework['inputRemapper'])
        self.assertFalse(rocket['gamescope'])
        self.assertTrue(rocket['protontricks'])
        self.assertIn('proton-ge', rocket['compatTools'])
        self.assertNotIn('protonup-qt', rocket['packages'])
        for package in ('lutris',):
            self.assertIn(package, rocket['packages'])
            self.assertNotIn(package, framework['packages'])
        self.assertIn('explorer.exe', rocket['files']['niri/cfg/gaming-rules.kdl'])
        self.assertIn('sc2_x64.exe', rocket['files']['niri/config.kdl'])
        self.assertNotIn('spawn-at-startup "slack"', rocket['files']['niri/config.kdl'])


if __name__ == '__main__':
    unittest.main()
