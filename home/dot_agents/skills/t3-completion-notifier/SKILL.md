---
name: t3-completion-notifier
description: Poll a long-running job with a Linux user timer and wake a T3 thread through a signed webhook. Use before schedule_task interval or fixed-time progress check-ins, or for watcher.log and completion timers without recurring agent runs.
---

# T3 completion notifier

Use a systemd user timer for short status checks and a T3 webhook to wake this thread once the job reaches a terminal state. The job and any local orchestrator must survive the T3/provider session ending. The notifier observes them; it never resumes, cancels or mutates them. End the agent turn after setup.

1. Define the exact execution identity and authoritative success/failure evidence. Missing results or a disappeared process do not establish success.
2. Read [setup.md](references/setup.md) for the adapter, config, webhook prompt and commands. Use a private watch directory and a fresh UUID; retain both when resuming that same watch.
3. Read the live T3 scheduling schemas. Create one signed webhook bound to this thread, with exact job/watch/event filters, event-ID replay dedupe and no coalescing. Complete the private signing-key request and consume its `secretRef`. Recover uncertain creation responses using the original `clientRequestId`.
4. Use a local webhook or an existing Tailscale HTTPS endpoint with the same signing setup. Use service discovery. Read [local-compatibility.md](references/local-compatibility.md) for endpoint and credential discovery.
5. Validate the job adapter with active, successful, failed, wrong-identity and incomplete-evidence fixtures. Enable the webhook, preflight, start the timer and verify its first tick. Replace old agent check-ins after a valid active tick, or after terminal reconciliation if already finished. Give queued old turns a supersession check.

Report the host, cadence, state/log path and schedule ID. Keep each watch's helper/config stable until reconciliation.

The helper persists and retries the same terminal event, records acceptance, then stops its timer. Acceptance does not prove a receiving turn started; check delivery history and thread state before resending an accepted event. After six days it stops the timer and preserves the pending event, inside T3's seven-day replay window.

Transient timers do not survive reboot. Keep watch state and helper/interpreter dependencies available until reconciliation; Nix store references in transient units are not GC roots.
