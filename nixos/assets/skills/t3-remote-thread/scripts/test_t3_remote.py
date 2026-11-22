"""Exercise routing, credential boundaries and ambiguous launch handling offline."""

import contextlib
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import copy
import io
import json
import os
from pathlib import Path
import shutil
import ssl
import struct
import subprocess
import tempfile
import threading
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
            "models": [
                {
                    "slug": "sol",
                    "name": "Sol",
                    "capabilities": {"optionDescriptors": []},
                }
            ],
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
    def test_safe_storage_accepts_both_t3_key_labels_only(self):
        item = Mock()
        item.get_attributes.return_value = {"application": "t3code"}
        item.is_locked.return_value = False
        for label in ("Chromium Safe Storage", "t3code Safe Storage"):
            item.get_label.return_value = label
            self.assertTrue(bridge.is_storage_key(item))
        item.get_attributes.return_value = {"application": "chromium"}
        self.assertFalse(bridge.is_storage_key(item))
        item.get_attributes.return_value = {"application": "t3code"}
        item.is_locked.return_value = True
        self.assertFalse(bridge.is_storage_key(item))

    def test_discovery_never_contains_credentials(self):
        self.assertNotIn("private-token", json.dumps(bridge.routes(catalog())))
        summary = bridge.provider_summary(providers())
        self.assertNotIn("private-token", json.dumps(summary))
        self.assertEqual(
            summary[0]["models"], [{"id": "sol", "label": "Sol", "options": []}]
        )

    def test_discovery_omits_learned_plaintext_routes(self):
        value = catalog()
        learned = copy.deepcopy(value["profiles"][0])
        learned.update(
            connectionId="learned",
            httpBaseUrl="http://example.test/",
            wsBaseUrl="ws://example.test/",
        )
        value["profiles"].append(learned)
        value["targets"].append(
            {
                "_tag": "BearerConnectionTarget",
                "environmentId": "remote",
                "connectionId": "learned",
            }
        )
        route, token = bridge.select_route(value, "remote", None)
        self.assertEqual(route["connectionId"], "route")
        self.assertEqual(token, "private-token")

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

    @unittest.skipUnless(shutil.which("openssl"), "TLS fixture needs openssl")
    def test_https_and_wss_verify_tls_and_ignore_environment_proxy(self):
        records = []
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cert, key = root / "cert.pem", root / "key.pem"
            subprocess.run(
                [
                    "openssl",
                    "req",
                    "-x509",
                    "-newkey",
                    "rsa:2048",
                    "-nodes",
                    "-days",
                    "1",
                    "-subj",
                    "/CN=localhost",
                    "-addext",
                    "subjectAltName=DNS:localhost",
                    "-keyout",
                    str(key),
                    "-out",
                    str(cert),
                ],
                capture_output=True,
                check=True,
                timeout=10,
            )

            class Handler(BaseHTTPRequestHandler):
                def log_message(self, *args):
                    pass

                def do_GET(self):
                    records.append((self.path, self.headers.get("Authorization")))
                    if self.path.startswith("/ws?"):
                        accept = base64.b64encode(
                            hashlib.sha1(
                                (
                                    self.headers["Sec-WebSocket-Key"]
                                    + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
                                ).encode()
                            ).digest()
                        ).decode()
                        self.send_response(101)
                        self.send_header("Upgrade", "websocket")
                        self.send_header("Connection", "Upgrade")
                        self.send_header("Sec-WebSocket-Accept", accept)
                        self.end_headers()
                        first, second = self.rfile.read(2)
                        length = second & 127
                        if length == 126:
                            length = struct.unpack("!H", self.rfile.read(2))[0]
                        mask = self.rfile.read(4)
                        data = self.rfile.read(length)
                        request = json.loads(
                            bytes(b ^ mask[i % 4] for i, b in enumerate(data))
                        )
                        payload = json.dumps(
                            {
                                "_tag": "Exit",
                                "requestId": request["id"],
                                "exit": {"_tag": "Success", "value": {"ok": True}},
                            }
                        ).encode()
                        header = (
                            bytes([0x81, len(payload)])
                            if len(payload) < 126
                            else struct.pack("!BBH", 0x81, 126, len(payload))
                        )
                        self.wfile.write(header + payload)
                        self.wfile.flush()
                        self.close_connection = True
                        return
                    payload = json.dumps(
                        {"environmentId": "remote"}
                        if self.path.startswith("/.well-known")
                        else {"authenticated": True}
                    ).encode()
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)

            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            server.daemon_threads = True
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(cert, key)
            server.socket = context.wrap_socket(server.socket, server_side=True)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            value = catalog()
            value["profiles"][0].update(
                httpBaseUrl=f"https://localhost:{server.server_port}/",
                wsBaseUrl=f"wss://localhost:{server.server_port}/",
            )
            route, token = bridge.select_route(value, "remote", None)
            client = bridge.Remote(route, token)
            try:
                with self.assertRaises(bridge.BridgeError):
                    client.verify()
                with self.assertRaises(bridge.BridgeError):
                    client.rpc("server.getConfig", {})
                self.assertEqual(records, [])
                with patch.dict(
                    os.environ,
                    {
                        "SSL_CERT_FILE": str(cert),
                        "NIX_SSL_CERT_FILE": str(cert),
                        "https_proxy": "http://127.0.0.1:1",
                        "HTTPS_PROXY": "http://127.0.0.1:1",
                        "no_proxy": "",
                        "NO_PROXY": "",
                    },
                ):
                    # Construct while proxy settings are present: opener discovery happens here.
                    bridge.Remote(route, token).verify()
                    self.assertEqual(
                        records,
                        [
                            ("/.well-known/t3/environment", None),
                            ("/api/auth/session", "Bearer private-token"),
                        ],
                    )
                    self.assertEqual(
                        bridge.Remote(route, token).rpc("server.getConfig", {}),
                        {"ok": True},
                    )
                    self.assertEqual(
                        records[-1],
                        ("/ws?orchestrationProtocol=2", "Bearer private-token"),
                    )
                    wrong_ws = {
                        **route,
                        "wsBaseUrl": route["wsBaseUrl"].replace(
                            "localhost", "127.0.0.1"
                        ),
                    }
                    with self.assertRaises(bridge.BridgeError):
                        bridge.Remote(wrong_ws, token).rpc("server.getConfig", {})
                    wrong = {
                        **route,
                        "httpBaseUrl": route["httpBaseUrl"].replace(
                            "localhost", "127.0.0.1"
                        ),
                    }
                    with self.assertRaises(bridge.BridgeError):
                        bridge.Remote(wrong, token).verify()
                    self.assertEqual(len(records), 3)
            finally:
                server.shutdown()
                server.server_close()
                worker.join()

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
            patch.object(bridge.http.client, "HTTPSConnection") as tls,
            patch.object(bridge.uuid, "uuid4", return_value="request-id"),
        ):
            self.assertEqual(remote().rpc("server.getConfig", {}), {"ok": True})
        self.assertEqual(connect.call_args.kwargs["redirect_limit"], 0)
        self.assertIs(connect.call_args.kwargs["socket"], tls.return_value.sock)
        tls.return_value.connect.assert_called_once()
        tls.return_value.close.assert_called_once()
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
            patch.object(bridge.http.client, "HTTPSConnection"),
            self.assertRaises(bridge.BridgeError),
        ):
            remote().rpc("orchestration.launchThread", request())
        ws.send.assert_not_called()
        ws.close.assert_called_once()

    def test_failed_or_missing_tls_socket_never_falls_back(self):
        import websocket

        for failed in [True, False]:
            connection = Mock()
            connection.sock = None
            connection.connect.side_effect = (
                OSError("private-token") if failed else None
            )
            with (
                patch.object(
                    bridge.http.client, "HTTPSConnection", return_value=connection
                ),
                patch.object(websocket, "create_connection") as connect,
                self.assertRaises(bridge.BridgeError) as error,
            ):
                remote().rpc("server.getConfig", {})
            connect.assert_not_called()
            connection.close.assert_called_once()
            self.assertNotIn("private-token", str(error.exception))

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
