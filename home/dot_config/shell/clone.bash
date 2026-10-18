__clone_dest_from_args() {
  # Bare/mirror destinations differ from working trees; leave directory changes
  # to the caller instead of guessing from the repository name.
  local option
  for option in "$@"; do
    case "$option" in --bare|--mirror) return 0 ;; esac
  done
  local github=0
  if [[ "${1:-}" == --github ]]; then github=1; shift; fi
  local value_flags=" -b --branch -o --origin -c --config -u --upload-pack -j --jobs --depth --reference --reference-if-able --template --separate-git-dir --filter --revision --server-option --shallow-since --shallow-exclude --ref-format --bundle-uri --upstream-remote-name "
  local skip=0 end_options=0 repo="" dest="" arg
  for arg in "$@"; do
    if (( skip )); then skip=0; continue; fi
    if (( ! end_options )); then
      if [[ "$arg" == "--" ]]; then
        if (( github )); then break; fi
        end_options=1; continue
      fi
      if [[ "$value_flags" == *" $arg "* ]]; then skip=1; continue; fi
      if [[ "$arg" == -* ]]; then continue; fi
    fi
    if [[ -z "$repo" ]]; then repo="$arg"; else dest="$arg"; break; fi
  done
  if [[ -n "$dest" ]]; then
    printf '%s\n' "$dest"
  elif [[ -n "$repo" ]]; then
    repo="${repo%/}"
    repo="${repo##*/}"
    repo="${repo##*:}"
    printf '%s\n' "${repo%.git}"
  fi
}

git() {
  if [[ "$1" == "clone" ]]; then
    local dest
    dest=$(__clone_dest_from_args "${@:2}")
    command git "$@"
    local rc=$?
    if (( rc == 0 )) && [[ -n "$dest" && -d "$dest" ]]; then
      if [[ "$dest" != /* ]]; then dest="$PWD/$dest"; fi
      cd -- "$dest" || return
    fi
    return $rc
  else
    command git "$@"
  fi
}

gh() {
  if [[ "$1" == "repo" && "$2" == "clone" ]]; then
    local dest
    dest=$(__clone_dest_from_args --github "${@:3}")
    command gh "$@"
    local rc=$?
    if (( rc == 0 )) && [[ -n "$dest" && -d "$dest" ]]; then
      if [[ "$dest" != /* ]]; then dest="$PWD/$dest"; fi
      cd -- "$dest" || return
    fi
    return $rc
  else
    command gh "$@"
  fi
}
