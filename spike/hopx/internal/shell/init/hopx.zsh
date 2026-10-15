# hopx init zsh: eval "$(hopx init zsh)" in ~/.zshrc, after compinit.

zmodload -F zsh/files b:zf_rm 2>/dev/null

# The binary writes the chosen dir to HOPX_CMDFILE, and only this function cds, so no binary output is ever eval'd.
# - `cd`, not `builtin cd`, so a zoxide-style cd wrapper and chpwd still see the jump.
# - No `--`: the dir is always absolute, and some cd wrappers read a `--` as a query word.
# - read -d '' rather than $(<f), which would drop a trailing newline in the name.
@CMD@() {
	emulate -L zsh
	if [[ $# -eq 1 && $1 == - ]]; then
		cd -
		return
	fi
	local f="${TMPDIR:-/tmp}/hopx.$$.$RANDOM" dir=''
	local -i rc
	HOPX_CMDFILE=$f command hopx "$@"
	rc=$?
	if [[ -e $f ]]; then
		IFS= read -r -d '' dir <"$f"
		zf_rm -f -- "$f" 2>/dev/null || command rm -f -- "$f"
	fi
	[[ -n $dir ]] || return rc
	cd "$dir" || return
	return rc
}

_hopx() {
	emulate -L zsh
	local -a lines cands
	local l
	lines=("${(@f)$(command hopx __complete "${(@)words[2,CURRENT]}")}")
	for l in "${lines[@]}"; do
		[[ -n $l ]] || continue
		cands+=("${${l%%$'\t'*}//:/\\:}:${l#*$'\t'}")
	done
	_describe -t hopx-args hopx cands
}
(( $+functions[compdef] )) && compdef _hopx @CMD@

# ^G pushes the half-typed line aside and runs the function as a real command; zsh restores the line at the next prompt.
# - accept-line rather than calling the function in the widget, so precmd hooks (vcs_info, p10k, starship) see the new dir.
# - The editor gets the real tty and job control, which a widget body does not give it.
# - The leading space keeps it out of history under HIST_IGNORE_SPACE.
# - hop's own widget keeps ^G when it is loaded, so the two can sit in one shell.
__hopx_widget() {
	zle push-input
	BUFFER=' @CMD@'
	zle accept-line
}

if [[ -o interactive ]]; then
	zle -N hopx-widget __hopx_widget
	if (( ! ${+widgets[hop-widget]} )); then
		bindkey -M emacs '^G' hopx-widget
		bindkey -M viins '^G' hopx-widget
		bindkey -M emacs '^[g' hopx-widget
		bindkey -M viins '^[g' hopx-widget
	fi
fi
