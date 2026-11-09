import argparse
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch
from urllib.error import HTTPError
from urllib.request import Request


SCRIPT = Path(__file__).resolve().parents[1] / "nixos/ci/cache-policy.py"
SPEC = importlib.util.spec_from_file_location("cache_policy", SCRIPT)
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)
SYSTEM = "/nix/store/" + "0" * 32 + "-nixos-system-framework"
CODEX = "/nix/store/" + "1" * 32 + "-codex"
RIDER = "/nix/store/" + "2" * 32 + "-rider"
OPTIONAL = "/nix/store/" + "3" * 32 + "-optional-tools"
SMALL = "/nix/store/" + "4" * 32 + "-small-tool"
MIB = 1024 * 1024


def cache(paths):
  result = Mock()
  result.probe.side_effect = lambda path: paths.get(path)
  return result


def narinfo(path=CODEX, references=()):
  return (f"StorePath: {path}\nURL: nar/codex.nar\nNarHash: sha256:fixture\n"
      f"References: {' '.join(Path(ref).name for ref in references)}\n"
      "Sig: fixture:signature\n").encode()


class PublicationTests(unittest.TestCase):
  def test_size_limit_never_excludes_required_system_dependencies(self):
    paths = {
      SYSTEM: {"narSize": MIB, "references": [CODEX, RIDER]},
      CODEX: {"narSize": 600 * MIB, "references": []},
      RIDER: {"narSize": 2000 * MIB, "references": []},
      OPTIONAL: {"narSize": 512 * MIB, "references": []},
      SMALL: {"narSize": 512 * MIB - 1, "references": []},
    }
    with redirect_stdout(io.StringIO()):
      selected = policy.publication_plan(paths, {SYSTEM, CODEX, RIDER}, cache({RIDER: set()}), 512 * MIB)
    self.assertEqual(set(selected), {SYSTEM, CODEX, SMALL})
    # An uncached prebuilt application is still required for deployment.
    with redirect_stdout(io.StringIO()):
      selected = policy.publication_plan(paths, {SYSTEM, CODEX, RIDER}, cache({}), 512 * MIB)
    self.assertIn(RIDER, selected)

  def test_upstream_outage_does_not_turn_into_unbounded_uploads(self):
    upstream = Mock()
    upstream.probe.side_effect = RuntimeError("HTTP 503")
    with self.assertRaisesRegex(RuntimeError, "503"):
      policy.publication_plan({CODEX: {"narSize": 1}}, {CODEX}, upstream, 512 * MIB)

  def test_upstream_metadata_must_match_local_references(self):
    with self.assertRaisesRegex(ValueError, "references differ"):
      policy.publication_plan({SYSTEM: {"narSize": 1, "references": [CODEX]}}, {SYSTEM},
                  cache({SYSTEM: set()}), 512 * MIB)

  def test_publish_requires_successful_upload_and_remote_closure_verification(self):
    args = argparse.Namespace(max_mib=512)
    required = {SYSTEM: {"narSize": 1, "references": [CODEX]},
          CODEX: {"narSize": 600 * MIB, "references": []}}
    with tempfile.TemporaryDirectory() as temporary:
      root = Path(temporary)
      for host in ("framework", "rocket"):
        (root / f"{host}-system").write_text(SYSTEM + "\n")
      for name in ("project-shells", "check-outputs", "pc2mqtt-deps"):
        (root / name).write_text("")
      with patch.dict(policy.os.environ, RUNNER_TEMP=temporary), \
        patch.object(policy, "inventory", return_value=required), \
        patch.object(policy.subprocess, "run") as run, redirect_stdout(io.StringIO()):
        # Successful upload exit code cannot conceal a missing remote dependency.
        with self.assertRaisesRegex(RuntimeError, "Binary not available"):
          policy.publish(args, cache({SYSTEM: {CODEX}}), cache({}))
        self.assertIn("--ignore-upstream-cache-filter", run.call_args.args[0])
        self.assertIn(CODEX + "\n", run.call_args.kwargs["input"])
        run.side_effect = subprocess.CalledProcessError(1, "attic")
        with self.assertRaises(subprocess.CalledProcessError):
          policy.publish(args, cache({SYSTEM: {CODEX}, CODEX: set()}), cache({}))


class ReadinessTests(unittest.TestCase):
  def test_remote_closure_can_span_caches_and_contain_cycles(self):
    public = cache({RIDER: set()})
    private = cache({SYSTEM: {CODEX, RIDER}, CODEX: {SYSTEM}})
    with redirect_stdout(io.StringIO()):
      self.assertEqual(policy.verify([SYSTEM], [public, private]), {SYSTEM, CODEX, RIDER})
    self.assertEqual(private.probe.call_count, 2)

  def test_transitive_miss_defers_deployment(self):
    with self.assertRaisesRegex(RuntimeError, "Binary not available"):
      policy.verify([SYSTEM], [cache({SYSTEM: {CODEX}})])

  def test_other_cache_can_satisfy_path_during_outage(self):
    offline = Mock()
    offline.probe.side_effect = RuntimeError("HTTP 503")
    self.assertEqual(policy.available(CODEX, [offline, cache({CODEX: set()})]), set())

  def test_cached_graph_must_match_ci_build(self):
    with self.assertRaisesRegex(ValueError, "Cached references differ"):
      policy.verify([SYSTEM], [cache({SYSTEM: set()})], {SYSTEM: {"references": [CODEX]}})


class ProtocolTests(unittest.TestCase):
  def test_probe_checks_nar_endpoint_without_downloading_it(self):
    client = policy.Cache(policy.PRIVATE)
    with patch.object(client, "request", side_effect=[narinfo(references=[SYSTEM]), b""]) as request:
      self.assertEqual(client.probe(CODEX), {SYSTEM})
      self.assertEqual(request.call_args.args, (policy.PRIVATE + "/nar/codex.nar",))
      self.assertEqual(request.call_args.kwargs, {"method": "HEAD"})

  def test_narinfo_without_its_payload_is_not_ready(self):
    client = policy.Cache(policy.PRIVATE)
    with patch.object(client, "request", side_effect=[narinfo(), None]):
      self.assertIsNone(client.probe(CODEX))

  def test_references_field_may_be_omitted_for_a_leaf(self):
    client = policy.Cache(policy.PRIVATE)
    with patch.object(client, "request", side_effect=[narinfo().replace(b"References: \n", b""), b""]):
      self.assertEqual(client.probe(CODEX), set())

  def test_mismatched_path_and_unsafe_references_are_rejected(self):
    client = policy.Cache(policy.PRIVATE)
    for body in (narinfo(path=SYSTEM), narinfo().replace(b"References: ", b"References: ../secret")):
      with self.subTest(body=body), patch.object(client, "request", return_value=body):
        with self.assertRaises(ValueError):
          client.probe(CODEX)

  def test_only_404_means_absent(self):
    client = policy.Cache(policy.PRIVATE)
    for code in (404, 401, 403, 500):
      opener = Mock()
      opener.open.side_effect = HTTPError(policy.PRIVATE, code, "fixture", {}, None)
      with self.subTest(code=code), patch.object(policy, "build_opener", return_value=opener):
        if code == 404:
          self.assertIsNone(client.request(policy.PRIVATE))
        else:
          with self.assertRaisesRegex(RuntimeError, str(code)):
            client.request(policy.PRIVATE)

  def test_credentials_are_not_forwarded_to_another_origin(self):
    client = policy.Cache(policy.PRIVATE, ("user", None, "secret"))
    opener = MagicMock()
    opener.open.return_value.__enter__.return_value.read.return_value = b"fixture"
    with patch.object(policy, "build_opener", return_value=opener):
      client.request(policy.PRIVATE)
      self.assertIn("Authorization", opener.open.call_args.args[0].headers)
      client.request(policy.PUBLIC)
      self.assertNotIn("Authorization", opener.open.call_args.args[0].headers)
    request = Request(policy.PRIVATE, headers={"Authorization": "Basic secret"})
    redirected = policy.SafeRedirect().redirect_request(request, None, 302, "fixture", {}, policy.PUBLIC)
    self.assertNotIn("Authorization", redirected.headers)
    with self.assertRaisesRegex(RuntimeError, "HTTPS"):
      policy.SafeRedirect().redirect_request(request, None, 302, "fixture", {}, "http://insecure/")


class UpgradeTests(unittest.TestCase):
  def test_checked_revision_is_also_used_for_activation(self):
    revision = "a" * 40
    flake = "git+https://example.test/dotfiles.git?ref=main"
    args = argparse.Namespace(flake=flake, host="framework", rebuild="/bin/nixos-rebuild")
    outputs = [json.dumps({"locked": {"rev": revision}}).encode(), SYSTEM]
    with patch.object(policy.subprocess, "check_output", side_effect=outputs) as output, \
      patch.object(policy.subprocess, "run") as run, \
      patch.object(policy.signal, "alarm"), redirect_stdout(io.StringIO()):
      policy.upgrade(args, [cache({SYSTEM: set()})])
    pinned = flake + "&rev=" + revision
    self.assertIn(pinned + "#nixosConfigurations.framework.config.system.build.toplevel", output.call_args.args[0])
    self.assertEqual(run.call_args.args[0], [args.rebuild, "switch", "--no-write-lock-file", "--flake", pinned + "#framework"])

  def test_missing_binary_never_invokes_rebuild(self):
    args = argparse.Namespace(flake="git+https://example.test/dotfiles.git?ref=main", host="framework", rebuild="rebuild")
    with patch.object(policy.subprocess, "check_output", side_effect=[json.dumps({"locked": {"rev": "a" * 40}}).encode(), SYSTEM]), \
      patch.object(policy.subprocess, "run") as run:
      with self.assertRaisesRegex(RuntimeError, "Binary not available"):
        policy.upgrade(args, [cache({})])
      run.assert_not_called()

  def test_readiness_timeout_never_invokes_rebuild(self):
    args = argparse.Namespace(flake="git+https://example.test/dotfiles.git?ref=main", host="framework", rebuild="rebuild")
    with patch.object(policy.subprocess, "check_output", side_effect=[json.dumps({"locked": {"rev": "a" * 40}}).encode(), SYSTEM]), \
       patch.object(policy, "verify", side_effect=TimeoutError("deadline exceeded")), \
       patch.object(policy.subprocess, "run") as run:
      with self.assertRaises(TimeoutError):
        policy.upgrade(args, [cache({})])
      run.assert_not_called()

  def test_existing_revision_is_replaced(self):
    result = policy.pinned_flake("git+https://example.test/repo?ref=main&rev=" + "a" * 40, "b" * 40)
    self.assertEqual(result.count("rev="), 1)
    self.assertTrue(result.endswith("b" * 40))

  def test_refresh_protects_all_retained_generations_and_booted_system(self):
    client = cache({SYSTEM: set(), CODEX: set(), RIDER: None})
    with patch.object(policy.glob, "glob", return_value=["/nix/var/nix/profiles/system-1-link"]), \
      patch.object(policy.Path, "exists", return_value=True), \
      patch.object(policy.Path, "resolve", side_effect=[Path(SYSTEM), Path(CODEX), Path(RIDER)]), \
      patch.object(policy, "inventory", return_value={SYSTEM: {}, CODEX: {}, RIDER: {}}) as inventory, \
      redirect_stdout(io.StringIO()):
      policy.refresh(client)
    self.assertEqual(set(inventory.call_args.args[0]), {SYSTEM, CODEX, RIDER})
    self.assertEqual({call.args[0] for call in client.probe.call_args_list}, {SYSTEM, CODEX, RIDER})


if __name__ == "__main__":
  unittest.main()
