set -euo pipefail
test -n "$NOTIFY_KEY"
test -n "$FRAMEWORK_HOST"
test -n "$ROCKET_HOST"
umask 077
key="$RUNNER_TEMP/nixos-notify-key"
known_hosts="$RUNNER_TEMP/nixos-notify-known-hosts"
trap 'rm -f "$key" "$known_hosts"' EXIT
printf '%s\n' "$NOTIFY_KEY" > "$key"
for machine in framework rocket; do
  case "$machine" in
    framework) host="$FRAMEWORK_HOST" ;;
    rocket) host="$ROCKET_HOST" ;;
  esac
  read -r key_type public_key _ < "nixos/keys/$machine-host.pub"
  printf '%s %s %s\n' "$machine" "$key_type" "$public_key" > "$known_hosts"
  if timeout 30 ssh -p 2222 -F /dev/null -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o ConnectTimeout=5 -o ConnectionAttempts=1 \
    -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
    -o StrictHostKeyChecking=yes -o "HostKeyAlias=$machine" \
    -o "UserKnownHostsFile=$known_hosts" "comin-notify@$host" 'comin fetch'; then
    echo "$machine accepted the deployment notification."
  else
    echo "::warning::$machine could not accept the notification; it will check on boot, resume, or network reconnect."
  fi
done
