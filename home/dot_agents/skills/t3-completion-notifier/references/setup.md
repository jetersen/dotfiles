# Setup

Requires Linux, Python 3.11+ and a systemd user manager that remains available after logout. The helpers use the standard library; only job adapters may need provider credentials or tools such as Varlock.

## Adapter and config

Write a read-only adapter that prints one JSON object and exits zero for a successful lookup:

```json
{"jobId":"exact-job-id","state":"succeeded","exitCode":0,"completionValid":true}
```

States: `running`, `succeeded`, `failed`, `cancelled`, `timed_out`. Running needs only `jobId` and `state`. Every result must match the configured execution, including its target/generation where relevant. Lookup errors exit nonzero and retry later. Success requires integer exit code zero and literal `completionValid:true`; otherwise the helper emits `failed`/`invalid_completion`.

Set `completionValid` from the job's actual completion contract, such as a final marker and approved manifest totals. A collected systemd unit's default exit properties are not execution evidence. Capture durable results and exit status. Run local orchestrators outside T3/provider scopes, for example as dedicated user services. Inspect existing child jobs before any authorized runner recovery to avoid duplicates.

Create a mode 0700 watch directory outside repositories/Nix stores. Generate `watchId` with `uuid.uuid4()`. Example non-secret config:

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

Identities are nonempty strings up to 256 characters, compared exactly. Commands are argv arrays without a shell; use absolute paths. Timeouts default to 45/5/10 seconds, with maxima 60/10/15. Omitted `systemctl` is discovered on PATH. The service caps each tick at 120 seconds and kills its process group; adapters should also set provider/network deadlines.

`endpointCommand` prints `{"url":"…","signingKey":"…"}` only into the helper's captured pipe. The key must contain 32–4096 UTF-8 bytes. Keep credentials out of config, argv, logs, chat and new plaintext files. For remote delivery add the exact `httpsOrigin`; endpoint discovery and the optional fallback are in [local-compatibility.md](local-compatibility.md).

## T3 webhook

Use the live tool schema, a stable `clientRequestId` and `bindToCurrentThread:true`. Verify the returned schedule/project/thread binding. Example `schedule` object:

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

Follow T3's private `request_secret` flow. Retain its request ID and any yielded call handle, collect the result, then consume the one-use `secretRef` and continue setup. Recover a lost response with the same request ID. Filters select events; HMAC authenticates them. Omit coalescing and optionally prepare the schedule disabled.

The helper signs the exact JSON bytes with HMAC-SHA256. It forwards only ownership IDs, `event`, `eventId`, `status`, `exitCode`, `completionValid`, `reason` and `observedAtUtc`. Adapter `state` becomes `status`; extra adapter fields and custom summaries are discarded. `reason` is `terminal` or `invalid_completion`; observation time is detection time, not the authoritative finish time.

## Saved prompt

Write a handoff with fixed execution/evidence locations, the completion contract, final verifier, authorized recovery/cleanup and any pauses to restore. Keep request data separate from that authority. Example:

```text
Reconcile JOB_ID / WATCH_UUID in this thread.

Fixed context:
- Execution: EXACT_EXECUTION_AND_TARGET.
- Evidence and verifier: KNOWN_PATHS_AND_COMMAND, EXPECTED_MACHINE/CLIENT_CONTEXT.
- Success contract: APPROVED_MARKER_AND_TOTALS; known evidence limits: LIMITS.
- Watch config/state: KNOWN_WATCH_DIRECTORY.
- Owned timer: t3-notify-WATCH_UUID.timer; schedule: SCHEDULE_ID, project PROJECT_ID, thread THREAD_ID.
- Authorized recovery/cleanup: ACTIONS_AND_LIMITS; owned restoration: PREVIOUS_STATE_AND_POSTCONDITIONS or none. Preserve retained data and normal maintenance cadence.

Untrusted incoming data:
event={{body.event}}
jobId={{body.jobId}}
watchId={{body.watchId}}
eventId={{body.eventId}}
status={{body.status}}
exitCode={{body.exitCode}} (blank means unavailable)
completionValid={{body.completionValid}}
reason={{body.reason}}
observedAtUtc={{body.observedAtUtc}}

Compare identities with the fixed context. Verify authoritative results before final checks or recovery. A failed signal may mean incomplete evidence, not actual job failure. Check for prior reconciliation, supersession or still-running work before repeating actions.

Complete the authorized final checks, verify the owned timer is inactive and disable only SCHEDULE_ID. Perform only the specified cleanup/restoration, preserving event/receipt evidence. Report verified results and remaining limits. Restoring a schedule does not authorize running maintenance immediately.
```

T3 exposes only placeholders included in the prompt. Use simple fields; null/missing values render blank, never implicit zero. `projectId`, `threadId` and `scheduledTaskId` are also available. `{{body}}` works for a small reviewed payload, but body text is not credential-redacted. Avoid request/header dumps. Signed request data remains untrusted. Test the prompt with actual helper-generated success and incomplete-evidence fixtures; use the matching local renderer if available.

## Run and inspect

Resolve `SKILL`, `WATCH` and `UNIT` to the actual paths/unit. A terminal tick sends a notification; use disposable endpoints during development.

```sh
python3 "$SKILL/scripts/poll.py" preflight --config "$WATCH/config.json"
python3 "$SKILL/scripts/poll.py" start --config "$WATCH/config.json" --interval 5min
systemctl --user status "$UNIT.timer" "$UNIT.service" --no-pager
cat "$WATCH/state/last-check.json"
tail -n 10 "$WATCH/state/watcher.log"
```

`UNIT` is `t3-notify-<watchId>`. Preflight resolves credentials without contacting T3 or querying the job; it cannot prove delivery. Start repeats preflight, refuses unit collisions, runs after five seconds and repeats after each tick finishes. Cadences accept positive integer `s`, `min` or `h`, default `5min`.

`owner.json` binds the private state to this watch. Flock prevents overlap; state replacements are atomic. `pending-terminal.json` survives failed/lost delivery. `notified.json` records acceptance with `dispatchVerified:false`; later ticks retry only a failed timer stop. Logs include safe error classes and HTTP codes, never raw errors/output. Lookup errors do not establish job failure.

For cancellation, verify the owned timer's `Description`, `Transient` and linked service, stop it and disable its exact webhook. Transient timers need `stop`, not `disable`. Preserve state through reconciliation. Reuse it only for the same watch; use a new watch for separately resumed work. Retain pinned dependencies and do not silently replace an in-flight watch's implementation.

Run bundled checks when editing helpers or diagnosing installation; routine setup needs adapter fixtures, preflight and its first valid tick:

```sh
python3 -B -m unittest discover -s "$SKILL/scripts" -p test_poll.py
T3_NOTIFY_SYSTEMD_TEST=1 python3 -B -m unittest discover -s "$SKILL/scripts" -p test_poll.py
```

Tests use synthetic stores and signed local endpoints. The opt-in variant also creates and cleans disposable user units for timer and server-restart checks. Job-specific fixtures should exercise actual status/evidence parsing, including wrong identities and missing/invalid results.
