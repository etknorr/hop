# hop init bash: eval "$(hop init bash)" in ~/.bashrc. Works on bash 3.2 (macOS /bin/bash) and 5.x.

# `cd`, not `builtin cd`, so a cd wrapper still sees the jump; no `--`, since the dir is always absolute.
# - read, not $(<f): bash 3.2 forks a subshell for the substitution, and it would drop a trailing newline.
@CMD@() {
	if [[ $# -eq 1 && $1 == - ]]; then
		cd -
		return
	fi
	local f="${TMPDIR:-/tmp}/hop.$$.$RANDOM" rc dir=
	HOP_CMDFILE=$f HOP_SHELL=bash HOP_INIT_HASH=@HASH@ command hop "$@"
	rc=$?
	if [[ -e $f ]]; then
		IFS= read -r -d '' dir <"$f"
		command rm -f -- "$f"
	fi
	[[ -n $dir ]] || return "$rc"
	cd "$dir" || return
	return "$rc"
}

# Words come from COMP_LINE split on blanks, since bash 4+ also splits COMP_WORDS at COMP_WORDBREAKS (`=`, `:`) and 3.2 does not.
# - Either way readline replaces only the text after the last break character, so each reply drops what precedes it there.
_@CMD@_complete() {
	local IFS=$' \t\n' l i cur pre=
	local -a w
	cur=${COMP_LINE:0:COMP_POINT}
	read -ra w <<<"$cur"
	if [[ -z $cur || $cur == *[[:space:]] ]]; then
		cur=
	else
		cur=${w[${#w[@]}-1]}
		w=("${w[@]:0:${#w[@]}-1}")
	fi
	for ((i = ${#cur} - 1; i >= 0; i--)); do
		if [[ $COMP_WORDBREAKS == *"${cur:i:1}"* ]]; then
			pre=${cur:0:i+1}
			break
		fi
	done
	IFS=$'\n'
	COMPREPLY=()
	for l in $(command hop __complete "${w[@]:1}" "$cur"); do
		l=${l%%$'\t'*}
		COMPREPLY+=("${l#"$pre"}")
	done
}
complete -F _@CMD@_complete @CMD@

# ^G turns the line into ` @CMD@`, accepts it, and restores the line at the next prompt.
# - Accepting rather than running inside bind -x is what re-runs PROMPT_COMMAND and PS1, so the prompt shows the new dir.
# - The macro text after accept-line is read by the next readline call, which is what lands the restore on the new prompt.
# - Every step is a private \C-x\C-_ sequence bound in each keymap, so vi-mode users get the same widget.
if [[ $- == *i* ]]; then
	if (( BASH_VERSINFO[0] >= 4 )); then
		__@CMD@_widget_save() {
			__hop_line=$READLINE_LINE
			__hop_point=$READLINE_POINT
			READLINE_LINE=' @CMD@'
			READLINE_POINT=${#READLINE_LINE}
		}
		__@CMD@_widget_restore() {
			READLINE_LINE=$__hop_line
			READLINE_POINT=$__hop_point
			__hop_line= __hop_point=0
		}
		for __hop_km in emacs-standard vi-insert vi-command; do
			bind -m "$__hop_km" -x '"\C-x\C-_s": __@CMD@_widget_save'
			bind -m "$__hop_km" -x '"\C-x\C-_r": __@CMD@_widget_restore'
			bind -m "$__hop_km" '"\C-x\C-_a": accept-line'
			bind -m "$__hop_km" '"\C-g": "\C-x\C-_s\C-x\C-_a\C-x\C-_r"'
			bind -m "$__hop_km" '"\eg": "\C-x\C-_s\C-x\C-_a\C-x\C-_r"'
		done
	else
		# bash 3.2 has no READLINE_LINE, so the line rides the kill ring; the appended space keeps an empty line from yanking a stale kill.
		for __hop_km in emacs-standard vi-insert; do
			bind -m "$__hop_km" '"\C-x\C-_e": end-of-line'
			bind -m "$__hop_km" '"\C-x\C-_b": beginning-of-line'
			bind -m "$__hop_km" '"\C-x\C-_k": kill-line'
			bind -m "$__hop_km" '"\C-x\C-_y": yank'
			bind -m "$__hop_km" '"\C-x\C-_h": backward-delete-char'
			bind -m "$__hop_km" '"\C-x\C-_a": accept-line'
			bind -m "$__hop_km" '"\C-g": "\C-x\C-_e \C-x\C-_b\C-x\C-_k @CMD@\C-x\C-_a\C-x\C-_y\C-x\C-_h"'
			bind -m "$__hop_km" '"\eg": "\C-x\C-_e \C-x\C-_b\C-x\C-_k @CMD@\C-x\C-_a\C-x\C-_y\C-x\C-_h"'
		done
	fi
	unset __hop_km
fi
