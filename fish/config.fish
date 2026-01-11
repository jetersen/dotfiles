set -x BROWSER "zen-browser"
set -x SESSIONDEFAULTUSER $USER
set -x EDITOR "code --wait"
set -x CDPATH $HOME/git/code $HOME/git/work

fish_add_path --path --prepend --move --global \
  ~/.dotnet/tools \
  ~/.local/bin \
  ~/.npm-global/bin \
  ~/.cargo/bin \
  ~/.krew/bin \
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

oh-my-posh init fish --config ~/.jetersen.omp.json | source
