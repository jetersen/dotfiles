function __clone_dest_from_args
  if contains -- --bare $argv; or contains -- --mirror $argv
    return 0
  end
  set -l github 0
  if test "$argv[1]" = --github
    set github 1
    set -e argv[1]
  end
  set -l value_flags -b --branch -o --origin -c --config -u --upload-pack -j --jobs --depth --reference --reference-if-able --template --separate-git-dir --filter --revision --server-option --shallow-since --shallow-exclude --ref-format --bundle-uri --upstream-remote-name
  set -l positionals
  set -l skip 0
  set -l end_options 0
  for arg in $argv
    if test $skip -eq 1
      set skip 0
      continue
    end
    if test $end_options -eq 0
      if test "$arg" = --
        if test $github -eq 1
          break
        end
        set end_options 1
        continue
      end
      if contains -- "$arg" $value_flags
        set skip 1
        continue
      end
      if string match -q -- '-*' "$arg"
        continue
      end
    end
    set -a positionals "$arg"
  end
  if test (count $positionals) -ge 2
    printf '%s\n' "$positionals[2]"
  else if test (count $positionals) -eq 1
    string replace -r '\.git$' '' -- (string replace -r '^.*[/:]' '' -- (string trim -r -c / -- "$positionals[1]"))
  end
end

function git
  if test "$argv[1]" = clone
    set -l dest (__clone_dest_from_args $argv[2..])
    command git $argv
    set -l rc $status
    if test $rc -eq 0; and test -n "$dest"; and test -d "$dest"
      if not string match -q '/*' -- "$dest"
        set dest "$PWD/$dest"
      end
      cd -- "$dest"; or return
    end
    return $rc
  end
  command git $argv
end

function gh
  if test "$argv[1]" = repo; and test "$argv[2]" = clone
    set -l dest (__clone_dest_from_args --github $argv[3..])
    command gh $argv
    set -l rc $status
    if test $rc -eq 0; and test -n "$dest"; and test -d "$dest"
      if not string match -q '/*' -- "$dest"
        set dest "$PWD/$dest"
      end
      cd -- "$dest"; or return
    end
    return $rc
  end
  command gh $argv
end
