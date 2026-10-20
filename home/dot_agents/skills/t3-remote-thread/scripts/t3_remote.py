# /// script
# requires-python = ">=3.11"
# dependencies = ["cryptography==50.0.2", "SecretStorage==3.5.0", "websocket-client==1.9.0"]
# ///
"""Temporary Linux desktop bridge to configured T3 HTTPS bearer environments."""

import argparse
import base64
import hashlib
import json
import os
import sys
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class BridgeError(Exception):
    pass


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def load_catalog(path):
    import secretstorage
    from cryptography.hazmat.primitives import padding
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    if sys.platform != "linux":
        raise BridgeError("This helper supports Linux Secret Service desktops only.")
    document = json.loads(path.read_text())
    if document.get("version") != 1:
        raise BridgeError("Unsupported encrypted catalog version.")
    encrypted = base64.b64decode(document["encryptedCatalog"], validate=True)
    if encrypted[:3] != b"v11":
        raise BridgeError("Unsupported safeStorage encryption; no fallback attempted.")
    # Headless provider processes may omit the existing user-session bus address.
    user_bus = Path(f"/run/user/{os.getuid()}/bus")
    if "DBUS_SESSION_BUS_ADDRESS" not in os.environ and user_bus.is_socket():
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={user_bus}"
    bus = secretstorage.dbus_init()
    try:
        keys = [
            item
            for collection in secretstorage.get_all_collections(bus)
            if not collection.is_locked()
            for item in collection.get_all_items()
            if is_storage_key(item)
        ]
        if len(keys) != 1:
            raise BridgeError("Need exactly one unlocked T3 safeStorage key.")
        key = hashlib.pbkdf2_hmac("sha1", keys[0].get_secret(), b"saltysalt", 1, 16)
        decryptor = Cipher(algorithms.AES(key), modes.CBC(b" " * 16)).decryptor()
        padded = decryptor.update(encrypted[3:]) + decryptor.finalize()
        unpadder = padding.PKCS7(128).unpadder()
        catalog = json.loads(unpadder.update(padded) + unpadder.finalize())
    finally:
        bus.close()
    if catalog.get("schemaVersion") != 1:
        raise BridgeError("Unsupported decrypted catalog schema.")
    return catalog


def is_storage_key(item):
    return (
        item.get_label() in ("Chromium Safe Storage", "t3code Safe Storage")
        and item.get_attributes().get("application") == "t3code"
        and not item.is_locked()
    )


def routes(catalog):
    disabled = set(catalog.get("disabledEnvironmentIds", []))
    targets = {t.get("connectionId"): t for t in catalog["targets"]}
    return [
        {
            "environmentId": p["environmentId"],
            "label": p["label"],
            "connectionId": p["connectionId"],
            "enabled": p["environmentId"] not in disabled,
            "httpBaseUrl": p["httpBaseUrl"],
            "wsBaseUrl": p["wsBaseUrl"],
        }
        for p in catalog["profiles"]
        if p.get("_tag") == "BearerConnectionProfile"
        and p.get("authorization") != "t3-connect"
        and urlsplit(p["httpBaseUrl"]).scheme == "https"
        and urlsplit(p["wsBaseUrl"]).scheme == "wss"
        and targets.get(p["connectionId"], {}).get("_tag") == "BearerConnectionTarget"
        and targets[p["connectionId"]]["environmentId"] == p["environmentId"]
    ]


def select_route(catalog, environment, connection_id):
    matches = [
        r
        for r in routes(catalog)
        if environment in (r["environmentId"], r["label"])
        and (connection_id is None or r["connectionId"] == connection_id)
    ]
    if len(matches) != 1:
        raise BridgeError(
            "Select one saved bearer route using environment ID and connection ID."
        )
    route = matches[0]
    if not route["enabled"]:
        raise BridgeError("The selected environment is disabled in T3.")
    http, ws = (urlsplit(route[k]) for k in ("httpBaseUrl", "wsBaseUrl"))
    if (
        http.scheme != "https"
        or ws.scheme != "wss"
        or not http.hostname
        or http.netloc != ws.netloc
        or http.path.rstrip("/") != ws.path.rstrip("/")
        or any((http.username, http.password, http.query, http.fragment))
        or any((ws.username, ws.password, ws.query, ws.fragment))
    ):
        raise BridgeError("Need HTTPS and WSS routes on the same origin and base path.")
    credentials = [
        c["credential"]
        for c in catalog["credentials"]
        if c["connectionId"] == route["connectionId"]
        and c["credential"].get("_tag") == "BearerConnectionCredential"
    ]
    if len(credentials) != 1 or not credentials[0].get("token"):
        raise BridgeError("Need exactly one saved bearer credential for the route.")
    return route, credentials[0]["token"]


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Redirects must not forward the desktop's credential to a different endpoint.
        return None


class Remote:
    def __init__(self, route, token):
        self.route = route
        self.headers = {
            "Authorization": "Bearer " + token,
            "x-t3-orchestration-protocol": "2",
        }
        self.opener = build_opener(NoRedirect())

    def get(self, path, *, authenticated=True, missing_ok=False):
        request = Request(
            self.route["httpBaseUrl"].rstrip("/") + "/" + path.lstrip("/"),
            headers=self.headers if authenticated else {},
        )
        try:
            with self.opener.open(request, timeout=20) as response:
                return json.load(response)
        except HTTPError as error:
            if missing_ok and error.code == 404:
                return None
            raise BridgeError(
                f"T3 HTTP request refused (status {error.code})."
            ) from None
        except (URLError, OSError):
            raise BridgeError(
                "T3 HTTPS connection failed; TLS verification remains enabled."
            ) from None

    def verify(self):
        identity = self.get(".well-known/t3/environment", authenticated=False)
        if identity.get("environmentId") != self.route["environmentId"]:
            raise BridgeError(
                "Server identity differs from the configured environment."
            )
        if self.get("api/auth/session").get("authenticated") is not True:
            raise BridgeError("The configured desktop session is not authenticated.")

    def rpc(self, method, payload):
        import websocket

        parsed = urlsplit(self.route["wsBaseUrl"])
        url = urlunsplit(
            (
                "wss",
                parsed.netloc,
                parsed.path.rstrip("/") + "/ws",
                "orchestrationProtocol=2",
                "",
            )
        )
        request_id = str(uuid.uuid4())
        try:
            ws = websocket.create_connection(
                url, header=self.headers, timeout=20, redirect_limit=0
            )
            try:
                if ws.getstatus() != 101:
                    raise BridgeError(
                        "WebSocket upgrade refused; redirects are not followed."
                    )
                ws.send(
                    json.dumps(
                        {
                            "_tag": "Request",
                            "id": request_id,
                            "tag": method,
                            "payload": payload,
                            "headers": [],
                        }
                    )
                )
                deadline = time.monotonic() + 50
                while time.monotonic() < deadline:
                    ws.settimeout(max(0.1, deadline - time.monotonic()))
                    frame = json.loads(ws.recv())
                    if frame.get("_tag") == "Ping":
                        ws.send(json.dumps({"_tag": "Pong"}))
                    elif (
                        frame.get("_tag") == "Exit"
                        and frame.get("requestId") == request_id
                    ):
                        result = frame["exit"]
                        if result.get("_tag") != "Success":
                            raise BridgeError(
                                "T3 RPC failed; raw error payload omitted."
                            )
                        return result["value"]
                raise BridgeError("T3 RPC timed out.")
            finally:
                ws.close()
        except (websocket.WebSocketException, OSError):
            raise BridgeError(
                "T3 WebSocket request failed; do not automatically retry launches."
            ) from None

    def projects(self):
        return self.get("api/projects")["projects"]

    def providers(self):
        return self.rpc("server.getConfig", {})["providers"]

    def status(self, thread_id):
        snapshot = self.get(
            "api/orchestration/threads/" + quote(thread_id, safe=""), missing_ok=True
        )
        if snapshot is None:
            raise BridgeError("Thread not found on this environment.")
        return summarize(snapshot["projection"], self.route["environmentId"])


def summarize(projection, environment_id):
    thread = projection["thread"]
    return {
        "environmentId": environment_id,
        "threadId": thread["id"],
        "title": thread["title"],
        "modelSelection": thread.get("modelSelection"),
        "runs": [
            {key: run.get(key) for key in ("id", "status")}
            for run in projection.get("runs", [])[-3:]
        ],
    }


def provider_summary(providers):
    return [
        {
            **{
                key: p.get(key)
                for key in (
                    "instanceId",
                    "displayName",
                    "enabled",
                    "installed",
                    "status",
                    "supportedRuntimeModes",
                )
            },
            "models": [
                {
                    "id": m["slug"],
                    "label": m["name"],
                    "options": (m.get("capabilities") or {}).get(
                        "optionDescriptors", []
                    ),
                }
                for m in p.get("models", [])
            ],
        }
        for p in providers
    ]


def validate_launch(request, projects, providers):
    fields = {
        "projectId",
        "title",
        "modelSelection",
        "runtimeMode",
        "interactionMode",
        "workspaceStrategy",
        "initialMessage",
    }
    if set(request) != fields:
        raise BridgeError("Launch request must contain exactly the documented fields.")
    if not any(p["id"] == request["projectId"] for p in projects):
        raise BridgeError("Project does not exist on the destination.")
    selection = request["modelSelection"]
    provider = next(
        (p for p in providers if p["instanceId"] == selection.get("instanceId")), None
    )
    if provider is None or not provider.get("enabled") or not provider.get("installed"):
        raise BridgeError("Destination provider is disabled, absent, or not installed.")
    if not any(m["slug"] == selection.get("model") for m in provider.get("models", [])):
        raise BridgeError("Model is absent from the destination's catalog.")
    if request["runtimeMode"] not in (
        "approval-required",
        "auto-accept-edits",
        "auto",
        "full-access",
    ):
        raise BridgeError("Unsupported runtime mode.")
    supported = provider.get("supportedRuntimeModes")
    if supported is not None and request["runtimeMode"] not in supported:
        raise BridgeError("The provider does not support the requested runtime mode.")
    if request["interactionMode"] not in ("default", "plan"):
        raise BridgeError("Unsupported interaction mode.")
    if request["workspaceStrategy"].get("type") not in (
        "root",
        "worktree",
        "existing_worktree",
    ):
        raise BridgeError("Unsupported workspace strategy.")
    if request["initialMessage"].get("attachments") != []:
        raise BridgeError("Local attachments cannot be forwarded by this helper.")
    if (
        not isinstance(request["initialMessage"].get("text"), str)
        or not request["title"].strip()
    ):
        raise BridgeError("Launch needs message text and a nonempty title.")


def launch(remote, request, thread_id):
    validate_launch(request, remote.projects(), remote.providers())
    if (
        remote.get(
            "api/orchestration/threads/" + quote(thread_id, safe=""), missing_ok=True
        )
        is not None
    ):
        raise BridgeError(
            "Thread ID already exists; use status instead of launching again."
        )
    command_id = str(
        uuid.uuid5(uuid.NAMESPACE_URL, remote.route["environmentId"] + ":" + thread_id)
    )
    emit(
        {
            "launchAttempt": True,
            "environmentId": remote.route["environmentId"],
            "threadId": thread_id,
            "commandId": command_id,
        }
    )
    result = remote.rpc(
        "orchestration.launchThread",
        {**request, "commandId": command_id, "threadId": thread_id},
    )
    return summarize(result["projection"], remote.route["environmentId"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("list", "inspect", "launch", "status"))
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path.home() / ".t3/userdata/connection-catalog.json",
    )
    parser.add_argument("--environment")
    parser.add_argument("--connection-id")
    parser.add_argument("--request-file", help="Launch JSON file; '-' reads stdin")
    parser.add_argument(
        "--thread-id", help="Existing thread for status; optional fixed ID for launch"
    )
    args = parser.parse_args()
    if args.command != "list" and not args.environment:
        parser.error("--environment is required")
    if args.command == "launch" and not args.request_file:
        parser.error("launch requires --request-file")
    if args.command == "status" and not args.thread_id:
        parser.error("status requires --thread-id")
    try:
        catalog = load_catalog(args.catalog)
        if args.command == "list":
            emit({"routes": routes(catalog)})
            return
        route, token = select_route(catalog, args.environment, args.connection_id)
        remote = Remote(route, token)
        remote.verify()
        if args.command == "inspect":
            emit(
                {
                    "environmentId": route["environmentId"],
                    "label": route["label"],
                    "projects": [
                        {k: p.get(k) for k in ("id", "title", "workspaceRoot")}
                        for p in remote.projects()
                    ],
                    "providers": provider_summary(remote.providers()),
                }
            )
        elif args.command == "status":
            emit(remote.status(args.thread_id))
        else:
            text = (
                sys.stdin.read()
                if args.request_file == "-"
                else Path(args.request_file).read_text()
            )
            emit(launch(remote, json.loads(text), args.thread_id or str(uuid.uuid4())))
    except BridgeError as error:
        emit({"error": str(error)})
        sys.exit(1)
    except Exception:  # noqa: BLE001 - credential-bearing library errors must never escape.
        # Third-party exceptions can contain headers or decrypted data.
        emit(
            {
                "error": "Unsupported catalog/API response or local dependency failure; raw details omitted."
            }
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
