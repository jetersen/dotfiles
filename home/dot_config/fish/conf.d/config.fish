set -x BROWSER "zen-browser"
set -x SESSIONDEFAULTUSER $USER
set -x EDITOR "code --wait"
set -x SUDO_EDITOR "vim"
set -x CDPATH $HOME/git/code $HOME/git/work
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
alias open="xdg-open"
alias myip="curl -sSfL -w '\n' https://api.ipify.org"
alias myip6="curl -sSfL -w '\n' https://api6.ipify.org"
alias cc="claude --dangerously-skip-permissions"
alias cx="codex --dangerously-bypass-approvals-and-sandbox"
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
      command gh pr merge $pr --squash --auto
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
function __clone_dest_from_args
  set -l value_flags -b --branch -o --origin -c --config -u --upload-pack -j --jobs --depth --reference --reference-if-able --template --separate-git-dir --filter --revision --server-option --shallow-since --shallow-exclude --ref-format --bundle-uri --upstream-remote-name
  set -l positionals
  set -l skip 0
  for a in $argv
    if test "$a" = "--"
      break
    end
    if test $skip -eq 1
      set skip 0
      continue
    end
    if contains -- "$a" $value_flags
      set skip 1
      continue
    end
    if string match -q -- "-*" "$a"
      continue
    end
    set positionals $positionals $a
  end
  if test (count $positionals) -ge 2
    echo $positionals[2]
  else if test (count $positionals) -ge 1
    set -l name (basename $positionals[1])
    string replace -r '\.git$' '' -- $name
  end
end

function __write_git_remote
  set -l url (command git remote get-url origin 2>/dev/null)
  if test -n "$url"
    echo $url > .git-remote
  end
end

function git
  if test "$argv[1]" = "clone"
    set -l dest (__clone_dest_from_args $argv[2..])
    command git $argv
    set -l rc $status
    if test $rc -eq 0 -a -n "$dest" -a -d "$dest"
      cd $dest
      __write_git_remote
    end
    return $rc
  else
    command git $argv
  end
end
function gh
  if test "$argv[1]" = "repo" -a "$argv[2]" = "clone"
    set -l dest (__clone_dest_from_args $argv[3..])
    command gh $argv
    set -l rc $status
    if test $rc -eq 0 -a -n "$dest" -a -d "$dest"
      cd $dest
      __write_git_remote
    end
    return $rc
  else
    command gh $argv
  end
end

function cws
  cd ~/git/code
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
