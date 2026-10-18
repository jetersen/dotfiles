function open
  command nohup xdg-open $argv </dev/null >/dev/null 2>&1 &
  disown
end
function github-auto-merge
  set fields number,autoMergeRequest,reviewDecision
  if test (count $argv) -gt 0
    set prs (command gh pr list --author $argv[1] --json $fields --jq '.[] | [.number, .reviewDecision, (.autoMergeRequest | length)] | @tsv')
  else
    set prs (command gh pr list --json "$fields,author" --jq '[.[] | select(.author.is_bot)] | .[] | [.number, .reviewDecision, (.autoMergeRequest | length)] | @tsv')
  end
  set my_login (command gh api user --jq '.login')
  for line in $prs
    set parts (string split \t $line)
    set pr $parts[1]
    set review_decision $parts[2]
    set has_auto_merge $parts[3]
    if test "$review_decision" != "APPROVED"
      set approved (command gh api repos/{owner}/{repo}/pulls/$pr/reviews --jq "[.[] | select(.user.login == \"$my_login\" and .state == \"APPROVED\")] | length")
      if test "$approved" -eq 0
        command gh pr review $pr --approve
      end
    end
    if test "$has_auto_merge" -eq 0
      command gh pr merge $pr --rebase --auto
    end
  end
end
function ride
  set -l target .
  if test (count $argv) -gt 0
    set target $argv[1]
  end
  if not test -f "$target"
    for ext in slnx slnf sln csproj
      set -l file (fd --ignore-case --no-ignore --absolute-path --max-depth 3 --max-results 1 --threads 1 --type file --extension $ext . "$target")
      if test -n "$file"
        set target $file
        break
      end
    end
  end
  command nohup rider "$target" >/dev/null 2>&1 &
  disown
end
source "$HOME/.config/shell/clone.fish"

function cws
  cd ~/git
end
function dotfile
  xdg-open https://forgejo.jetersen.dev/jetersen/dotfiles
end
function clean-sln
  fd -HI -t d '^(\.vs|bin|obj)$' -x rm -rf
end
function hostfile
  sudoedit /etc/hosts
end
function dcid
  docker ps -l -q
end
function dprune
  docker system prune $argv
end
function dip
  docker inspect --format '{{range .NetworkSettings.Networks}}{{println .IPAddress}}{{end}}' $argv[1]
end
function dotenv
  set -l env_file .env
  if test (count $argv) -gt 0
    set env_file $argv[1]
  end
  if not test -f $env_file
    echo "No .env file found"
    return 1
  end
  for line in (string split \n -- (cat $env_file))
    if test -z "$line"; or string match -q '#*' -- $line
      continue
    end
    set -l kv (string split -m 1 '=' -- $line)
    if test (count $kv) -eq 2
      set -gx (string trim -- $kv[1]) (string trim -- $kv[2])
    end
  end
end
