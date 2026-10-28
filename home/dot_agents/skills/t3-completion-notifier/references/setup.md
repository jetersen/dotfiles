# Setup

Requires Linux, Python 3.11+ and a systemd user manager available after logout.

## Adapter and config

A read-only adapter prints one JSON object and exits zero for a successful lookup:

```json
{"jobId":"exact-job-id","state":"succeeded","exitCode":0,"completionValid":true}
```

States: `running`, `succeeded`, `failed`, `cancelled`, `timed_out`. Running needs only `jobId` and `state`. Match the exact execution and target; exit nonzero for lookup failures. Report success only with exit code zero and `completionValid:true`, based on the job's authoritative results.

Create a mode 0700 watch directory outside repositories/Nix stores. Generate `watchId` with `uuid.uuid4()`; retain the directory and ID when continuing the same watch. Use a fresh watch for separately resumed work. Example config:

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
  "systemctl": "/absolute/systemctl"
}
```

Commands are argv arrays with absolute paths. The resolver prints `{"url":"…"}` into the helper's captured pipe; the URL contains the hook token, so keep it out of config, argv and logs. See [endpoint.md](endpoint.md) for endpoint setup and the supplied resolver.

## Webhook and prompt

Use the live T3 schema, a stable `clientRequestId` and `bindToCurrentThread:true`. Omit `signature` to use T3's generated webhook URL token without a secret-card request. Verify the returned schedule/project/thread binding. Do not configure coalescing.

Example `schedule` object:

```json
{
  "type": "webhook",
  "filters": [
    {"path":"body.jobId","op":"equals","value":"exact-job-id"},
    {"path":"body.watchId","op":"equals","value":"8c3605f1-b44e-49c9-942c-c6c35d7b479a"},
    {"path":"body.event","op":"equals","value":"job_terminal"}
  ],
  "dedupe": {"replayKey":"{{body.eventId}}"}
}
```

For optional HMAC signing, collect a `request_secret` result and set `signature` with its `secretRef`, header `x-t3-notify-signature`, encoding `hex` and prefix `sha256=`. Include `signingKey` in the resolver output.

Tailor the handoff to the job:

```text
Reconcile JOB_ID / WATCH_UUID: EXECUTION_AND_TARGET on HOST.
Evidence and success criterion: PATHS_OR_VERIFIER, REQUIRED_RESULTS.
Watch config/state: WATCH_DIRECTORY; webhook: SCHEDULE_ID.
Authorized final actions (optional): CHECKS_AND_CLEANUP.

Completion signal:
jobId={{body.jobId}}
watchId={{body.watchId}}
eventId={{body.eventId}}
status={{body.status}}
exitCode={{body.exitCode}} (blank means unavailable)
completionValid={{body.completionValid}}
reason={{body.reason}}
observedAtUtc={{body.observedAtUtc}}

Verify identities and authoritative job results. Complete the authorized final actions, verify t3-notify-WATCH_UUID.timer is inactive and disable SCHEDULE_ID. Preserve event/receipt evidence and report verified results.
```

## Run

Resolve `SKILL`, `WATCH` and `UNIT=t3-notify-<watchId>`:

```sh
python3 "$SKILL/scripts/poll.py" start --config "$WATCH/config.json" --interval 5min
systemctl --user status "$UNIT.timer" "$UNIT.service" --no-pager
tail -n 10 "$WATCH/state/watcher.log"
```

To cancel notification, stop its owned timer and disable its webhook. Transient timers use `stop`.
