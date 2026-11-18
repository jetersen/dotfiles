# Publish the fixed home resolver with an optional validated work search suffix.
set -euo pipefail

base=${1:?base resolver file}
target=${2:?output resolver file}
work_search=${3:?work search-domain JSON}
search=$(jq -er '
  select(type == "string" and length <= 253)
  | select(test("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"))
' "$work_search" 2>/dev/null) || search=""

temporary=$(mktemp "${target}.XXXXXX")
trap 'rm -f "$temporary"' EXIT
awk -v suffix="$search" '
  /^search / && suffix != "" {
    present = 0
    for (i = 2; i <= NF; i++) if ($i == suffix) present = 1
    if (!present) $0 = $0 " " suffix
  }
  { print }
' "$base" > "$temporary"
chmod 644 "$temporary"
if ! cmp -s "$temporary" "$target"; then
  mv -f "$temporary" "$target"
fi
