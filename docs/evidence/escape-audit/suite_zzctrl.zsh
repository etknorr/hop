#!/usr/bin/env zsh
# SCRATCH investigation suite for task #31, control-byte class, not for commit.
# - A single raw control BYTE, with no escape sequence around it, sent into a live picker.
# - Run twice per byte, because the claim under test is that --expect at lib/ui.zsh:311 is
#   unconditional, so HOP_VIM=0 would not protect against this class the way it does letters.

source "$HOP_TESTS/lib/pty.zsh"

if ! pty_supported; then
	skip 'zzctrl: pty' 'zsh/zpty is not available'
	return 0
fi

pty_fixture_repo || return 1
pty_env || return 1
export HOP_DEBUG=1

typeset -g ZZ_DBG="$HOME/.local/state/hop/debug.log"
typeset -ga ZZ_VERBS=(gh pbcopy pbpaste code editor vim nvim open xclip xsel wl-copy)

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

# zz_ctrl <label> <byte> <vim> -> one raw control byte into a fresh picker, then report.
zz_ctrl() {
	emulate -L zsh
	local label=$1 byte=$2 vim=$3
	export HOP_VIM=$vim
	printf -- '--- %-22s HOP_VIM=%s\n' "$label" "$vim"
	rm -f -- "$ZZ_DBG"
	if ! pty_open 'hop -k tg'; then
		print -r -- "    OPEN-FAILED err=[$(pty_err)]"
		pty_close
		return 0
	fi
	zpty -w -n "$HOP_PTY_NAME" "$byte" || print -r -- '    WRITE-FAILED'
	local exited=no
	zz_wait_exit 2.5 && exited=yes
	pty_settle 0.4

	local verbs dbg key stderr
	verbs=$(zz_verbs)
	dbg=''
	key=''
	if [[ -r $ZZ_DBG ]]; then
		dbg=$(<"$ZZ_DBG")
		key=${${dbg#*dispatch key=}%% *}
	fi
	print -r -- "    exited=${exited} dispatch-key=[${key:-none}] verb=[${verbs//$'\n'/ ;; }]"
	stderr=$(pty_err)
	[[ -n $stderr ]] && print -r -- "    stderr: ${stderr//$'\n'/ | }"
	pty_close
	return 0
}

t 'zzctrl: probes ran'

typeset v
for v in 1 0; do
	zz_ctrl 'BEL 0x07 (ctrl-g)' $'\a'   $v
	zz_ctrl 'BS  0x08 (ctrl-h)' $'\b'   $v
	zz_ctrl 'FF  0x0c (ctrl-l)' $'\f'   $v
	zz_ctrl 'SI  0x0f (ctrl-o)' $'\x0f' $v
	zz_ctrl 'DC4 0x14 (ctrl-t)' $'\x14' $v
	zz_ctrl 'EM  0x19 (ctrl-y)' $'\x19' $v
done

assert_eq 'probed' 'probed' 'placeholder so the suite reports a tally'
