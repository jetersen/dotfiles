fish_add_path --path --prepend --move --global \
    ~/.dotnet/tools \
    ~/.local/bin \
    ~/.npm-global/bin \
    ~/.cargo/bin \
    ~/.krew/bin

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
    set file (fd --ignore-case --no-ignore --absolute-path --max-depth 3 --max-results 1 --threads 1 --type file --extension sln . $argv[1])
    if test -z "$file"
        set file (fd --ignore-case --no-ignore --absolute-path --max-depth 3 --max-results 1 --threads 1 --type file --extension csproj . $argv[1])
    end
    if test -n "$file"
        echo "$file"
        xdg-open $file
    else
        echo "No .sln or .csproj file found."
    end
end

set -x BROWSER "zen-browser"
set -x SESSIONDEFAULTUSER $USER
set -x EDITOR "code --wait"
set -x CDPATH $HOME/git/code $HOME/git/work
set -x PACKAGEOUTPUTPATH $HOME/.nuget/local

oh-my-posh init fish --config ~/.jetersen.omp.json | source
