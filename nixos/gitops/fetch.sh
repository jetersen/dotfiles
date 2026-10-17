set -euo pipefail
# This worker runs only in response to an event. Never start a stopped daemon.
active() { @timeout@ 5 @systemctl@ --quiet is-active comin.service; }
defer() { @timeout@ 5 @systemctl@ --no-block restart comin-fetch-retry.timer; }
wait_for_comin() {
  for attempt in {1..15}; do
    active || return 1
    if status=$(@timeout@ 2 @comin@ status --json 2>/dev/null); then
      return 0
    fi
    @sleep@ 1
  done
  return 1
}
active || exit 0
if ! wait_for_comin; then
  active && defer
  exit 0
fi
# Resume remains an explicit user action. A deferred event cannot undo a pause.
if @jq@ -e '.is_suspended != false' <<< "$status" >/dev/null; then
  exit 0
fi
if ! @jq@ -e '
  .fetcher.is_fetching == false and .deployer.is_deploying == false and
  .builder.is_evaluating == false and .builder.is_building == false
' <<< "$status" >/dev/null; then
  defer
  exit 0
fi
# v0.14 ignores unchanged commits. Retry a settled failure only after the event
# has waited out the previous operation, so transient evaluation or build failures can recover.
if @jq@ -e '
  .builder.generation.eval_status == "failed" or
  .builder.generation.build_status == "failed"
' <<< "$status" >/dev/null; then
  @timeout@ 30 @systemctl@ try-restart comin.service
  if ! wait_for_comin; then
    active && defer
    exit 0
  fi
fi
active || exit 0
@timeout@ 10 @comin@ fetch
