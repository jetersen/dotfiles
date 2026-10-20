"""Exercise routing, credential boundaries and ambiguous launch handling offline."""

import contextlib
import copy
import io
import json
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

import t3_remote as bridge


def catalog():
    return {
        "schemaVersion": 1,
        "targets": [
            {
                "_tag": "BearerConnectionTarget",
                "environmentId": "remote",
                "connectionId": "route",
            }
        ],
        "profiles": [
            {
                "_tag": "BearerConnectionProfile",
                "environmentId": "remote",
                "label": "desktop",
                "connectionId": "route",
                "httpBaseUrl": "https://example.test/",
                "wsBaseUrl": "wss://example.test/",
            }
        ],
        "credentials": [
            {
                "connectionId": "route",
                "credential": {
                    "_tag": "BearerConnectionCredential",
                    "token": "private-token",
                },
            }
        ],
        "disabledEnvironmentIds": [],
    }


def providers():
    return [
        {
            "instanceId": "codex",
            "enabled": True,
            "installed": True,
            "models": [{"id": "sol", "options": []}],
            "auth": {"token": "private-token"},
        }
    ]


def request():
    return {
        "projectId": "project",
        "title": "Test",
        "modelSelection": {"instanceId": "codex", "model": "sol"},
        "runtimeMode": "approval-required",
        "interactionMode": "default",
        "workspaceStrategy": {"type": "root"},
        "initialMessage": {"text": "allow", "attachments": []},
    }


def remote():
    route, token = bridge.select_route(catalog(), "remote", None)
    return bridge.Remote(route, token)


class BridgeTests(unittest.TestCase):
    def test_discovery_never_contains_credentials(self):
        self.assertNotIn("private-token", json.dumps(bridge.routes(catalog())))
        self.assertNotIn(
            "private-token", json.dumps(bridge.provider_summary(providers()))
        )

    def test_disabled_and_ambiguous_routes_are_refused(self):
        disabled = catalog()
        disabled["disabledEnvironmentIds"] = ["remote"]
        with self.assertRaisesRegex(bridge.BridgeError, "disabled"):
            bridge.select_route(disabled, "desktop", None)
        ambiguous = catalog()
        alternate = copy.deepcopy(ambiguous["profiles"][0])
        alternate["connectionId"] = "alternate"
        ambiguous["profiles"].append(alternate)
        ambiguous["targets"].append(
            {
                "_tag": "BearerConnectionTarget",
                "environmentId": "remote",
                "connectionId": "alternate",
            }
        )
        with self.assertRaisesRegex(bridge.BridgeError, "Select one"):
            bridge.select_route(ambiguous, "remote", None)
        self.assertEqual(
            bridge.select_route(ambiguous, "remote", "route")[0]["connectionId"],
            "route",
        )

    def test_plaintext_and_cross_origin_websocket_are_refused(self):
        for address in (
            "ws://example.test/",
            "wss://other.test/",
            "wss://example.test/?token=secret",
        ):
            with self.subTest(address=address):
                value = catalog()
                value["profiles"][0]["wsBaseUrl"] = address
                with self.assertRaises(bridge.BridgeError):
                    bridge.select_route(value, "remote", None)

    def test_identity_mismatch_prevents_credential_use(self):
        client = remote()
        client.get = Mock(return_value={"environmentId": "other"})
        with self.assertRaisesRegex(bridge.BridgeError, "identity"):
            client.verify()
        client.get.assert_called_once_with(
            ".well-known/t3/environment", authenticated=False
        )

    def test_http_error_does_not_echo_credentials(self):
        client = remote()
        client.opener = Mock()
        client.opener.open.side_effect = HTTPError(
            "https://example.test", 307, "private-token", {}, None
        )
        with self.assertRaisesRegex(bridge.BridgeError, "status 307") as error:
            client.get("api/projects")
        self.assertNotIn("private-token", str(error.exception))

    def test_invalid_target_and_local_attachments_are_refused(self):
        for key, value in (
            ("projectId", "local-project"),
            ("modelSelection", {"instanceId": "codex", "model": "absent"}),
            ("initialMessage", {"text": "allow", "attachments": [{"id": "local"}]}),
        ):
            with self.subTest(key=key):
                launch = request()
                launch[key] = value
                with self.assertRaises(bridge.BridgeError):
                    bridge.validate_launch(launch, [{"id": "project"}], providers())

    def test_rpc_preserves_protocol_and_answers_heartbeat(self):
        import websocket

        ws = Mock()
        ws.getstatus.return_value = 101
        ws.recv.side_effect = [
            json.dumps({"_tag": "Ping"}),
            json.dumps(
                {
                    "_tag": "Exit",
                    "requestId": "request-id",
                    "exit": {"_tag": "Success", "value": {"ok": True}},
                }
            ),
        ]
        with (
            patch.object(websocket, "create_connection", return_value=ws) as connect,
            patch.object(bridge.uuid, "uuid4", return_value="request-id"),
        ):
            self.assertEqual(remote().rpc("server.getConfig", {}), {"ok": True})
        self.assertEqual(connect.call_args.kwargs["redirect_limit"], 0)
        frames = [json.loads(call.args[0]) for call in ws.send.call_args_list]
        self.assertEqual(frames[0]["tag"], "server.getConfig")
        self.assertEqual(frames[1], {"_tag": "Pong"})
        ws.close.assert_called_once()

    def test_websocket_redirect_never_sends_request(self):
        import websocket

        ws = Mock()
        ws.getstatus.return_value = 307
        with (
            patch.object(websocket, "create_connection", return_value=ws),
            self.assertRaises(bridge.BridgeError),
        ):
            remote().rpc("orchestration.launchThread", request())
        ws.send.assert_not_called()
        ws.close.assert_called_once()

    def test_lost_launch_response_preserves_ids_and_does_not_retry(self):
        client = remote()
        client.projects = Mock(return_value=[{"id": "project"}])
        client.providers = Mock(return_value=providers())
        client.get = Mock(return_value=None)
        client.rpc = Mock(side_effect=bridge.BridgeError("response lost"))
        output = io.StringIO()
        with contextlib.redirect_stdout(output), self.assertRaises(bridge.BridgeError):
            bridge.launch(client, request(), "fixed-thread")
        receipt = json.loads(output.getvalue())
        self.assertEqual(receipt["threadId"], "fixed-thread")
        client.rpc.assert_called_once()
        self.assertEqual(
            client.rpc.call_args.args[1]["commandId"], receipt["commandId"]
        )
        self.assertEqual(
            client.rpc.call_args.args[1]["runtimeMode"], "approval-required"
        )

    def test_existing_thread_prevents_second_launch(self):
        client = remote()
        client.projects = Mock(return_value=[{"id": "project"}])
        client.providers = Mock(return_value=providers())
        client.get = Mock(return_value={"projection": {}})
        client.rpc = Mock()
        with self.assertRaisesRegex(bridge.BridgeError, "already exists"):
            bridge.launch(client, request(), "fixed-thread")
        client.rpc.assert_not_called()

    def test_status_omits_conversation_and_arbitrary_server_fields(self):
        output = bridge.summarize(
            {
                "thread": {"id": "thread", "title": "Test", "private": "hidden"},
                "runs": [{"id": "run", "status": "completed", "private": "hidden"}],
                "messages": [{"text": "hidden"}],
            },
            "remote",
        )
        self.assertNotIn("hidden", json.dumps(output))
        self.assertEqual(output["runs"][0]["status"], "completed")


if __name__ == "__main__":
    unittest.main()
