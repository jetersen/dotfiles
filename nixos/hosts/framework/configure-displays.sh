config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell"
mkdir -p "$config_dir"
temporary=$(mktemp "$config_dir/.displays.XXXXXX")
trap 'rm -f "$temporary"' EXIT

# Replace only our named profiles; retain DMS's local layouts and other profiles.
monitors="$config_dir/monitors.json"
current=/dev/stdin
if [[ -s "$monitors" ]]; then current="$monitors"; fi
jq --slurpfile managed "$1" '
  .version = 1
  | .configurations = (
      $managed[0] + [.configurations[]?
        | select(.id as $id | all($managed[0][]; .id != $id))]
    )
' "$current" <<< '{}' > "$temporary"
if ! cmp -s "$temporary" "$monitors"; then mv "$temporary" "$monitors"; fi

# Model identifiers include serial numbers on niri, so either USB-C port matches.
settings="$config_dir/settings.json"
current=/dev/stdin
if [[ -s "$settings" ]]; then current="$settings"; fi
jq '.displayNameMode = "model" | .displayProfileAutoSelect = true' \
  "$current" <<< '{}' > "$temporary"
if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi

# The Framework-only daemon follows the shell's lock and live output state.
plugins="$config_dir/plugin_settings.json"
current=/dev/stdin
if [[ -s "$plugins" ]]; then current="$plugins"; fi
jq '.frameworkPanel.enabled = true' "$current" <<< '{}' > "$temporary"
if ! cmp -s "$temporary" "$plugins"; then mv "$temporary" "$plugins"; fi
