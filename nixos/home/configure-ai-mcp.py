"""Reconcile shared MCP entries while preserving client-managed settings."""

import json
import os
from pathlib import Path
import sys
import tempfile

import tomlkit


def write_private(path, content):
    if path.exists() and path.read_text() == content:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


managed = {}
if len(sys.argv) > 1:
    managed["victorialogs"] = {"type": "http", "url": Path(sys.argv[1]).read_text().strip()}
home = Path.home()
codex = Path(os.environ.get("CODEX_HOME", home / ".codex")) / "config.toml"
settings = tomlkit.parse(codex.read_text()) if codex.exists() else tomlkit.document()
servers = settings.setdefault("mcp_servers", tomlkit.table())
for retired in ("rea", "codegraph"):
    servers.pop(retired, None)
if "victorialogs" not in managed:
    servers.pop("victorialogs", None)
for name, server in managed.items():
    entry = servers.setdefault(name, tomlkit.table())
    for key in (["command", "args", "cwd"] if "url" in server else ["url"]):
        entry.pop(key, None)
    entry.update({key: value for key, value in server.items() if key != "type"})
write_private(codex, tomlkit.dumps(settings))

claude = home / ".claude.json"
settings = json.loads(claude.read_text()) if claude.exists() else {}
servers = settings.setdefault("mcpServers", {})
for retired in ("rea", "codegraph"):
    servers.pop(retired, None)
if "victorialogs" not in managed:
    servers.pop("victorialogs", None)
for name, server in managed.items():
    entry = servers.setdefault(name, {})
    for key in (["command", "args", "cwd"] if "url" in server else ["url"]):
        entry.pop(key, None)
    entry.update(server)
write_private(claude, json.dumps(settings, indent=2) + "\n")
