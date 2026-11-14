# Keep T3's normal interface and prompt faces, with explicit color emoji fallback.
umask 077
directory="$HOME/.t3/userdata"
mkdir -p "$directory"
settings="$directory/client-settings.json"
input=/dev/stdin
if [[ -s "$settings" ]]; then input="$settings"; fi
temporary=$(mktemp "$directory/.typography.XXXXXX")
trap 'rm -f "$temporary"' EXIT
jq '.fontFamilyComposer = "Inter Variable, Noto Color Emoji"
    | .fontFamilySans = "Inter Variable, Noto Color Emoji"' "$input" <<< '{}' > "$temporary"
if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi
