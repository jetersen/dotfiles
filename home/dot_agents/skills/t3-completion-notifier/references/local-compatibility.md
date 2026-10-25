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

Record the inspected executable's SHA-256, boot ID, and process start ticks. `runtime_identity(pid)` in the helper reads the latter two from Linux `/proc`; capture only those non-secret fields, never call the credential resolver in visible output. These guards detect restart/PID reuse, including the same executable, at each credential-resolution attempt. Active status-only ticks do not resolve credentials. The helper does not independently revalidate listener/database ownership, so rediscover that relationship after a restart or routing change. If the same inspected executable/bundle and exact listener/database binding remain valid, refresh only `runtimePid` and `runtimeIdentity` in the existing watch config; keep its watch ID, schedule and pending/receipt state. A listener change alone does not require recreating the webhook or changing transport. For a regular Electron desktop app, include the exact loaded `resources/app.asar` in `runtimeArtifacts` as shown below. The helper hashes each declared artifact as well as the process executable; an executable hash alone does not cover embedded server code. Discover the loaded archive from the process/installation, not a newer desktop launcher on PATH.

Add to the watch config (illustrative paths/port/identity only):

```json
{
  "t3Compatibility": {
    "origin": "http://127.0.0.1:12345",
    "database": "/absolute/discovered/app.sqlite",
    "runtimePid": 1234,
    "runtimeSha256": "sha256-of-inspected-running-server-executable",
    "runtimeIdentity": {"bootId": "discovered-boot-id", "startTicks": 123456},
    "runtimeArtifacts": [{"path":"/absolute/loaded/resources/app.asar","sha256":"sha256-of-inspected-loaded-archive"}]
  }
}
```

Omit `runtimeArtifacts` only for a self-contained standalone executable whose inspected hash covers the server code.

Set `endpointCommand` to `["/absolute/python3", "/absolute/skill/scripts/local_endpoint.py", "--config", "/absolute/watch/config.json"]`. The resolver requires the expected project/thread, enabled webhook, exact job/watch/terminal-event filters, `{{body.eventId}}` replay key, no coalescing, and the fixed signature descriptor in setup.md. Unsigned schedules fail closed. For a remote sender, the resolver must still run on the T3 host through an already authorized mechanism, or use native API discovery plus its own local key storage. It cannot read a remote SQLite store simply because the listener is reachable over Tailscale or HTTPS.

Validate with synthetic databases and disposable local HTTP/HTTPS endpoints first. If a real app contract test is necessary, create a new disposable schedule bound to an intentionally disposable thread. A nonmatching filter can prove rejection without dispatch; use the correct signature even for that probe. A full dispatch test needs authorization for that test run. Disable the disposable schedule afterward. Never revive an old one-use webhook to test compatibility.
