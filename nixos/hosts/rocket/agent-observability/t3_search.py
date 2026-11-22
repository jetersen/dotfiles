"""Import T3 conversations through AgentsView's supported ChatGPT exchange format.

The source database is read-only. A cursor advances only after a successful import.
"""

import datetime
import io
import json
import os
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


def timestamp(value):
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def conversation(thread, messages, environment):
    mapping = {}
    previous = None
    link = f"t3-thread://v2/{environment}/{thread['id']}"
    for message in messages:
        if message["role"] not in ("user", "assistant") or message.get("streaming"):
            continue
        text = message.get("text", "")
        if not text.strip():
            continue
        key = message["id"]
        if not mapping:
            text = f"Original T3 thread: {link}\n\n{text}"
        mapping[key] = {
            "id": key,
            "parent": previous,
            "children": [],
            "message": {
                "id": key,
                "author": {"role": message["role"]},
                "create_time": timestamp(message["createdAt"]),
                "content": {"content_type": "text", "parts": [text]},
            },
        }
        if previous:
            mapping[previous]["children"].append(key)
        previous = key
    state = "marked settled" if thread.get("settledOverride") == "settled" else "review in T3"
    return {
        "id": "t3-" + thread["id"],
        "title": f"[T3: {state}] {thread['title']}",
        "create_time": timestamp(thread["createdAt"]),
        "update_time": timestamp(thread["updatedAt"]),
        "mapping": mapping,
        "current_node": previous,
    }


def post_import(batch, replace=()):
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zipped:
        zipped.writestr("conversations.json", json.dumps(batch))
    boundary = "agent-session-import"
    body = (
        (
            f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
            'filename="conversations.zip"\r\nContent-Type: application/zip\r\n\r\n'
        ).encode()
        + archive.getvalue()
        + f"\r\n--{boundary}--\r\n".encode()
    )
    query = urllib.parse.urlencode([("replace", sid) for sid in replace])
    request = urllib.request.Request(
        "http://127.0.0.1:8120/sessions/api/v1/import/chatgpt" + ("?" + query if query else ""),
        data=body,
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Origin": "http://127.0.0.1:8120",
        },
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        result = json.load(response)
    return result


def import_batch(batch, post=post_import):
    result = post(batch)
    errors = result.get("errors", 0)
    if not errors:
        return
    refusals = result.get("refusals", [])
    expected = {"chatgpt:" + item["id"]: item for item in batch if item["id"].startswith("t3-")}
    if len(refusals) != errors or len({r.get("session_id") for r in refusals}) != errors:
        raise RuntimeError("Unexpected import errors; cursor preserved")
    replacements = []
    for refusal in refusals:
        sid = refusal.get("session_id")
        if sid not in expected:
            raise RuntimeError("Import refusal does not match this T3 batch; cursor preserved")
        reason = refusal.get("reason")
        if reason in ("diverged", "shorter_export"):
            replacements.append(sid)
        elif reason != "trashed":
            raise RuntimeError("T3 conversation import failed; cursor preserved")
    # T3 is authoritative for its derived search copies. AgentsView's supported
    # replacement path retains the previous version in trash. Never resurrect
    # copies a user has explicitly trashed, or replace an unrelated session.
    if replacements:
        edited = [expected[sid] for sid in replacements]
        retried = post(edited, replace=replacements)
        if retried.get("errors", 0):
            raise RuntimeError("T3 conversation replacement failed; cursor preserved")


def main():
    for attempt in range(90):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8120/sessions/api/v1/stats", timeout=2):
                break
        except (urllib.error.URLError, TimeoutError):
            time.sleep(2)
    else:
        raise RuntimeError("AgentsView did not become ready")
    home = Path.home()
    source = Path(os.environ.get("T3CODE_HOME", home / ".t3")) / "userdata"
    data = Path(os.environ["AGENTSVIEW_DATA_DIR"])
    cursor_file = data / "t3-import-cursor"
    cursor = cursor_file.read_text().strip() if cursor_file.exists() else ""
    db = sqlite3.connect(f"file:{source / 'statev2.sqlite'}?mode=ro", uri=True, timeout=30)
    db.execute("PRAGMA query_only=ON")
    # Snapshot the upper bound so edits during import are caught on the next run.
    until = (
        datetime.datetime.now(datetime.UTC)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )
    rows = db.execute(
        """SELECT t.payload_json FROM orchestration_v2_projection_threads t
        WHERE t.deleted_at IS NULL AND (t.updated_at > ? OR t.thread_id IN
        (SELECT thread_id FROM orchestration_v2_projection_messages WHERE updated_at > ?))
        ORDER BY t.thread_id""",
        (cursor, cursor),
    ).fetchall()
    environment = (source / "environment-id").read_text().strip()
    exported = 0
    for offset in range(0, len(rows), 50):
        batch = []
        for (payload,) in rows[offset : offset + 50]:
            thread = json.loads(payload)
            messages = [
                json.loads(r[0])
                for r in db.execute(
                    "SELECT payload_json FROM orchestration_v2_projection_messages "
                    "WHERE thread_id = ? ORDER BY created_at, message_id",
                    (thread["id"],),
                )
            ]
            if any(message.get("streaming") for message in messages):
                continue
            item = conversation(thread, messages, environment)
            if item["mapping"]:
                batch.append(item)
        if batch:
            import_batch(batch)
            exported += len(batch)
    records = [
        json.loads(row[0])
        for row in db.execute(
            "SELECT payload_json FROM orchestration_v2_projection_threads WHERE deleted_at IS NULL"
        )
    ]
    metrics = {
        "agent_session_index_last_success_timestamp_seconds": time.time(),
        "agent_t3_threads_total": len(records),
        "agent_t3_threads_explicitly_settled": sum(
            item.get("settledOverride") == "settled" for item in records
        ),
    }
    now = str(time.time_ns())
    payload = {
        "resourceMetrics": [
            {
                "resource": {
                    "attributes": [
                        {"key": "service.name", "value": {"stringValue": "agent-session-indexer"}},
                        {"key": "host.name", "value": {"stringValue": "rocket"}},
                    ]
                },
                "scopeMetrics": [
                    {
                        "metrics": [
                            {
                                "name": name,
                                "gauge": {"dataPoints": [{"asDouble": value, "timeUnixNano": now}]},
                            }
                            for name, value in metrics.items()
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
    temporary = cursor_file.with_suffix(".tmp")
    temporary.write_text(until)
    temporary.replace(cursor_file)
    print(f"Imported {exported} T3 conversations")


if __name__ == "__main__":
    main()
