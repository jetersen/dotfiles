#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to install .NET." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to determine the current .NET releases." >&2
  exit 1
fi

dotnet_tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$dotnet_tmp_dir"' EXIT

installer="$dotnet_tmp_dir/dotnet-install.sh"
release_index="$dotnet_tmp_dir/releases-index.json"

echo "Downloading .NET release information and install script..."
curl --fail --silent --show-error --location --retry 3 \
  https://dot.net/v1/dotnet-install.sh \
  --output "$installer"
curl --fail --silent --show-error --location --retry 3 \
  https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json \
  --output "$release_index"

IFS=$'\t' read -r current_channel current_version next_channel next_version < <(
  jq --raw-output '
    .["releases-index"] as $releases
    | ($releases
        | map(select((.["latest-release"] | contains("-")) | not))
        | max_by(.["channel-version"] | split(".")[0] | tonumber)) as $current
    | ($current["channel-version"] | split(".")[0] | tonumber + 1) as $next_major
    | ($releases
        | map(select((.["channel-version"] | split(".")[0] | tonumber) == $next_major))
        | first) as $next
    | [
        $current["channel-version"],
        $current["latest-sdk"],
        ($next["channel-version"] // ""),
        ($next["latest-sdk"] // "")
      ]
    | @tsv
  ' "$release_index"
)

if [[ -z "$current_channel" || -z "$current_version" ]]; then
  echo "Could not determine the current .NET SDK release." >&2
  exit 1
fi

install_dir="$HOME/.dotnet"

echo "Installing current .NET $current_channel SDK $current_version..."
bash "$installer" \
  --version "$current_version" \
  --install-dir "$install_dir" \
  --no-path

if [[ -n "$next_channel" && -n "$next_version" ]]; then
  echo "Installing next .NET $next_channel SDK $next_version..."
  bash "$installer" \
    --version "$next_version" \
    --install-dir "$install_dir" \
    --no-path
else
  current_major=${current_channel%%.*}
  echo ".NET $((current_major + 1)).0 is not published yet; leaving the current SDK installed."
fi

dotnet_cli="$install_dir/dotnet"
global_tools=(
  aws.codeartifact.nuget.credentialprovider
  csharp-ls
  dotnet-script
)

for package in "${global_tools[@]}"; do
  if "$dotnet_cli" tool list --global "$package" --format json >/dev/null 2>&1; then
    echo "Updating global .NET tool $package..."
    "$dotnet_cli" tool update --global "$package"
  else
    echo "Installing global .NET tool $package..."
    "$dotnet_cli" tool install --global "$package"
  fi
done
