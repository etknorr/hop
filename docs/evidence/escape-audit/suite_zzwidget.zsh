#!/usr/bin/env zsh
# SCRATCH investigation suite for task #31 question 1, widget half, not for commit.
# - Runs an INTERACTIVE zsh under the pty so ^G reaches the real zle widget.
# - Then writes the same undecoded sequences in and reads the stub log and the debug log.

source "$HOP_TESTS/lib/pty.zsh"

if ! pty_supported; then
	skip 'zzwidget: pty' 'zsh/zpty is not available'
	return 0
fi

pty_fixture_repo || return 1
pty_env || return 1
export HOP_DEBUG=1

typeset -g ZZ_DBG="$HOME/.local/state/hop/debug.log"
typeset -ga ZZ_VERBS=(gh pbcopy pbpaste code editor vim nvim open xclip xsel wl-copy)

# An rc file rather than typed lines, because zle in an unsized pty cannot be trusted with a long path.
typeset -g ZZ_ZDOT=''
zz_zdot() {
	emulate -L zsh
	[[ -n $ZZ_ZDOT ]] && return 0
	local REPLY
	fixture_tmpdir zzwzdot || return 1
	ZZ_ZDOT=$REPLY
	print -rl -- \
		'# scratch rc: put an interactive shell inside the fixture repo with hop loaded.' \
		'source "$HOP_HOME/hop.zsh"' \
		'builtin cd -q -- "$HOP_PTY_REPO"' \
		'print -r -- $$ > "$HOP_PTY_PIDF"' > "$ZZ_ZDOT/.zshrc"
	return 0
}

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

# zz_open -> an interactive shell under the pty, with the picker already open on ^G.
zz_open() {
	emulate -L zsh
	pty_close
	local REPLY
	_hop_pty_shared || return 1
	local shared=$REPLY
	zz_zdot || return 1
	fixture_tmpdir zzwrun || return 1
	HOP_PTY_WORK=$REPLY
	HOP_PTY_TRACE="$HOP_PTY_WORK/trace"
	HOP_PTY_ERR="$HOP_PTY_WORK/err"
	HOP_PTY_PWDF="$HOP_PTY_WORK/pwd"
	HOP_PTY_PIDF="$HOP_PTY_WORK/pid"
	: > "$HOP_PTY_TRACE"
	: > "$HOP_PTY_ERR"
	: > "$HOP_PTY_WORK/calls.log"
	export HOP_PTY_TRACE HOP_PTY_ERR HOP_PTY_PWDF HOP_PTY_PIDF HOP_PTY_REPO
	export HOP_FIX_LOG="$HOP_PTY_WORK/calls.log"
	export ZDOTDIR=$ZZ_ZDOT
	export FZF_DEFAULT_OPTS="--bind 'focus:execute-silent(${shared}/trace.sh F)'"
	FZF_DEFAULT_OPTS+=" --bind 'change:execute-silent(${shared}/trace.sh C)'"
	FZF_DEFAULT_OPTS+=" --bind 'result:execute-silent(${shared}/trace.sh R)'"

	# --no-globalrcs keeps /etc/zshrc out while still reading the scratch ZDOTDIR rc.
	zpty -b "$HOP_PTY_NAME" 'zsh --no-globalrcs -i' || return 1

	local -F spent=0
	while (( spent < HOP_PTY_WAIT )); do
		_hop_pty_drain
		[[ -s $HOP_PTY_PIDF ]] && break
		sleep 0.02
		(( spent += 0.02 ))
	done
	[[ -s $HOP_PTY_PIDF ]] || return 1
	HOP_PTY_PIDS+=("$(<"$HOP_PTY_PIDF")")
	pty_settle 0.5

	# ^G is 0x07, and -n is what keeps zpty from appending an Enter behind it.
	zpty -w -n "$HOP_PTY_NAME" $'\a' || return 1
	pty_wait_lines 1 || return 1
	return 0
}

# zz_probe <label> <bytes> -> open the widget's picker, inject one burst, report.
zz_probe() {
	emulate -L zsh
	local label=$1 bytes=$2
	print -r -- "--- widget: ${label}"
	rm -f -- "$ZZ_DBG"
	if ! zz_open; then
		print -r -- "    OPEN-FAILED trace=[$(pty_trace)] err=[$(pty_err)]"
		pty_close
		return 0
	fi
	print -r -- "    before: prompt=[$(pty_get prompt)] pos=[$(pty_get pos)]"
	zpty -w -n "$HOP_PTY_NAME" "$bytes" || print -r -- '    WRITE-FAILED'
	pty_settle 2.0

	local verbs dbg
	verbs=$(zz_verbs)
	dbg=''
	[[ -r $ZZ_DBG ]] && dbg=$(<"$ZZ_DBG")
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
	pty_close
	return 0
}

t 'zzwidget: probes ran'

zz_probe 'control: bare b, a real keypress' 'b'
zz_probe 'OSC 11 background reply, ST terminated' $'\e]11;rgb:1e1e/1e1e/1e1e\e\\'
zz_probe 'OSC 52 clipboard reply' $'\e]52;c;YmFzZTY0\e\\'
zz_probe 'DA1 primary device attributes' $'\e[?1;2c'

assert_eq 'probed' 'probed' 'placeholder so the suite reports a tally'
