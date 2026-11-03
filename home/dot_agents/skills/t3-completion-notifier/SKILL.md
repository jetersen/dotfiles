---
name: t3-completion-notifier
description: Poll a long-running job with a Linux user timer and wake a T3 thread through a webhook. Use before schedule_task interval or fixed-time progress check-ins, or for watcher.log and completion timers without recurring agent runs.
---

# T3 completion notifier

Use a systemd user timer for short status checks and a T3 webhook to wake this thread at completion. The job and its orchestrator must survive the T3/provider session ending; the notifier only observes them.

1. Define the exact execution identity and durable success/failure evidence that survives unit collection. Missing results or a disappeared process do not establish success.
2. Follow [setup.md](references/setup.md) for the adapter, config, webhook and timer. Validate active, collected successful/failed, wrong-identity and incomplete-evidence cases.
3. Enable the webhook, start the timer and verify its first tick. Remove any agent check-ins this watch replaces.
4. Report the host, cadence, state/log path and schedule ID, then end the agent turn.

Include a clickable absolute-path link to `watcher.log` in the first message after setup and whenever switching to a new log file.

Transient timers do not survive reboot. Keep the watch's state, config and helper/interpreter dependencies stable until reconciliation; Nix store references in transient units are not GC roots.
