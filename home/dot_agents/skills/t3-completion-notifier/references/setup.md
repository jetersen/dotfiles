# Setup

Requires Linux, Python 3.11+ and a systemd user manager available after logout. The helpers use the standard library. Run local job orchestrators independently of T3/provider scopes and retain durable exit/results evidence.

## Adapter and config

A read-only adapter prints one JSON object and exits zero for a successful lookup:

```json
{"jobId":"exact-job-id","state":"succeeded","exitCode":0,"completionValid":true}
```

States: `running`, `succeeded`, `failed`, `cancelled`, `timed_out`. Running needs only `jobId` and `state`. Match the exact execution and target. Lookup failures exit nonzero. Success requires integer exit code zero and literal `completionValid:true`, validated against the job's completion contract; otherwise it becomes `failed`/`invalid_completion`. Missing processes or collected units' default exit properties are not completion evidence.

Create a mode 0700 watch directory outside repositories/Nix stores. Generate `watchId` with `uuid.uuid4()`. Example config:

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

Identities are nonempty strings up to 256 characters. Commands are argv arrays with absolute paths. Timeouts default to 45/5/10 seconds, with maxima 60/10/15; each service tick is capped at 120 seconds. Omitted `systemctl` uses PATH.

The resolver prints `{"url":"…","signingKey":"…"}` into the helper's captured pipe. The key is 32–4096 UTF-8 bytes; credentials stay out of config, argv and logs. For endpoint discovery, `httpsOrigin` and the optional SQLite resolver, read [local-compatibility.md](local-compatibility.md).

## Webhook and prompt

Use the live T3 schema, a stable `clientRequestId` and `bindToCurrentThread:true`. Obtain and collect the private `request_secret` result, then consume its one-use `secretRef`. Reuse the request ID to recover a lost response. Verify the returned schedule/project/thread binding.

Example `schedule` object:

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

The helper signs exact JSON bytes with HMAC-SHA256 using the webhook's configured key; T3 verifies the signature before admitting the request. Adapter `state` becomes event `status`; extra adapter fields are discarded. Ownership IDs and the fields below are forwarded. `reason` is `terminal` or `invalid_completion`; `observedAtUtc` is detection time.

Tailor this handoff with fixed evidence, verification and action scope:

```text
Reconcile JOB_ID / WATCH_UUID in this thread.
Execution/target: EXACT_EXECUTION_AND_TARGET.
Evidence/verifier: KNOWN_PATHS_AND_COMMAND, MACHINE/CLIENT_CONTEXT.
Success contract and evidence limits: APPROVED_MARKER_AND_TOTALS, LIMITS.
Watch config/state: WATCH_DIRECTORY; timer: t3-notify-WATCH_UUID.timer.
Webhook: SCHEDULE_ID, project PROJECT_ID, thread THREAD_ID.
Final checks and authorized cleanup/restoration: ACTIONS, LIMITS, PREVIOUS_STATE_AND_POSTCONDITIONS.

Completion signal:
event={{body.event}}
jobId={{body.jobId}}
watchId={{body.watchId}}
eventId={{body.eventId}}
status={{body.status}}
exitCode={{body.exitCode}} (blank means unavailable)
completionValid={{body.completionValid}}
reason={{body.reason}}
observedAtUtc={{body.observedAtUtc}}

Verify identities and authoritative results, accounting for incomplete evidence, prior reconciliation and still-running work. Complete the specified final checks, verify the owned timer is inactive, disable SCHEDULE_ID and perform the authorized cleanup/restoration. Preserve event/receipt evidence and report verified results and remaining limits.
```

T3 exposes only named placeholders; null/missing values render blank. `{{body}}` includes the full unredacted payload. Check the prompt against helper-generated success and incomplete-evidence fixtures.

## Run

Resolve `SKILL`, `WATCH` and `UNIT=t3-notify-<watchId>`:

```sh
python3 "$SKILL/scripts/poll.py" preflight --config "$WATCH/config.json"
python3 "$SKILL/scripts/poll.py" start --config "$WATCH/config.json" --interval 5min
systemctl --user status "$UNIT.timer" "$UNIT.service" --no-pager
tail -n 10 "$WATCH/state/watcher.log"
```

Preflight does not contact T3 or query the job. Start repeats preflight, refuses collisions, runs after five seconds and repeats after each tick finishes. Cadences accept positive integer `s`, `min` or `h`, default `5min`. A terminal tick sends a notification.

To cancel notification, verify and stop its owned timer and disable its webhook. Transient timers use `stop`. Preserve state through reconciliation; use a fresh watch for separately resumed work.

When editing helpers or diagnosing installation:

```sh
python3 -B -m unittest discover -s "$SKILL/scripts" -p test_poll.py
```

Set `T3_NOTIFY_SYSTEMD_TEST=1` to include disposable user-unit tests. Routine setup needs job-specific adapter fixtures, preflight and its first valid tick.
