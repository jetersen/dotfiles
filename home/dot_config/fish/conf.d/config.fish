set -x BROWSER "zen-browser"
set -x SESSIONDEFAULTUSER $USER
set -x EDITOR "code --wait"
set -x CDPATH $HOME/git/code $HOME/git/work
set -x PACKAGEOUTPUTPATH "$HOME/.nuget/local"

fish_add_path --path --prepend --move --global \
  ~/.dotnet/tools \
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
alias github-auto-merge="gh pr list --json number -;-jq .[].number | xargs -I{} sh -c 'gh pr review {} --approve; gh pr merge {} --squash'"
alias g="git"
alias d="docker"
alias dc="docker compose"
function ride
  for ext in slnx sln csproj
    set file (fd --ignore-case --no-ignore --absolute-path --max-depth 3 --max-results 1 --threads 1 --type file --extension $ext . $argv[1])
    test -n "$file" && break
  end

  if test -n "$file"
    echo "$file"
    nohup rider "$file" >/dev/null 2>&1 &
  else
    echo "No .slnx, .sln, or .csproj file found."
  end
end
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
function git
  if test "$argv[1]" = "clone"
    set clone_output (command git $argv 2>&1)
    set status_code $status
    echo $clone_output
    if test $status_code -eq 0
      set dir_name (string match -r "Cloning into '(.+)'" $clone_output | tail -n 1)
      if test -n "$dir_name" -a -d "$dir_name"
        cd "./$dir_name"
      end
    end
    return $status_code
  else
    command git $argv
  end
end
function gh
  if test "$argv[1]" = "repo" -a "$argv[2]" = "clone"
    set clone_output (command gh $argv 2>&1)
    set status_code $status
    echo $clone_output
    if test $status_code -eq 0
      set dir_name (string match -r "Cloning into '(.+)'" $clone_output | tail -n 1)
      if test -n "$dir_name" -a -d "$dir_name"
        cd "./$dir_name"
      end
    end
    return $status_code
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
function drm
  for id in (docker ps -a -q)
    docker rm -f $id
  end
end
function drmi
  for id in (docker images -q -f 'dangling=true')
    docker rmi $id
  end
end
function drmi-all
  for id in (docker images -a -q)
    docker rmi -f $id
  end
end
function drmv
  for id in (docker volume ls -q -f 'dangling=true')
    docker volume rm $id
  end
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

oh-my-posh init fish --config ~/.config/oh-my-posh/jetersen.omp.json | source
