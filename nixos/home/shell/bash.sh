open() {
  nohup xdg-open "$@" </dev/null >/dev/null 2>&1 &
  disown
}

ride() {
  local file target="${1:-.}"
  if [[ ! -f "$target" ]]; then
    for ext in slnx slnf sln csproj; do
      file=$(fd --ignore-case --no-ignore --absolute-path --max-depth 3 --max-results 1 --threads 1 --type file --extension "$ext" . "$target")
      if [[ -n "$file" ]]; then target="$file"; break; fi
    done
  fi
  nohup rider "$target" >/dev/null 2>&1 &
}

github-auto-merge() {
  local fields="number,autoMergeRequest,reviewDecision"
  local prs
  if [[ $# -gt 0 ]]; then
    prs=$(command gh pr list --author "$1" --json "$fields" --jq '.[] | [.number, .reviewDecision, (.autoMergeRequest | length)] | @tsv')
  else
    prs=$(command gh pr list --json "$fields,author" --jq '[.[] | select(.author.is_bot)] | .[] | [.number, .reviewDecision, (.autoMergeRequest | length)] | @tsv')
  fi
  local my_login
  my_login=$(command gh api user --jq '.login')
  while IFS=$'\t' read -r pr review_decision has_auto_merge; do
    [[ -z "$pr" ]] && continue
    if [[ "$review_decision" != "APPROVED" ]]; then
      local approved
      approved=$(command gh api "repos/{owner}/{repo}/pulls/$pr/reviews" --jq "[.[] | select(.user.login == \"$my_login\" and .state == \"APPROVED\")] | length")
      if [[ "$approved" -eq 0 ]]; then
        command gh pr review "$pr" --approve
      fi
    fi
    if [[ "$has_auto_merge" -eq 0 ]]; then
      command gh pr merge "$pr" --rebase --auto
    fi
  done <<< "$prs"
}

source "$HOME/.config/shell/clone.bash"

cws() {
  cd ~/git || return
}

dotfile() {
  xdg-open https://forgejo.jetersen.dev/jetersen/dotfiles
}

clean-sln() {
  fd -HI -t d '^(\.vs|bin|obj)$' -x rm -rf
}

hostfile() {
  sudoedit /etc/hosts
}

dcid() {
  docker ps -l -q
}

dprune() {
  docker system prune "$@"
}

dip() {
  docker inspect --format '{{range .NetworkSettings.Networks}}{{println .IPAddress}}{{end}}' "$1"
}

dotenv() {
  local env_file="${1:-.env}"
  if [[ ! -f "$env_file" ]]; then
    echo "No .env file found"
    return 1
  fi
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    local key="${line%%=*}"
    local value="${line#*=}"
    export "$(echo "$key" | xargs)=$(echo "$value" | xargs)"
  done < "$env_file"
}
