import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PACKAGES = Path(__file__).resolve().parents[1] / "nixos" / "packages"


class PackageUpdates(unittest.TestCase):
  def setUp(self):
    self.temporary = tempfile.TemporaryDirectory()
    self.addCleanup(self.temporary.cleanup)
    self.directory = Path(self.temporary.name)
    for name in (
      "update-claude-code.sh",
      "update-t3code.sh",
      "claude-code-manifest.json",
      "workstation-manifest.json",
    ):
      shutil.copy2(PACKAGES / name, self.directory / name)
    self.fixture = self.directory / "response.json"
    curl = self.directory / "curl"
    curl.write_text(
      "#!/usr/bin/env bash\n"
      'if [[ "${!#}" == */latest ]]; then\n'
      "  echo 9.8.7\n"
      "else\n"
      '  cat "$UPDATE_FIXTURE"\n'
      "fi\n"
    )
    curl.chmod(0o755)
    self.environment = {
      **os.environ,
      "PATH": str(self.directory) + os.pathsep + os.environ["PATH"],
      "UPDATE_FIXTURE": str(self.fixture),
    }

  def run_update(self, script, response, *arguments):
    self.fixture.write_text(json.dumps(response))
    return subprocess.run(
      ["bash", str(self.directory / script), *arguments],
      env=self.environment,
      capture_output=True,
      text=True,
    )

  def test_claude_keeps_only_required_metadata(self):
    minimal = {
      "version": "9.8.7",
      "platforms": {"linux-x64": {"checksum": "a" * 64}},
    }
    upstream = {
      **minimal,
      "sdkCompat": {"testedWrapperVersions": ["unused"]},
      "platforms": {
        "linux-x64": {"checksum": "a" * 64, "size": 123},
        "darwin-arm64": {"checksum": "b" * 64},
      },
    }
    for arguments in ((), ("9.8.7",)):
      with self.subTest(arguments=arguments):
        result = self.run_update("update-claude-code.sh", upstream, *arguments)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = self.directory / "claude-code-manifest.json"
        self.assertEqual(json.loads(output.read_text()), minimal)

  def test_claude_invalid_response_preserves_pin(self):
    output = self.directory / "claude-code-manifest.json"
    before = output.read_bytes()
    for version, checksum in (("9.8.6", "a" * 64), ("9.8.7", "invalid")):
      with self.subTest(version=version, checksum=checksum):
        result = self.run_update(
          "update-claude-code.sh",
          {"version": version, "platforms": {"linux-x64": {"checksum": checksum}}},
          "9.8.7",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output.read_bytes(), before)

  def test_t3_updates_both_hashes_and_preserves_other_packages(self):
    output = self.directory / "workstation-manifest.json"
    before = json.loads(output.read_text())
    response = {
      "assets": [
        {"name": "t3-9.8.7-linux-x64.tar.gz", "digest": "sha256:" + "a" * 64},
        {"name": "T3-Code-9.8.7-x86_64.AppImage", "digest": "sha256:" + "b" * 64},
      ]
    }
    result = self.run_update("update-t3code.sh", response, "9.8.7")
    self.assertEqual(result.returncode, 0, result.stderr)
    before["t3code"] = {
      "repo": "pingdotgg/t3code",
      "version": "v9.8.7",
      "cliSha256": "a" * 64,
      "desktopSha256": "b" * 64,
    }
    self.assertEqual(json.loads(output.read_text()), before)

  def test_t3_missing_artifact_preserves_pin(self):
    output = self.directory / "workstation-manifest.json"
    before = output.read_bytes()
    result = self.run_update("update-t3code.sh", {"assets": []}, "9.8.7")
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(output.read_bytes(), before)


if __name__ == "__main__":
  unittest.main()
