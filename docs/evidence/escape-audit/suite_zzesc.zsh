#!/usr/bin/env zsh
# SCRATCH investigation suite for task #31 question 1, not for commit.
# - Drives the real picker under a pty and writes undecoded escape sequences in as INPUT.
# - Reports per sequence whether a verb stub fired and whether _hop_dispatch logged.

source "$HOP_TESTS/lib/pty.zsh"

if ! pty_supported; then
	skip 'zzesc: pty' 'zsh/zpty is not available'
	return 0
fi

pty_fixture_repo || return 1
pty_env || return 1
# The one pin pty_env deliberately leaves empty, and the whole point of this probe.
export HOP_DEBUG=1

typeset -g ZZ_DBG="$HOME/.local/state/hop/debug.log"

# The stubs that mean a VERB ran; bat is excluded, since that is the preview pane doing its job.
typeset -ga ZZ_VERBS=(gh pbcopy pbpaste code editor vim nvim open xclip xsel wl-copy)

# zz_verbs -> every verb-stub line this session recorded, newest last.
zz_verbs() {
	emulate -L zsh
	local log="${HOP_PTY_WORK}/calls.log"
	[[ -r $log ]] || return 0
	local -a lines=("${(@f)$(<"$log")}")
	lines=(${lines:#})
	local -a out=()
	local l n
	for l in "${lines[@]}"; do
		n=${l%%$'\t'*}
		(( ${ZZ_VERBS[(I)$n]} )) && out+=("${l//$'\t'/ }")
	done
	(( $#out )) && print -rl -- "${out[@]}"
	return 0
}

# zz_wait_exit <secs> -> 0 once the child recorded its final PWD, draining throughout.
zz_wait_exit() {
	emulate -L zsh
	local -F want=$1 spent=0
	while (( spent < want )); do
		_hop_pty_drain
		[[ -s ${HOP_PTY_PWDF:-} ]] && return 0
		sleep 0.02
		(( spent += 0.02 ))
	done
	return 1
}

# zz_probe <label> <bytes> [cmd] -> one sequence written as ONE burst, then reported.
zz_probe() {
	emulate -L zsh
	local label=$1 bytes=$2 cmd=${3:-'hop -k tg'}
	print -r -- "--- ${label}"
	rm -f -- "$ZZ_DBG"
	if ! pty_open "$cmd"; then
		print -r -- "    OPEN-FAILED err=[$(pty_err)]"
		pty_close
		return 0
	fi
	print -r -- "    before: prompt=[$(pty_get prompt)] pos=[$(pty_get pos)]"

	# One write, because a real terminal reply arrives as one burst and that is the reported case.
	zpty -w -n "$HOP_PTY_NAME" "$bytes" || print -r -- '    WRITE-FAILED'

	local exited=no
	zz_wait_exit 3 && exited=yes
	pty_settle 0.6

	local verbs dbg stderr
	verbs=$(zz_verbs)
	dbg=''
	[[ -r $ZZ_DBG ]] && dbg=$(<"$ZZ_DBG")

	print -r -- "    exited=${exited} pwd=[$(pty_pwd)]"
	print -r -- "    after:  prompt=[$(pty_get prompt)] pos=[$(pty_get pos)] query=[$(pty_get query)] state=[$(pty_get state)]"
	if [[ -n $verbs ]]; then
		print -r -- "    VERB FIRED: ${verbs//$'\n'/ ;; }"
	else
		print -r -- '    verb stubs: none'
	fi
	if [[ -n $dbg ]]; then
		print -r -- "    DEBUG LOG: ${dbg//$'\n'/ ;; }"
	else
		print -r -- '    debug log: empty, so no _hop_dispatch ran'
	fi
	stderr=$(pty_err)
	[[ -n $stderr ]] && print -r -- "    stderr: ${stderr//$'\n'/ | }"
	pty_close
	return 0
}

t 'zzesc: probes ran'

# The reported sequence, plus its BEL-terminated twin and the foreground query's reply.
zz_probe 'OSC 11 background reply, ST terminated' $'\e]11;rgb:1e1e/1e1e/1e1e\e\\'
zz_probe 'OSC 11 background reply, BEL terminated' $'\e]11;rgb:1e1e/1e1e/1e1e\a'
zz_probe 'OSC 10 foreground reply' $'\e]10;rgb:c5c5/c8c8/c6c6\e\\'

# Other replies a terminal or a stray program can inject unprompted.
zz_probe 'DA1 primary device attributes' $'\e[?1;2c'
zz_probe 'CPR cursor position report' $'\e[24;80R'
zz_probe 'DCS XTVERSION reply' $'\eP>|WezTerm 20240203\e\\'
zz_probe 'OSC 52 clipboard reply' $'\e]52;c;YmFzZTY0\e\\'

# Bracketed paste, which is the other way a letter arrives with no keypress behind it.
zz_probe 'bracketed paste wrapping letters' $'\e[200~oyb\e[201~'
zz_probe 'bracketed paste, open marker only' $'\e[200~oyb'

# Truncated, which is what a partial read of a reply looks like.
zz_probe 'OSC 11 truncated, no terminator' $'\e]11;rgb:1e1e'
zz_probe 'CSI truncated, no final byte' $'\e[?1;2'

# Controls, to prove the harness would have seen a verb if one had fired.
zz_probe 'control: bare b, a real keypress' 'b'
zz_probe 'control: bare y, a real keypress' 'y'

assert_eq 'probed' 'probed' 'placeholder so the suite reports a tally'
