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


policy = json.loads(sys.argv[1])
managed = {
    name: {"type": server["type"], "url": Path(server["urlFile"]).read_text().strip()}
    for name, server in policy["servers"].items()
}


def reconcile(servers, new_table, *, include_type):
    for name in policy["remove"]:
        servers.pop(name, None)
    for name, server in managed.items():
        entry = servers.setdefault(name, new_table())
        for key in ("command", "args", "cwd"):
            entry.pop(key, None)
        entry.update({key: value for key, value in server.items() if include_type or key != "type"})


home = Path.home()
codex = Path(os.environ.get("CODEX_HOME", home / ".codex")) / "config.toml"
settings = tomlkit.parse(codex.read_text()) if codex.exists() else tomlkit.document()
reconcile(settings.setdefault("mcp_servers", tomlkit.table()), tomlkit.table, include_type=False)
write_private(codex, tomlkit.dumps(settings))

claude = home / ".claude.json"
settings = json.loads(claude.read_text()) if claude.exists() else {}
reconcile(settings.setdefault("mcpServers", {}), dict, include_type=True)
write_private(claude, json.dumps(settings, indent=2) + "\n")
