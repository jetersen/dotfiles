set -euo pipefail
home_directory=$1
state_directory="$home_directory/.local/state/dotfiles"
marker="$state_directory/nixos-startup-migrated"
[[ -e "$marker" ]] && exit 0
legacy_paths=(
  "$home_directory/.config/fish/conf.d/config.fish"
  "$home_directory/.config/powershell/Microsoft.PowerShell_profile.ps1"
)
# Preflight every backup before changing any startup file.
for path in "${legacy_paths[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    if [[ -e "$path.pre-nixos" || -L "$path.pre-nixos" ]]; then
      echo "Refusing to overwrite startup backup: $path.pre-nixos" >&2
      exit 1
    fi
  fi
done
for path in "${legacy_paths[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    mv -- "$path" "$path.pre-nixos"
  fi
done
mkdir -p "$state_directory"
touch "$marker"
