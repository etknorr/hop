# hop init zsh: eval "$(hop init zsh)" in ~/.zshrc, after compinit.

zmodload -F zsh/files b:zf_rm 2>/dev/null

# The binary writes the chosen dir to HOP_CMDFILE, and only this function cds, so no binary output is ever eval'd.
# - `cd`, not `builtin cd`, so a zoxide-style cd wrapper and chpwd still see the jump.
# - No `--`: the dir is always absolute, and some cd wrappers read a `--` as a query word.
# - read -d '' rather than $(<f), which would drop a trailing newline in the name.
@CMD@() {
	emulate -L zsh
	if [[ $# -eq 1 && $1 == - ]]; then
		cd -
		return
	fi
	local f="${TMPDIR:-/tmp}/hop.$$.$RANDOM" dir=''
	local -i rc
	HOP_CMDFILE=$f HOP_SHELL=zsh HOP_INIT_HASH=@HASH@ command hop "$@"
	rc=$?
	if [[ -e $f ]]; then
		IFS= read -r -d '' dir <"$f"
		zf_rm -f -- "$f" 2>/dev/null || command rm -f -- "$f"
	fi
	[[ -n $dir ]] || return rc
	cd "$dir" || return
	return rc
}

# compadd, not _describe, which refuses words that look like options outside _arguments.
_@CMD@_complete() {
	emulate -L zsh
	local -a lines cands shown
	local l w d
	lines=("${(@f)$(command hop __complete "${(@)words[2,CURRENT]}")}")
	for l in "${lines[@]}"; do
		[[ -n $l ]] || continue
		w=${l%%$'\t'*} d=${l#*$'\t'}
		cands+=("$w")
		shown+=("$w${d:+  -- $d}")
	done
	compadd -l -d shown -a cands
}
(( $+functions[compdef] )) && compdef _@CMD@_complete @CMD@

# ^G pushes the half-typed line aside and runs the function as a real command; zsh restores the line at the next prompt.
# - accept-line rather than calling the function in the widget, so precmd hooks (vcs_info, p10k, starship) see the new dir.
# - The editor gets the real tty and job control, which a widget body does not give it.
# - The leading space keeps it out of history under HIST_IGNORE_SPACE.
# - zsh hop's widget keeps ^G when it is loaded and this function has another name, so the two can sit in one shell.
__@CMD@_widget() {
	zle push-input
	BUFFER=' @CMD@'
	zle accept-line
}

if [[ -o interactive ]]; then
	zle -N @CMD@-widget __@CMD@_widget
	if [[ ${widgets[hop-widget]-} != user:_hop_widget ]]; then
		bindkey -M emacs '^G' @CMD@-widget
		bindkey -M viins '^G' @CMD@-widget
		bindkey -M emacs '^[g' @CMD@-widget
		bindkey -M viins '^[g' @CMD@-widget
	fi
fi
