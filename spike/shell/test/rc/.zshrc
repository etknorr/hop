# The widget test's zsh: a prompt fed by a precmd hook, so a stale prompt shows the hook never re-ran.
setopt prompt_subst
precmd() { PRE=${PWD:t} }
PS1='[$PRE]> '
autoload -Uz compinit && compinit -u -D
eval "$(hopx init zsh)"
cd "$HOPX_T/repo"
