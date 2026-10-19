# The widget test's zsh: a prompt fed by a precmd hook, so a stale prompt shows the hook never re-ran.
setopt prompt_subst
precmd() { PRE=${PWD:t} }
PS1='[$PRE]> '
# macOS /etc/zshrc points HISTFILE at $ZDOTDIR, which is this tracked dir.
HISTFILE=$HOP_T/tmp/zsh_history
autoload -Uz compinit && compinit -u -D
eval "$(hop init zsh)"
cd "$HOP_T/repo"
