# Endpoint discovery and SQLite fallback

The webhook belongs to the environment hosting the thread, which may differ from the machine displaying the desktop app. Discover that environment, listener and store before resolving credentials.

## Endpoint and credentials

Use supported live tools/API. MCP `webhookUrl` is a Connect public URL; its absence does not disable local hooks. The native authenticated `scheduledTasks.list` API can expose `webhook: {path, url, hasSecret}` without Connect. It needs read permission plus `orchestration:operate` for capabilities; proof-bound sessions retain their proof requirements. The list has no task-ID filter and can expose unrelated capabilities, so use it only through an appropriately scoped resolver. It does not return the signing key; obtain that from existing local credential storage. For the desktop app, use a scoped API resolver; its embedded server follows the app lifetime.

Transport is separate:

- Same host: literal `127.0.0.1` or `::1` HTTP with the discovered port. The job can still be remote.
- Remote timer: verified HTTPS with one exact lowercase `httpsOrigin`, no trailing slash, for example `https://selected-host.example.ts.net`.

T3 can manage private Tailscale Serve HTTPS through the desktop setting or CLI `--tailscale-serve`. The app/server must remain running. Serve forwards to loopback, so this notifier needs no wildcard listener or direct remote HTTP. The CLI removes its Serve mapping on graceful shutdown and only warns on setup failure; verify HTTPS reachability after startup. Reuse existing endpoints and preserve other clients' exposure settings.

The helper disables proxies/redirects and rejects userinfo, query strings, fragments, remote HTTP and origin changes. Tailnet reachability and identity headers do not replace webhook token/HMAC authentication. Saved remote-thread bearer credentials are not webhook credentials.

## Selected-task SQLite fallback

Use `scripts/local_endpoint.py` for a service-managed T3 server when supported discovery cannot supply the credentials within scope. It reads the exact newly created schedule using SQLite `mode=ro`, returning `url` and `signingKey` only to the poller's pipe. No tokens belong in config, argv, logs, chat or new plaintext files.

Check matching local source against the installed runtime at setup. The consumed contract is:

- `/api/hooks/{encoded-task-id}/{token}` with raw-body HMAC-SHA256.
- `scheduled_tasks`: `task_id`, `webhook_token`, `webhook_secret`, `enabled`, `project_id`, `thread_id`, `schedule_json`.
- `202` plus `x-t3-hook-outcome: accepted|duplicate`; seven-day replay retention. Admission precedes asynchronous dispatch.

The resolver checks enabled state, exact project/thread and job/watch/event filters, the fixed signature descriptor from setup.md, event-ID replay key and absence of coalescing. Schema or contract mismatches fail the tick; compatible app upgrades need no executable/archive hash pin.

For a systemd-managed server, add discovered values to the watch config:

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

Set `endpointCommand` to `["/absolute/python3", "/absolute/skill/scripts/local_endpoint.py", "--config", "/absolute/watch/config.json"]` and supply the absolute `systemctl` path as in setup.md. The unit's main process must own the listener/database. The helper discovers the current server process and verifies same-user, listener and database ownership before returning credentials. Downtime or a restart during resolution retries later with the same event. Remote HTTPS proxy identity remains a separate setup check.

A remote sender must run this resolver on the T3 host through an already authorized mechanism, or use an API resolver with local key storage; network access does not grant remote SQLite access. Validate with synthetic stores/endpoints first. Any live test belongs within existing authorization and uses disposable resources, never historical one-use hooks.
