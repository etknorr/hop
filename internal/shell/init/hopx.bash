# hopx init bash: eval "$(hopx init bash)" in ~/.bashrc. Works on bash 3.2 (macOS /bin/bash) and 5.x.

# `cd`, not `builtin cd`, so a cd wrapper still sees the jump; no `--`, since the dir is always absolute.
# - read, not $(<f): bash 3.2 forks a subshell for the substitution, and it would drop a trailing newline.
@CMD@() {
	if [[ $# -eq 1 && $1 == - ]]; then
		cd -
		return
	fi
	local f="${TMPDIR:-/tmp}/hopx.$$.$RANDOM" rc dir=
	HOPX_CMDFILE=$f command hopx "$@"
	rc=$?
	if [[ -e $f ]]; then
		IFS= read -r -d '' dir <"$f"
		command rm -f -- "$f"
	fi
	[[ -n $dir ]] || return "$rc"
	cd "$dir" || return
	return "$rc"
}

# The current word is passed on its own because bash 3.2 leaves an empty one out of COMP_WORDS.
_hopx_complete() {
	local IFS=$'\n' l
	COMPREPLY=()
	for l in $(command hopx __complete "${COMP_WORDS[@]:1:COMP_CWORD-1}" "${COMP_WORDS[COMP_CWORD]}"); do
		COMPREPLY+=("${l%%$'\t'*}")
	done
}
complete -F _hopx_complete @CMD@

# ^G turns the line into ` @CMD@`, accepts it, and restores the line at the next prompt.
# - Accepting rather than running inside bind -x is what re-runs PROMPT_COMMAND and PS1, so the prompt shows the new dir.
# - The macro text after accept-line is read by the next readline call, which is what lands the restore on the new prompt.
# - Every step is a private \C-x\C-_ sequence bound in each keymap, so vi-mode users get the same widget.
if [[ $- == *i* ]]; then
	if (( BASH_VERSINFO[0] >= 4 )); then
		__hopx_widget_save() {
			__hopx_line=$READLINE_LINE
			__hopx_point=$READLINE_POINT
			READLINE_LINE=' @CMD@'
			READLINE_POINT=${#READLINE_LINE}
		}
		__hopx_widget_restore() {
			READLINE_LINE=$__hopx_line
			READLINE_POINT=$__hopx_point
			__hopx_line= __hopx_point=0
		}
		for __hopx_km in emacs-standard vi-insert vi-command; do
			bind -m "$__hopx_km" -x '"\C-x\C-_s": __hopx_widget_save'
			bind -m "$__hopx_km" -x '"\C-x\C-_r": __hopx_widget_restore'
			bind -m "$__hopx_km" '"\C-x\C-_a": accept-line'
			bind -m "$__hopx_km" '"\C-g": "\C-x\C-_s\C-x\C-_a\C-x\C-_r"'
			bind -m "$__hopx_km" '"\eg": "\C-x\C-_s\C-x\C-_a\C-x\C-_r"'
		done
	else
		# bash 3.2 has no READLINE_LINE, so the line rides the kill ring; the appended space keeps an empty line from yanking a stale kill.
		for __hopx_km in emacs-standard vi-insert; do
			bind -m "$__hopx_km" '"\C-x\C-_e": end-of-line'
			bind -m "$__hopx_km" '"\C-x\C-_b": beginning-of-line'
			bind -m "$__hopx_km" '"\C-x\C-_k": kill-line'
			bind -m "$__hopx_km" '"\C-x\C-_y": yank'
			bind -m "$__hopx_km" '"\C-x\C-_h": backward-delete-char'
			bind -m "$__hopx_km" '"\C-x\C-_a": accept-line'
			bind -m "$__hopx_km" '"\C-g": "\C-x\C-_e \C-x\C-_b\C-x\C-_k @CMD@\C-x\C-_a\C-x\C-_y\C-x\C-_h"'
			bind -m "$__hopx_km" '"\eg": "\C-x\C-_e \C-x\C-_b\C-x\C-_k @CMD@\C-x\C-_a\C-x\C-_y\C-x\C-_h"'
		done
	fi
	unset __hopx_km
fi
