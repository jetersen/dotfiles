# Endpoint setup

Resolve the hook URL on the T3 environment hosting the thread, using its live API or the helper below. Choose the endpoint:

- Local: literal `127.0.0.1` or `::1` HTTP with the discovered port.
- Tailscale HTTPS: set `httpsOrigin` to the exact lowercase origin without a trailing slash, for example `https://selected-host.example.ts.net`.

Reuse T3's Tailscale Serve endpoint, enabled through the desktop setting or CLI `--tailscale-serve`. Keep the app/server running. Both endpoints use the same webhook token.

## Supplied resolver

For a systemd user service, use `scripts/local_endpoint.py` on the T3 host. It reads credentials for the selected schedule from SQLite. Add the service name, loopback origin and database path to the watch config:

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

Set `endpointCommand` to `["/absolute/python3", "/absolute/skill/scripts/local_endpoint.py", "--config", "/absolute/watch/config.json"]` and supply the absolute `systemctl` path.
