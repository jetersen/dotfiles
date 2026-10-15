set -eg DOTFILES_PROMPT_IDENTITY
if test -n "$(@identity@)"
  set -gx DOTFILES_PROMPT_IDENTITY 1
end
