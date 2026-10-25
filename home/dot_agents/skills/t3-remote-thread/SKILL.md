---
name: t3-remote-thread
description: Launch a requested top-level T3 Code thread on another configured environment when native MCP tools cannot select that environment. Temporary fallback for Linux desktops with saved HTTPS bearer connections.
---

# Remote T3 threads

Prefer native T3 MCP environment discovery and launch tools when they support the destination. This fallback covers the routing gap addressed by [upstream PR #15904](https://github.com/pingdotgg/t3code/pull/15904); retire it once equivalent native routing works.

Use this only when the user requests a new top-level thread on another environment. It does not create a subagent or move the current conversation. A continuation needs a useful handoff in its initial message.

## Helper

Run `uv run <skill-directory>/scripts/t3_remote.py --help` on the source Linux machine that holds the configured T3 connections. Resolve the actual skill directory rather than assuming a checkout path. The helper uses HTTPS for identity, authentication, projects and thread status, and WSS for provider configuration and launch RPCs. Reuse the saved HTTPS endpoint. The destination can be a standalone T3 server or the regular desktop app's embedded server, which must remain running. T3 can manage private HTTPS through CLI `--tailscale-serve` or the desktop Tailscale HTTPS setting. Changing server exposure is separate from launching a thread.

Routing works in either direction. Each source machine needs its own saved connection to the destination and access to its unlocked desktop keyring. A connection saved on one machine does not grant the reverse direction. For a headless provider process, the helper discovers the existing systemd user bus if its address is absent; it does not start a desktop session or unlock a keyring. Discovery omits plaintext routes, including learned LAN addresses.

It decrypts the desktop's connection catalog in memory using the existing unlocked Secret Service key. Only saved HTTPS bearer routes are supported. An HTTPS endpoint still requires that saved session and unlocked source keyring. Neither Varlock nor a new credential file is required. Locked keyrings, other encryption formats, SSH/relay/DPoP connections, and ambiguous routes fail explicitly. Do not export credentials, inspect raw catalog contents, print raw server configuration, bypass TLS, or enable transport tracing. Both HTTPS and WSS disable environment proxies and redirects.

1. Run `uv run <helper> list`. Select the requested enabled environment by exact ID or unique label. If it has several bearer routes, add `--connection-id` from this output.
2. Run `uv run <helper> inspect --environment <id-or-label>`. This verifies the server identity and authentication and returns selected project and provider/model fields. Choose the destination project and model from that result. Preserve the user's model options and the calling thread's permission ceiling; this helper uses the desktop's credential, so it cannot infer that ceiling for you.
3. Prepare the launch request as JSON in a temporary file outside repositories, or pass it on stdin. Required fields: `projectId`, `title`, `modelSelection`, `runtimeMode`, `interactionMode`, `workspaceStrategy`, and `initialMessage`. Use T3's normal launch schema, shown below. Choose the workspace before launch. Never substitute a local project ID for the destination's project ID.
4. Run `uv run <helper> launch --environment <id-or-label> --request-file <file-or-dash>`. The helper prints its thread and command IDs before sending. Retain these IDs. It validates the project/model and sends exactly one launch request, without automatic retry.
5. Run `uv run <helper> status --environment <id-or-label> --thread-id <returned-id>` to verify preparation or completion. Report the actual destination and state, and link `[title](t3-thread://v1/<threadId>)` with the ID exactly as returned.

If the launch response is lost, inspect the printed thread ID with `status` before trying again. Do not generate another ID while the first launch is unresolved. A repeated `launch --thread-id <same-id>` refuses an existing thread. A missing thread after an ambiguous request is not proof that a fresh launch is safe; resolve the original request first. Remove temporary prompt/request files after use.

Example request shape (replace project, provider, model and options from `inspect`):

```json
{
  "projectId": "destination-project-id",
  "title": "Continuation",
  "modelSelection": {
    "instanceId": "codex",
    "model": "gpt-6.1-sol",
    "options": [{"id": "reasoningEffort", "value": "low"}]
  },
  "runtimeMode": "full-access",
  "interactionMode": "default",
  "workspaceStrategy": {"type": "root"},
  "initialMessage": {"text": "Requested task and handoff context", "attachments": []}
}
```

Set modes to the caller's authorized modes, not automatically to the example values. Local attachments cannot be transferred by this helper. It supports root, new-worktree, and existing-worktree bindings through the destination's launch API.

The default catalog is `~/.t3/userdata/connection-catalog.json`; `--catalog` supports a different desktop profile. The helper never writes that catalog, the keyring, tokens, or launch receipts. Its output omits credentials and transcripts. Changes to T3's catalog, encryption, or API schemas require checking matching local source before adapting this temporary workaround.
