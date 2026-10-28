# Adapter, configuration, and local timer

Requires Linux, Python 3.11+, and an existing systemd user manager. Check whether the user manager survives logout; discover its bus normally if needed. Do not enable lingering or change login policy silently. The helper itself needs no third-party Python packages or Varlock. OpenSSL is used only by the disposable TLS tests.

## Job independence

The timer and the job's orchestrator must both survive the T3/provider session ending. For a remote job, verify that its authoritative controller runs independently. For a local orchestrator, inspect its ancestry and cgroup and verify a separate owned user service rather than relying on an agent terminal, `nohup`, `disown` or a lock. A process can be outside the T3 server's cgroup yet still belong to a provider scope that T3 cancels.

Use read-only checks against the exact discovered runner, for example:

```sh
ps -o pid,ppid,sid,pgid,comm -p "$JOB_PID"
cat "/proc/$JOB_PID/cgroup"
systemctl --user show "$JOB_UNIT" -p MainPID -p ControlGroup -p KillMode -p RemainAfterExit
```

For an already-running job, use its authorized checkpoint/recovery policy to establish an independent orchestrator if needed; inspect current child jobs first and avoid duplicate submissions. The notifier does not move, resume or restart the job. Capture durable exit/result evidence independently of transient unit collection. If an interrupted orchestrator leaves remote work running, the receiving agent must reconcile it before recovery.

## Status adapter

Write a job-specific, read-only executable that prints exactly one JSON object and exits zero for a completed status lookup:

```json
{"jobId":"exact-job-id","state":"succeeded","exitCode":0,"completionValid":true}
```

`state` is one of `running`, `succeeded`, `failed`, `cancelled`, `timed_out`. `running` needs only `jobId` and `state`. All states must refer to the exact configured identity, including active results. Return nonzero for a status lookup failure, not for an observed job failure. Unknown states and invalid JSON are lookup errors that retry later. A terminal `succeeded` without integer exit code zero and literal `completionValid:true` becomes `failed` with reason `invalid_completion`.

A collected transient systemd unit may lose its exit properties; `ExecMainStatus=0` from a missing/reset unit is not execution evidence. Capture durable completion/exit evidence when starting a job when possible. For an already-running job with unavailable final status, signal failed/incomplete validation and let the receiving agent reconcile; do not restart it to obtain evidence.

The adapter must validate the job's actual completion contract before emitting `completionValid:true`. For example, compare the authoritative output manifest to approved totals and verify its final marker; do not infer success from process absence or a progress message. Configure provider CLI profile, region, JSON output, and connect/read deadlines explicitly when applicable. Never return credentials, signed URLs, raw stdout/stderr, or arbitrary summaries. The poller forwards only its allowlisted identities, state, exit code, validation flag, reason, timestamp, and stable event ID. Keep detailed evidence in the authoritative job artifacts.

`adapterCommand` and `endpointCommand` are argv arrays, executed without a shell. Use absolute executable and script paths, no tokens in arguments. A resolver prints JSON containing `url` and `signingKey` **only into the poller's captured pipe**. The helper requires a signing key of 32–4096 UTF-8 bytes and adds `x-t3-notify-signature: sha256=<hex HMAC-SHA256>` over the exact POST bytes. Its output must not be displayed by an agent or a terminal probe. The helper caps stdout, discards stderr, bounds command wall time, and kills subprocess groups. Configure SDK/CLI network deadlines inside adapters too. The service has a 120 second hard runtime ceiling, including HTTP parsing; the per-request socket timeout alone is not a total deadline against a slow trickle of headers.

## Per-watch config

Create a mode 0700 directory outside repositories and the Nix store; use umask 077. Generate `watchId` with `uuid.uuid4()`. Replace example paths and IDs with discovered values, including Python and systemctl paths on NixOS. The config contains no capability URL, token or signing key:

```json
{
  "watchId": "8c3605f1-b44e-49c9-942c-c6c35d7b479a",
  "jobId": "exact-job-id",
  "scheduledTaskId": "returned-schedule-id",
  "projectId": "returned-project-id",
  "threadId": "returned-bound-thread-id",
  "stateDirectory": "/absolute/watch/state",
  "adapterCommand": ["/absolute/python3", "/absolute/watch/status.py"],
  "endpointCommand": ["/absolute/python3", "/absolute/watch/resolve_endpoint.py"],
  "systemctl": "/absolute/systemctl",
  "adapterTimeout": 45,
  "endpointTimeout": 5,
  "httpTimeout": 10
}
```

The job ID must encode every dimension that distinguishes an execution (for example command ID plus target ID); the adapter verifies those dimensions against provider results. Identities must be non-secret, nonempty strings of at most 256 characters; spaces, punctuation and Unicode are preserved and compared exactly. Do not change identity fields in an existing state directory. Use a new watch for a new job/schedule. Omitted timeouts default to 45/5/10 seconds; maxima are 60/10/15. Omitted `systemctl` is discovered on PATH.

For remote delivery, set the exact `httpsOrigin` described in [local-compatibility.md](local-compatibility.md); omit it for loopback. The same document covers both the desktop app and CLI, including service discovery and manual PID mode.

Write its saved prompt using [webhook-message.md](webhook-message.md), which maps the actual event fields and provides a handoff template. The T3 schedule argument has this shape. Provision the signing key through T3's current `request_secret` flow, then substitute its returned `secretRef` and the job/watch values before calling the live tool:

```json
{
  "type": "webhook",
  "signature": {"header":"x-t3-notify-signature","encoding":"hex","prefix":"sha256=","secretRef":"returned-secret-reference"},
  "filters": [
    {"path":"body.jobId","op":"equals","value":"exact-job-id"},
    {"path":"body.watchId","op":"equals","value":"8c3605f1-b44e-49c9-942c-c6c35d7b479a"},
    {"path":"body.event","op":"equals","value":"job_terminal"}
  ],
  "dedupe": {"replayKey":"{{body.eventId}}"}
}
```

Use `enabled:false` during preparation if useful, then enable the exact new task before local delivery testing. Bind to this thread explicitly. Omit coalescing for a one-use event. Signatures are required by this helper. Filters select the intended event; they do not authenticate the sender. Replay dedupe limits repeated dispatch.

Private entry is T3's current provisioning workflow, not a cryptographic requirement for a user-chosen or externally issued key. Retain the secret request's `clientRequestId` and any pending call handle. If the call yields while other preparation continues, resume that same call to collect its result before reporting that user input is still missing. Recover a lost response with the same `clientRequestId` rather than opening another card. When the result is saved, consume its one-use `secretRef` and continue through activation and first-tick verification. Keep the raw key out of chat, command output and configuration. The SQLite fallback obtains the selected schedule's existing key in memory; native API resolvers need that same signing key in existing local credential storage. No Varlock installation is required.

## Start and inspect

Resolve real paths into the following commands; `SKILL`, `WATCH`, and `UNIT` below are task-specific shell variables, not literal paths. Review `poll.py tick --help` if needed. A manual active tick is safe after adapter validation and before starting the timer; a terminal tick sends the notification, so use disposable endpoints during development.

```sh
python3 "$SKILL/scripts/poll.py" preflight --config "$WATCH/config.json"
python3 "$SKILL/scripts/poll.py" start --config "$WATCH/config.json" --interval 5min
systemctl --user status "$UNIT.timer" "$UNIT.service" --no-pager
systemctl --user show "$UNIT.service" -p RuntimeMaxUSec -p TimeoutStopUSec -p KillMode
cat "$WATCH/state/last-check.json"
tail -n 10 "$WATCH/state/watcher.log"
```

`UNIT` is `t3-notify-<watchId>`. `preflight` checks resolver output, credentials, runtime guards and selected origin without contacting T3, querying the job, or printing credentials. It does not prove reachability, HMAC acceptance, filters or thread dispatch on the server. `start` repeats this check, creates only that transient timer/service, refuses collisions, starts after five seconds, and repeats the interval after each service finishes. There is no shell polling loop and no recurring LLM turn. Cadences accept positive integer `s`, `min`, or `h` (default `5min`). Keep the config, adapter, resolver, helper and interpreter paths available for the watch's lifetime. Nix store paths in transient units are not GC roots: retain the owning generations or explicit roots for these dependencies until completion. New skill versions do not migrate running watches; keep their pinned implementation/config until reconciliation, then adopt the current contract for a new watch. A failed service still gets a future timer tick. The helper refuses to start a watch already carrying a receipt.

Log events are JSONL: `job_running`, `terminal_detected`, `webhook_accepted`, `poll_failed_retry_next_tick`. A locked overlapping tick exits quietly. Inspect exception types, HTTP status codes and authoritative job status when diagnosing errors. `AdapterCommandError` identifies the job-status command; `EndpointCommandError` identifies credential resolution. Do not enable transport tracing or print exception messages. Persistent polling errors do not establish that the job failed.

For intentional cancellation of notification, verify the unit's `Description`, `Transient`, and timer `Unit` properties against this watch, stop that exact timer, and disable its exact T3 schedule with `update_scheduled_task`. Transient timers need `stop`, not `disable`. Verify timer inactivity and service completion before cleanup. Do not stop the underlying job. On completion, preserve pending/receipt evidence until the receiving thread has reconciled the result. `notified.json` is an acceptance receipt with `dispatchVerified:false`, not proof that a turn started. If no turn appears, inspect the selected schedule's delivery history and bound thread timeline through supported authenticated tools/API, correlate the event ID, and verify job state before any recovery send. Do not reset the receipt automatically.

## Checks

Run the bundled helper checks when changing the helpers or diagnosing an installation. Routine setup uses the job-specific adapter fixtures, credential preflight and first live tick; it does not require rerunning the unchanged helper suite for every watch.

```sh
python3 -B -m unittest discover -s "$SKILL/scripts" -p test_poll.py
T3_NOTIFY_SYSTEMD_TEST=1 python3 -B -m unittest discover -s "$SKILL/scripts" -p test_poll.py
```

The first uses temporary status files, a synthetic read-only SQLite store, and disposable signed loopback HTTP/HTTPS endpoints. It checks certificate/hostname verification, remote HTTP rejection, proxy/redirect refusal, and identical-event retries across compatible server restarts and upgrades. Service-mode resolver fixtures use real child processes, loopback listeners and synthetic SQLite files to check ownership and rejection boundaries. The second additionally checks a quiet active tick, terminal delivery retry and timer stop with a unique transient timer. It also restarts a separate disposable server service and delivers its preserved pending event. Both tests clean their exact units and never call T3 or a production provider. Run on the intended timer host. Job-specific fixtures should exercise the adapter's status and evidence parsing, including wrong execution identities and missing or invalid completion evidence, before installation.
