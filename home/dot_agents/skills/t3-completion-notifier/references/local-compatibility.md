# Endpoint discovery and SQLite fallback

Resolve the webhook on the T3 environment hosting the thread.

## Endpoint and credentials

Use supported live tools/API. The authenticated `scheduledTasks.list` API exposes the hook path without Connect when authorized with read and `orchestration:operate` permissions. It does not return the signing key; resolve that from the webhook's local credential storage. For the desktop app, use an API resolver.

Choose the endpoint:

- Local: literal `127.0.0.1` or `::1` HTTP with the discovered port.
- Tailscale HTTPS: set `httpsOrigin` to the exact lowercase origin without a trailing slash, for example `https://selected-host.example.ts.net`.

Reuse T3's Tailscale Serve endpoint, enabled through the desktop setting or CLI `--tailscale-serve`. Keep the app/server running. Both endpoints use the same webhook token and HMAC key; the helper verifies HTTPS certificates and disables proxies/redirects.

## Selected-task SQLite fallback

Run `scripts/local_endpoint.py` on the T3 host when API discovery cannot supply the credentials. It reads only the selected schedule using SQLite `mode=ro`, returning `url` and `signingKey` to the poller's pipe.

Check matching local source against the installed runtime at setup. The consumed contract is:

- `/api/hooks/{encoded-task-id}/{token}` with raw-body HMAC-SHA256.
- `scheduled_tasks`: `task_id`, `webhook_token`, `webhook_secret`, `enabled`, `project_id`, `thread_id`, `schedule_json`.
- `202` plus `x-t3-hook-outcome: accepted|duplicate`; seven-day replay retention. Admission precedes asynchronous dispatch.

The resolver checks enabled state, project/thread binding, job/watch/event filters, signature configuration, event-ID replay key and absence of coalescing.

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

Set `endpointCommand` to `["/absolute/python3", "/absolute/skill/scripts/local_endpoint.py", "--config", "/absolute/watch/config.json"]` and supply the absolute `systemctl` path as in setup.md. The helper uses service discovery and checks that the current server owns the listener/database. Downtime or a restart during resolution retries later with the same event.
