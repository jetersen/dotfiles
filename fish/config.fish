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
alias myip="curl -sSfL -w '\n' https://ifconfig.me/ip"
alias github-auto-merge="gh pr list --json number --jq .[].number | xargs -I{} sh -c 'gh pr review {} --approve; gh pr merge {} --squash'"
function ride
    xdg-open (fd --ignore-case --absolute-path --max-depth 3 --max-results 1 --threads 1 --type file --extension sln . $argv[1])
end