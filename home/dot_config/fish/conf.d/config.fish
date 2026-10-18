set -x BROWSER "zen-browser"
if not set -q PROMPT_DEFAULT_USER
  if set -q SUDO_USER
    set -gx PROMPT_DEFAULT_USER $SUDO_USER
  else
    set -gx PROMPT_DEFAULT_USER $USER
  end
end
set -x EDITOR "code --wait"
set -x SUDO_EDITOR "vim"
set -x CDPATH $HOME/git
set -x PACKAGEOUTPUTPATH "$HOME/.nuget/local"
set -x DOTNET_ROOT "$HOME/.dotnet"

fish_add_path --path --prepend --move --global \
  ~/.dotnet/tools \
  ~/.dotnet \
  ~/.local/bin \
  ~/.npm-global/bin \
  ~/.cargo/bin \
  ~/.krew/bin \
  ~/.aspire/bin \
  ~/go/bin

alias vim="nvim"
alias vi="nvim"
alias l="eza -1 --color=always --group-directories-first --all"
alias ll="eza --binary --group --header --all --long --links --classify --group-directories-first"
alias ls="eza --color=always --group-directories-first"
alias pip="pip3"
alias python="python3"
alias rimraf="rm -rf"
alias myip="curl -sSfL -w '\n' https://api.ipify.org"
alias myip6="curl -sSfL -w '\n' https://api6.ipify.org"
alias cc="claude --dangerously-skip-permissions"
alias cx="codex --dangerously-bypass-approvals-and-sandbox"
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
alias d="docker"
alias dc="docker compose"
function rider-eap
  for ext in slnx sln csproj
    set file (fd --ignore-case --no-ignore --absolute-path --max-depth 3 --max-results 1 --threads 1 --type file --extension $ext . $argv[1])
    test -n "$file" && break
  end

  if test -n "$file"
    echo "$file"
    nohup rider-eap "$file" >/dev/null 2>&1 &
  else
    echo "No .slnx, .sln, or .csproj file found."
  end
end
source "$HOME/.config/shell/clone.fish"

function cws
  cd ~/git
end
function dotfile
  xdg-open https://github.com/jetersen/dotfiles
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
  docker inspect --format '{{ .NetworkSettings.Networks.nat.IPAddress }}' $argv[1]
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

if command -q mise
  mise activate fish | source
end

oh-my-posh init fish --config ~/.config/oh-my-posh/jetersen.omp.json | source

if command -q wt
  wt config shell init fish | source
end
