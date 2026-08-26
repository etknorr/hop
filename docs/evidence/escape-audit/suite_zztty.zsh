#!/usr/bin/env zsh
# SCRATCH investigation suite for task #31 question 2, not for commit.
# - A zpty child is a pty with a controlling terminal, so it stands in for a tmux pane or ssh -t.
# - Each case reports whether the proposed guard would pass AND whether the picker still works.

source "$HOP_TESTS/lib/pty.zsh"

if ! pty_supported; then
	skip 'zztty: pty' 'zsh/zpty is not available'
	return 0
fi

pty_fixture_repo || return 1
pty_env || return 1

# zz_guard <fd-shape> -> the guard's own expression, then hop with that shape, in one child.
typeset -g ZZ_GUARD='{ : < /dev/tty } 2>/dev/null && print -ru2 -- GUARD=OPENABLE || print -ru2 -- GUARD=CLOSED'

zz_case() {
	emulate -L zsh
	local label=$1 cmd=$2 key=$3
	print -r -- "--- ${label}"
	if ! pty_open "${ZZ_GUARD}; ${cmd}"; then
		print -r -- "    OPEN-FAILED err=[$(pty_err)]"
		pty_close
		return 0
	fi
	print -r -- "    picker opened: prompt=[$(pty_get prompt)] pos=[$(pty_get pos)] count=[$(pty_get count)]"
	pty_key "$key"
	if pty_wait_exit; then
		print -r -- "    ${key} landed. pwd=[$(pty_pwd)]"
	else
		print -r -- "    ${key} did NOT make the picker exit. trace=[$(pty_last)]"
	fi
	local calls
	calls=$(pty_calls code)
	[[ -n $calls ]] && print -r -- "    code stub: ${calls//$'\t'/ }"
	print -r -- "    child stderr: $(pty_err)"
	pty_close
	return 0
}

t 'zztty: cases ran'

print -r -- "row 1 is ${$(pty_row 1):t:h}"
zz_case 'hop with stdin from /dev/null, enter'  'hop -k tg < /dev/null' enter
zz_case 'hop with stdin closed (0<&-), enter'   'hop -k tg 0<&-'        enter
zz_case 'hop with stdin from a pipe, enter'     'print -r -- x | hop -k tg' enter
zz_case 'hop with stdout piped to cat, o'       'hop -k tg | cat'       o
zz_case 'hop unredirected, enter (control)'     'hop -k tg'             enter

assert_eq 'probed' 'probed' 'placeholder so the suite reports a tally'
