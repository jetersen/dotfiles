# Endpoint discovery, transport, and compatibility

T3's webhook schedule, the sender's local timer, and network transport are separate. `webhookUrl` in MCP results is a Connect public URL. Its absence does not disable the installed app's authenticated webhook route.

## Prefer native discovery

Inspect the live tools and matching runtime before using a fallback. The native authenticated WebSocket API currently exposes `scheduledTasks.list`, whose task objects can contain `webhook: {path, url, hasSecret}`. `path` exists without Connect; `url` may be null. The installed MCP summary omits `path`. The app requires read permission to list tasks and `orchestration:operate` to expose webhook capabilities. Existing legitimate cookie/bearer sessions can authorize access; proof-bound credentials still need their proof. Tailscale identity headers do not grant these app permissions.

The list API currently has no task-ID filter and may return capabilities for other tasks. It is not automatically equivalent to selected-task-only credential access. Use an appropriate existing authenticated API resolver when it can respect the intended scope; never dump its result, enumerate unrelated secrets, export credentials, or weaken session requirements. The API exposes whether a signing key exists, not the key itself. An API-based resolver must obtain the same user-provided signing key from local credential storage, such as the existing OS keyring, without Varlock being required.

A resolver prints one JSON object with `url` and `signingKey` **only into the poller's captured pipe**. Both fields are secret. No URL token or signing key belongs in the watch config, command arguments, logs, chat, or a new plaintext file. The fallback below can reuse the credentials already stored by T3 for the exact newly created schedule, in memory only.

## Desktop app and standalone CLI

The webhook belongs to the environment hosting the thread/schedule, which may differ from the machine displaying the desktop app. Verify that environment and the schedule's project/thread binding before choosing a listener or database. The regular desktop app embeds the same server/webhook API; a separate CLI service is not required.

- Desktop app: its Tailscale HTTPS setting enables Serve for the embedded server. The app must remain running. Quitting/restarting it affects delivery and requires compatibility rediscovery.
- Standalone CLI: `t3 serve --tailscale-serve` manages the Serve HTTPS mapping; discover the installed flags and local port. In the reviewed runtime it removes the mapping on graceful shutdown, and setup failure logs a warning while the local server continues. Verify the advertised HTTPS endpoint after startup rather than treating a running service as proof of remote access.

Serve forwards to the local listener, so a wildcard bind or direct tailnet HTTP port is unnecessary for this workflow. Preserve any listener/firewall settings needed by other clients. Check HTTPS reachability and tailnet grants separately; inspect the user's ACL repository read-only before suggesting changes. Reuse existing HTTPS. Do not change app exposure, restart it, alter grants, or replace a Serve mapping without authorization. If remote HTTPS is unavailable, a timer on the T3 host can still check a remote job.

## Choose transport

- Same timer/T3 host: literal `127.0.0.1` or `::1` HTTP with an explicit discovered port. The job itself can be remote.
- Timer on another host: verified HTTPS. Set `httpsOrigin` to one exact lowercase origin, including a port if needed, without a trailing slash. For example, `{"httpsOrigin":"https://selected-host.example.ts.net"}`. Certificate/hostname verification remains enabled.

Tailscale Serve supplies private HTTPS without Connect or public ingress. Reachability does not discover webhook credentials or replace URL-token/HMAC checks. The saved bearer session used for remote thread launches cannot substitute for webhook credentials. Do not rely on forwarded identity headers to authenticate a T3 webhook.

Both modes reject userinfo, query strings and fragments, and disable proxies/redirects. HTTPS refuses other origins, including automatic loopback fallback. Remote HTTP configurations are rejected. Keep any existing watch on its pinned implementation until reconciliation; new watches use this contract. A resolver-only preflight does not establish server acceptance or thread dispatch; validate with a signed disposable endpoint from the actual sender when appropriate.

## Selected-task SQLite fallback

`scripts/local_endpoint.py` is version-sensitive compatibility code, not a public API. Use it only when native discovery/authentication cannot supply an appropriately scoped resolver. It reads **only the exact newly created task's** token, signing key, binding, and trigger fields through SQLite `mode=ro`. It never changes the app store. This is a deliberate narrow credential read; do not run it against historical or unrelated schedules.

Search matching source under `~/git` first, then verify it against the **running server's** executable/bundle. A package version label alone is insufficient. Discover the PID, loopback origin, and existing database path from narrowly selected non-secret process/configuration metadata. Do not dump environments, connection catalogs, or database contents. Confirm in the matching runtime:

- `/api/hooks/{encodeURIComponent(taskId)}/{token}` authenticates the selected enabled schedule and checks its configured HMAC-SHA256 over the raw request bytes.
- `scheduled_tasks` contains `task_id`, `webhook_token`, `webhook_secret`, `enabled`, `project_id`, `thread_id`, and `schedule_json` in the expected shapes.
- Positive admission is status 202 with `x-t3-hook-outcome: accepted|duplicate`, replay dedupe lasts seven days, and asynchronous dispatch may still fail after acceptance.
- The identified process owns the discovered listener/database. Any selected network route reaches that exact environment.

For T3 managed by an existing systemd user service, use its exact discovered `runtimeUnit`. At each credential-resolution attempt, the helper obtains the active unit's current `MainPID`, requires the same user, and verifies that process owns both the configured loopback listener and SQLite file. It checks process identity and ownership again before returning credentials. Temporary downtime fails that tick; later ticks discover the replacement process. No config rewrite or new event is needed after an ordinary restart. Normal upgrades are allowed while the selected database fields, task binding, signature/filter/dedupe settings and HTTP acknowledgement remain compatible. An actual contract mismatch fails the tick and needs diagnosis; a changed executable or desktop archive alone does not block delivery.

Example for a standalone server managed by a user service (discover all values):

```json
{
  "endpointTimeout": 10,
  "t3Compatibility": {
    "origin": "http://127.0.0.1:12345",
    "database": "/absolute/discovered/app.sqlite",
    "runtimeUnit": "discovered-t3.service"
  }
}
```

The unit's main process must be the server that owns the listener/database. Do not select a desktop launcher or wrapper whose child owns them. Discover the absolute `systemctl` path as in setup.md. The ownership check requires readable Linux `/proc` metadata for that process. If the server restarts during a check, the helper rejects that attempt and retries later with the same pending event. Active status-only ticks do not resolve credentials. This mode checks local listener ownership; verify any remote HTTPS proxy still reaches that exact environment separately.

For an unmanaged server or the regular desktop app, replace `runtimeUnit` with explicit `runtimePid` and `runtimeIdentity` instead:

```json
{
  "runtimePid": 1234,
  "runtimeIdentity": {"bootId": "discovered-boot-id", "startTicks": 123456}
}
```

These fields belong inside `t3Compatibility`. `runtime_identity(pid)` reads boot ID and process start ticks from Linux `/proc`; capture only that non-secret identity, never credential resolver output. This fixed-PID mode deliberately requires manual rediscovery after restart/PID reuse and does not independently revalidate listener/database ownership. Legacy `runtimeSha256` and `runtimeArtifacts` fields are ignored by this helper; they can be removed from new configurations.

During manual recovery, verify the exact listener/database binding and the selected webhook contract, then refresh only `runtimePid` and `runtimeIdentity`. Preserve the watch ID, schedule, pending event and acceptance receipt. An accepted event must not be rearmed by deleting its receipt; reconcile it and use a new watch for separately resumed work.

Set `endpointCommand` to `["/absolute/python3", "/absolute/skill/scripts/local_endpoint.py", "--config", "/absolute/watch/config.json"]`. The resolver requires the expected project/thread, enabled webhook, exact job/watch/terminal-event filters, `{{body.eventId}}` replay key, no coalescing, and the fixed signature descriptor in setup.md. Unsigned schedules fail closed. For a remote sender, the resolver must still run on the T3 host through an already authorized mechanism, or use native API discovery plus its own local key storage. It cannot read a remote SQLite store simply because the listener is reachable over Tailscale or HTTPS.

Validate with synthetic databases and disposable local HTTP/HTTPS endpoints first. If a real app contract test is necessary, use a new disposable schedule and a test thread within the requested validation scope. A nonmatching filter can prove rejection without dispatch; use the correct signature even for that probe. A full dispatch test creates an agent turn, so keep it within the existing authorization; no additional confirmation is needed when that test is already authorized. Disable the disposable schedule afterward. Never revive an old one-use webhook to test compatibility.
