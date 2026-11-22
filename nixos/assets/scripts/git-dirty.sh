#!/usr/bin/env bash
# Walk ROOT (default: ~/git) and report repos that are "dirty":
#   - uncommitted changes (staged, unstaged, or untracked)
#   - commits on local branches not pushed to their upstream
#   - local branches with no upstream configured
#
# Usage: git-dirty [ROOT] [--quiet]
#
#   --quiet   Only print dirty repos (skip the trailing summary).

set -uo pipefail

root="$HOME/git"
quiet=0
for arg in "$@"; do
    case "$arg" in
        --quiet|-q) quiet=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) root="$arg" ;;
    esac
done

if [[ ! -d "$root" ]]; then
    echo "git-dirty: $root does not exist" >&2
    exit 1
fi

total=0 dirty=0 clean=0

while IFS= read -r -d '' gitentry; do
    repo="$(dirname "$gitentry")"
    total=$((total + 1))

    reasons=()

    # Uncommitted: staged, unstaged, or untracked files.
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        reasons+=("uncommitted")
    fi

    # Per-branch upstream check. Collect branches missing upstream
    # or ahead of upstream.
    no_upstream=()
    ahead=()
    while IFS=$'\t' read -r branch upstream; do
        [[ -z "$branch" ]] && continue
        if [[ -z "$upstream" ]]; then
            no_upstream+=("$branch")
            continue
        fi
        # Count commits in branch not in upstream.
        n="$(git -C "$repo" rev-list --count "$upstream..$branch" 2>/dev/null || echo 0)"
        if [[ "$n" -gt 0 ]]; then
            ahead+=("$branch:+$n")
        fi
    done < <(git -C "$repo" for-each-ref --format='%(refname:short)%09%(upstream:short)' refs/heads 2>/dev/null)

    if [[ ${#ahead[@]} -gt 0 ]]; then
        reasons+=("unpushed[${ahead[*]}]")
    fi
    if [[ ${#no_upstream[@]} -gt 0 ]]; then
        reasons+=("no-upstream[${no_upstream[*]}]")
    fi

    if [[ ${#reasons[@]} -gt 0 ]]; then
        dirty=$((dirty + 1))
        printf '%s\t%s\n' "$repo" "${reasons[*]}"
    else
        clean=$((clean + 1))
    fi
done < <(find "$root" -name .git -prune -print0)

if [[ $quiet -eq 0 ]]; then
    echo
    echo "total=$total dirty=$dirty clean=$clean"
fi

[[ $dirty -eq 0 ]]
