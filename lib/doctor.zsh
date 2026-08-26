#!/usr/bin/env zsh
# hop --doctor: everything needed to diagnose a report, in one paste-able block.
# - Interactive fzf cannot be captured, so the shell's STATE is the next best evidence.
# - Ordered by how often it turns out to be the cause, not alphabetically.
# - Full mode prints paths, workspace names and kind names: read it before pasting anywhere public.
# - `--doctor=short` is the paste-safe mode: counts and shapes instead of paths and names.

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
	# The redirect binds to "$name", not to head: after the pipe it fixes nothing and still hangs.
	v=$("$name" "$@" </dev/null 2>&1 | head -1)
	printf '  %-8s %s\n' "$name" "${v:-present}"
}

# _hop_doctor_path <label> <var> <default> -> one aligned line, the value shown only if default.
# - A path that was never customised carries nothing personal, so it is fine to print as-is.
# - A path someone pointed somewhere else could name anything, so short mode withholds it.
_hop_doctor_path() {
	emulate -L zsh
	local label=$1 var=$2 default=$3 short=${4:-0}
	local val=${(P)var}
	local shown=$val
	if (( short )); then
		[[ $val == "$default" ]] || shown='(customised, withheld)'
	fi
	printf '  %-22s %s %s\n' "$label" "$shown" "$([[ -r $val ]] && print -n '(readable)' || print -n '(MISSING)')"
}

_hop_doctor_body() {
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
	_hop_doctor_path HOP_CONFIG HOP_CONFIG "${XDG_CONFIG_HOME:-$HOME/.config}/hop/config.zsh"
	_hop_doctor_path HOP_WORKSPACES_FILE HOP_WORKSPACES_FILE "${XDG_CONFIG_HOME:-$HOME/.config}/hop/workspaces"
	_hop_doctor_path HOP_HISTFILE HOP_HISTFILE "${XDG_STATE_HOME:-$HOME/.local/state}/hop/history"
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

# _hop_doctor -> the full local-diagnostic view. Contains paths, workspace names and kind names.
# - $HOME is collapsed to ~ throughout: there is no reason to print the absolute home directory
#   even for a view that never leaves this machine.
_hop_doctor() {
	emulate -L zsh
	local body
	body=$(_hop_doctor_body)
	print -r -- "${body//${(b)HOME}/~}"
	return 0
}

# _hop_doctor_short_body -> the paste-safe view for a public bug report, $HOME still literal.
# - OMITS ENTIRELY: PWD, git toplevel, the workspaces table, and every kind NAME.
# - REPLACES with counts: how many workspaces, how many kinds and their shape histogram.
# - A path is shown only when it is still the shipped default; anything customised is withheld,
#   because a customised path is free text and free text is exactly what this mode exists to hide.
# - $HOME collapse happens once, in the wrapper below, the same way _hop_doctor does it.
_hop_doctor_short_body() {
	emulate -L zsh
	setopt local_options no_nomatch
	local REPLY
	local -a reply

	print -r -- '--- hop --doctor=short (paste-safe: paths and names withheld) ---'
	print -r -- ''

	print -r -- 'install'
	printf '  %-22s %s\n' HOP_HOME "$HOP_HOME"
	local ver
	ver=$(git -C "$HOP_HOME" describe --tags --always --dirty 2>/dev/null) || ver='not a git checkout'
	printf '  %-22s %s\n' version "$ver"
	printf '  %-22s %s\n' 'entry point' "$HOP_HOME/hop.zsh"
	print -r -- ''

	print -r -- 'config'
	_hop_doctor_path HOP_CONFIG HOP_CONFIG "${XDG_CONFIG_HOME:-$HOME/.config}/hop/config.zsh" 1
	_hop_doctor_path HOP_WORKSPACES_FILE HOP_WORKSPACES_FILE "${XDG_CONFIG_HOME:-$HOME/.config}/hop/workspaces" 1
	_hop_doctor_path HOP_HISTFILE HOP_HISTFILE "${XDG_STATE_HOME:-$HOME/.local/state}/hop/history" 1
	printf '  %-22s %s\n' HOP_DEFAULT_KINDS "$([[ -n ${HOP_DEFAULT_KINDS:-} ]] && print -n "set (${#${(z)HOP_DEFAULT_KINDS}} kinds)" || print -n unset)"
	printf '  %-22s %s\n' HOP_VIM "${HOP_VIM:-1 (default)}"
	printf '  %-22s %s\n' HOP_HOPRC "${HOP_HOPRC:-unset, .hoprc disabled}"
	printf '  %-22s %s\n' HOP_REPOS "$([[ -n ${HOP_REPOS:-} ]] && print -n "set (${#${(s.:.)HOP_REPOS}} repos, withheld)" || print -n 'unset, derived from workspaces')"
	printf '  %-22s %s\n' HOP_DEBUG "${HOP_DEBUG:-unset}"
	_hop_doctor_path HOP_DEBUG_LOG HOP_DEBUG_LOG "${XDG_STATE_HOME:-$HOME/.local/state}/hop/debug.log" 1
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

	print -r -- 'workspaces'
	if _hop_ws_parse; then
		printf '  %-22s %d\n' configured "$#reply"
	else
		printf '  %-22s %d\n' configured 0
	fi
	print -r -- ''

	print -r -- 'kinds'
	printf '  %-22s %d\n' registered "$#_HOP_ALL_KINDS"
	local -i ndefault=0
	local k
	for k in "${_HOP_ALL_KINDS[@]}"; do
		(( ${_HOP_K_DEFAULT[$k]:-0} )) && (( ndefault++ ))
	done
	printf '  %-22s %d\n' 'in default set' "$ndefault"
	print -r -- '  by shape:'
	local -A byshape
	for k in "${_HOP_ALL_KINDS[@]}"; do
		(( byshape[${_HOP_K_SHAPE[$k]:-?}]++ ))
	done
	local shape
	for shape in dirs files marker fn; do
		printf '    %-8s %d\n' "$shape" "${byshape[$shape]:-0}"
	done
	print -r -- ''

	print -r -- 'PWD, the git toplevel, workspace names and kind names are withheld deliberately.'
	print -r -- 'This is not a bug: run plain --doctor locally if you need any of those.'
	print -r -- '--- end ---'
	return 0
}

# _hop_doctor_short -> _hop_doctor_short_body with $HOME collapsed, the same way _hop_doctor works.
# - One substitution point for both modes means a forgotten ~ collapse in either body cannot leak.
_hop_doctor_short() {
	emulate -L zsh
	local body
	body=$(_hop_doctor_short_body)
	print -r -- "${body//${(b)HOME}/~}"
	return 0
}
