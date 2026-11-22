"""Consistent T3 snapshots and encrypted agent transcript backups to Kopia S3."""

import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import time
import urllib.request
from contextlib import closing
from pathlib import Path


def snapshot_database(source, target):
    partial = target.with_suffix(".partial")
    # Only this service's disposable staging file is replaced.
    for suffix in ["", "-wal", "-shm", "-journal"]:
        Path(str(partial) + suffix).unlink(missing_ok=True)
    with closing(sqlite3.connect(f"file:{source}?mode=ro", uri=True)) as src:
        src.execute("BEGIN")
        # BEGIN is deferred. Establish the read snapshot before backup starts so
        # concurrent source writes do not repeatedly restart the online backup.
        src.execute("SELECT count(*) FROM sqlite_schema").fetchone()
        with closing(sqlite3.connect(partial)) as dest:
            src.backup(dest, pages=1024, sleep=0.05)
            if dest.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                raise RuntimeError("T3 backup integrity check failed")
            dest.execute("PRAGMA journal_mode=DELETE").fetchone()
    partial.replace(target)


def write_snapshot_manifest(database):
    digest = hashlib.sha256()
    with database.open("rb") as source:
        while chunk := source.read(4 * 1024 * 1024):
            digest.update(chunk)
    tables = [
        "projection_projects",
        "orchestration_v2_projection_threads",
        "orchestration_v2_projection_messages",
    ]
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
        counts = {
            table: db.execute("SELECT count(*) FROM " + table).fetchone()[0] for table in tables
        }
    manifest = {"database": database.name, "sha256": digest.hexdigest(), "counts": counts}
    target = database.parent / "snapshot-manifest.json"
    temporary = target.with_suffix(".partial")
    temporary.write_text(json.dumps(manifest) + "\n")
    temporary.replace(target)
    return manifest


def main():
    os.umask(0o077)
    home = Path.home()
    root = Path("/media/games/agent-observability/backup")
    root.mkdir(parents=True, exist_ok=True)
    os.environ.update(
        KOPIA_PASSWORD=os.environ["BACKUP_KOPIA_PASSWORD"],
        AWS_ACCESS_KEY_ID=os.environ["BACKUP_S3_ACCESS_KEY_ID"],
        AWS_SECRET_ACCESS_KEY=os.environ["BACKUP_S3_SECRET_ACCESS_KEY"],
        KOPIA_CONFIG_PATH=str(root / "repository.config"),
        KOPIA_CACHE_DIRECTORY=str(root / "cache"),
        KOPIA_PERSIST_CREDENTIALS_ON_CONNECT="false",
    )
    binary = Path(os.environ["KOPIA_BIN"])

    def run(*args, capture=False):
        result = subprocess.run(
            [str(binary), "--disable-file-logging", *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.stdout if capture else None

    # An isolated prefix prevents retention or maintenance affecting other apps.
    if not (root / "repository.config").exists():
        run(
            "repository",
            "connect",
            "s3",
            "--bucket=" + os.environ["BACKUP_S3_BUCKET"],
            "--endpoint=" + os.environ["BACKUP_S3_ENDPOINT"],
            "--region=" + os.environ["BACKUP_S3_REGION"],
            "--prefix=agents/rocket/",
            "--no-persist-credentials",
        )
    stage = root / "t3"
    stage.mkdir(exist_ok=True)
    source = home / ".t3/userdata"
    snapshot_database(source / "statev2.sqlite", stage / "statev2.sqlite")
    write_snapshot_manifest(stage / "statev2.sqlite")
    for name in ["environment-id", "settings.json", "keybindings.json"]:
        if (source / name).exists():
            shutil.copy2(source / name, stage / name)
    paths = [
        stage,
        source / "attachments",
        source / "artifacts",
        source / "browser-artifacts",
        home / ".codex/sessions",
        home / ".codex/archived_sessions",
        home / ".claude/projects",
    ]
    for path in paths:
        if path.exists():
            run("snapshot", "create", str(path))
    run("maintenance", "run", "--full")
    (root / "last-success").write_text(str(int(time.time())))
    payload = {
        "resourceMetrics": [
            {
                "resource": {
                    "attributes": [
                        {"key": "service.name", "value": {"stringValue": "agent-backup"}},
                        {"key": "host.name", "value": {"stringValue": "rocket"}},
                    ]
                },
                "scopeMetrics": [
                    {
                        "metrics": [
                            {
                                "name": "agent_backup_last_success_timestamp_seconds",
                                "gauge": {
                                    "dataPoints": [
                                        {
                                            "asDouble": time.time(),
                                            "timeUnixNano": str(time.time_ns()),
                                        }
                                    ]
                                },
                            }
                        ]
                    }
                ],
            }
        ]
    }
    request = urllib.request.Request(
        "http://192.168.1.23:4318/v1/metrics",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=10):
        pass
    print("Encrypted agent snapshots completed; T3 SQLite quick_check passed")


if __name__ == "__main__":
    main()
