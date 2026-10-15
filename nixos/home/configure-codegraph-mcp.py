"""Reconcile CodeGraph's MCP entry while preserving client-managed settings."""

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


command = sys.argv[1]
home = Path.home()
codex = Path(os.environ.get("CODEX_HOME", home / ".codex")) / "config.toml"
settings = tomlkit.parse(codex.read_text()) if codex.exists() else tomlkit.document()
servers = settings.setdefault("mcp_servers", tomlkit.table())
entry = servers.setdefault("codegraph", tomlkit.table())
entry["command"] = command
entry["args"] = ["serve", "--mcp"]
write_private(codex, tomlkit.dumps(settings))

claude = home / ".claude.json"
settings = json.loads(claude.read_text()) if claude.exists() else {}
entry = settings.setdefault("mcpServers", {}).setdefault("codegraph", {})
entry.update({"type": "stdio", "command": command, "args": ["serve", "--mcp"]})
write_private(claude, json.dumps(settings, indent=2) + "\n")
