#!/usr/bin/env zsh
# hop --doctor: everything needed to diagnose a report, in one paste-able block.
# - Interactive fzf cannot be captured, so the shell's STATE is the next best evidence.
# - Ordered by how often it turns out to be the cause, not alphabetically.
# - Prints paths, so it is local diagnostic output; read it before pasting anywhere public.

typeset -g HOP_DEBUG_LOG=${HOP_DEBUG_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/hop/debug.log}

# _hop_dbg <message> -> append one timestamped line when HOP_DEBUG is set, and never fail.
# - Nothing in hop may break because logging could not write, so every failure here is swallowed.
# - Called from _hop_dispatch, which runs in the parent shell after fzf exits.
_hop_dbg() {
	emulate -L zsh
	[[ -n ${HOP_DEBUG:-} ]] || return 0
	local d=${HOP_DEBUG_LOG:h}
	[[ -d $d ]] || mkdir -p "$d" 2>/dev/null || return 0
	# `date` rather than $EPOCHSECONDS so no zmodload is needed; it only forks while debugging.
	print -r -- "$(date +%FT%T 2>/dev/null) $*" >> "$HOP_DEBUG_LOG" 2>/dev/null
	return 0
}

# _hop_doctor_tool <name> <version-args...> -> one aligned line per external tool.
_hop_doctor_tool() {
	emulate -L zsh
	local name=$1
	shift
	if (( ! ${+commands[$name]} )); then
		printf '  %-8s %s\n' "$name" 'NOT INSTALLED'
		return 0
	fi
	local v
	v=$("$name" "$@" 2>&1 | head -1)
	printf '  %-8s %s\n' "$name" "${v:-present}"
}

_hop_doctor() {
	emulate -L zsh
	setopt local_options no_nomatch
	local root ws REPLY
	local -a reply

	print -r -- '--- hop --doctor ---'
	print -r -- ''

	print -r -- 'install'
	printf '  %-22s %s\n' HOP_HOME "$HOP_HOME"
	local ver
	ver=$(git -C "$HOP_HOME" describe --tags --always --dirty 2>/dev/null) || ver='not a git checkout'
	printf '  %-22s %s\n' version "$ver"
	printf '  %-22s %s\n' 'entry point' "$HOP_HOME/hop.zsh"
	print -r -- ''

	print -r -- 'config'
	local f
	for f in HOP_CONFIG HOP_WORKSPACES_FILE HOP_HISTFILE; do
		local p=${(P)f}
		printf '  %-22s %s %s\n' "$f" "$p" "$([[ -r $p ]] && print -n '(readable)' || print -n '(MISSING)')"
	done
	printf '  %-22s %s\n' HOP_DEFAULT_KINDS "$HOP_DEFAULT_KINDS"
	printf '  %-22s %s\n' HOP_VIM "${HOP_VIM:-1 (default)}"
	printf '  %-22s %s\n' HOP_HOPRC "${HOP_HOPRC:-unset, .hoprc disabled}"
	printf '  %-22s %s\n' HOP_REPOS "${HOP_REPOS:-unset, derived from workspaces}"
	printf '  %-22s %s\n' HOP_DEBUG "${HOP_DEBUG:-unset}"
	printf '  %-22s %s\n' HOP_DEBUG_LOG "$HOP_DEBUG_LOG"
	print -r -- ''

	print -r -- 'tools'
	_hop_doctor_tool zsh --version
	_hop_doctor_tool fzf --version
	_hop_doctor_tool git --version
	_hop_doctor_tool gh --version
	_hop_doctor_tool bat --version
	_hop_doctor_tool code --version
	print -r -- ''

	print -r -- 'terminal'
	printf '  %-22s %s\n' TERM "${TERM:-unset}"
	printf '  %-22s %s\n' COLUMNS "${COLUMNS:-unknown}"
	printf '  %-22s %s\n' 'completions on fpath' "$([[ -n ${fpath[(r)$HOP_HOME/completions]} ]] && print -n yes || print -n 'no, source hop.zsh before compinit')"
	print -r -- ''

	print -r -- 'where you are'
	printf '  %-22s %s\n' PWD "$PWD"
	root=$(git rev-parse --show-toplevel 2>/dev/null)
	printf '  %-22s %s\n' 'git toplevel' "${root:-NONE, so hop opens the workspace or repo picker}"
	if _hop_ws_for "$PWD"; then
		printf '  %-22s %s\n' 'workspace for PWD' "$REPLY"
	else
		printf '  %-22s %s\n' 'workspace for PWD' 'none'
	fi
	print -r -- ''

	print -r -- 'workspaces'
	if _hop_ws_parse; then
		local e
		for e in "${reply[@]}"; do
			printf '  %-22s %s\n' "${e%%$'\t'*}" "${e#*$'\t'}"
		done
	else
		print -r -- '  none configured'
	fi
	print -r -- ''

	print -r -- 'kinds, with row counts here'
	if [[ -z $root ]]; then
		print -r -- '  (not in a repo, so nothing to count)'
	else
		local k n mark
		for k in "${_HOP_ALL_KINDS[@]}"; do
			n=$(_hop_generate "$root" "$k" 2>/dev/null | grep -c .)
			if (( ${_HOP_K_DEFAULT[$k]:-0} )); then mark='*'; else mark=' '; fi
			printf '  %s %-11s %7s  %-8s %s\n' "$mark" "$k" "$n" "${_HOP_K_SHAPE[$k]:-?}" "${_HOP_K_DESC[$k]:-}"
		done
		print -r -- '  (* is in the default set)'
	fi
	print -r -- ''

	print -r -- 'keys people mix up'
	print -r -- '  l / ctrl-l    go INTO the thing under the cursor (workspace -> repos -> targets)'
	print -r -- '  h / ctrl-h    come back OUT a level'
	print -r -- '  b / ctrl-g    open on your git host, NOT navigation'
	print -r -- '  ^G / alt-g    launch hop from the shell prompt'
	print -r -- ''

	if [[ -r $HOP_DEBUG_LOG ]]; then
		print -r -- "last 15 debug lines (${HOP_DEBUG_LOG})"
		tail -15 "$HOP_DEBUG_LOG" | sed 's/^/  /'
	else
		print -r -- 'debug log'
		print -r -- '  none yet. Run: HOP_DEBUG=1 hop   then re-run hop --doctor'
	fi
	print -r -- '--- end ---'
	return 0
}
