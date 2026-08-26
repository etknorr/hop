#!/usr/bin/env zsh
# suite_pty_escape: bytes the TERMINAL emits, driven into the real picker as INPUT.
# - fzf does not decode every inbound escape sequence, and what it cannot parse arrives as keystrokes.
# - So a colour-query reply printed by any program could run a hop verb with nobody touching a key.
# - Every case here was reproduced under a pty before it was fixed, never inferred from the bind table.
# - The log line each negative hunts is `dispatch key=`, which only HOP_DEBUG=1 writes.
# - Separate from suite_pty.zsh, whose header declares an explicit eight-test budget.
# - Nothing asserts on the screen: zpty cannot size the window, so the UI never paints usefully.

source "$HOP_TESTS/lib/pty.zsh"

# Every test name in one list, so the skip block can never drift from the tests themselves.
typeset -ga ESC_NAMES=(
	'pty-esc: a bare BEL byte reaches no verb'
	'pty-esc: a real b still browses, so the negatives are not vacuous'
	'pty-esc: a real y still copies, so the negatives are not vacuous'
)

# esc_skip_all <why> -> skip every test this suite owns, with one reason.
esc_skip_all() {
	emulate -L zsh
	local n
	for n in "${ESC_NAMES[@]}"; do
		skip "$n" "$1"
	done
}

if ! pty_supported; then
	esc_skip_all 'zsh/zpty is not available'
	return 0
fi

pty_fixture_repo || return 1
pty_env || return 1

# The one pin pty_env deliberately leaves empty, and the whole mechanism every negative below reads.
export HOP_DEBUG=1
typeset -g ESC_DBG="$HOME/.local/state/hop/debug.log"

# A hard override, so the copy control names the same binary on macOS and on a Linux runner.
# - Left to hop's own probe it is pbcopy here and wl-copy or xclip there, which no exact assert survives.
export HOP_CLIPBOARD=pbcopy

# Losing pty capability is suite_pty.zsh's canary to report, and it turns CI red on its own.
# - Duplicating that assertion here would give one broken runner nine red tests for one cause.
if ! pty_canary; then
	esc_skip_all 'no pty capability on this machine'
	return 0
fi

# The verb binaries; bat is deliberately absent, since bat running IS the preview pane doing its job.
typeset -ga ESC_VERB_BINS=(gh pbcopy pbpaste code editor vim nvim open xclip xsel wl-copy)

typeset -g ESC_DISPATCH='' ESC_FIRED='' ESC_ALIVE='' ESC_POS=''

# esc_open -> a fresh picker on the tg view, with the debug log cleared first.
esc_open() {
	emulate -L zsh
	rm -f -- "$ESC_DBG"
	pty_open 'hop -k tg'
}

# esc_key -> the key _hop_dispatch logged, or empty when no dispatch ran at all.
# - Every pick logs a `pick label=` line whether or not a verb followed, so only `dispatch` counts.
esc_key() {
	emulate -L zsh
	[[ -r $ESC_DBG ]] || return 0
	local -a lines=("${(@f)$(<"$ESC_DBG")}")
	lines=(${(M)lines:#*dispatch key=*})
	(( $#lines )) || return 0
	print -rn -- "${${lines[-1]#*dispatch key=}%% *}"
}

# esc_verbs -> a comma list of the verb binaries this session actually ran, newest last.
esc_verbs() {
	emulate -L zsh
	local -a all=("${(@f)$(pty_calls)}")
	all=(${all:#})
	local -a out=()
	local l n
	for l in "${all[@]}"; do
		n=${l%%$'\t'*}
		(( ${ESC_VERB_BINS[(I)$n]} )) && out+=("$n")
	done
	print -rn -- "${(j:,:)out}"
}

# esc_case <bytes> -> drive one sequence in as a single write, then describe what it did.
# - ONE write, because a real terminal reply arrives as one burst and that is the reported case.
# - ESC_ALIVE is empty while the picker is still up, so a non-empty value means the burst accepted.
# - The `j` afterwards is the anti-vacuum half: a picker that died or wedged would also report no verb.
# - It proves the keystroke channel still works AND that no half-read escape state is left pending.
esc_case() {
	emulate -L zsh
	ESC_DISPATCH='' ESC_FIRED='' ESC_ALIVE='' ESC_POS=''
	esc_open || return 1
	if ! zpty -w -n "$HOP_PTY_NAME" "$1"; then
		pty_close
		return 1
	fi
	pty_quiesce
	ESC_DISPATCH=$(esc_key)
	ESC_FIRED=$(esc_verbs)
	ESC_ALIVE=$(pty_pwd)
	pty_key_ev j
	ESC_POS=$(pty_get pos)
	pty_close
	return 0
}

# esc_assert_inert <what> -> the four things every suppressed sequence must be true of at once.
esc_assert_inert() {
	emulate -L zsh
	local what=$1
	assert_empty "$ESC_DISPATCH" "${what} dispatched a verb"
	assert_empty "$ESC_FIRED" "${what} reached a verb binary"
	assert_empty "$ESC_ALIVE" "${what} made the picker accept and exit"
	assert_eq '2' "$ESC_POS" "the picker stopped taking keys after ${what}"
}

# ---------------------------------------------------------------------------
# The control-byte class, which no keymap change alone could have reached.
# ---------------------------------------------------------------------------
# A bare BEL (0x07) came back out of fzf as ctrl-g, and --expect made that the browse verb.
# - --expect is passed unconditionally, so HOP_VIM=0 and --no-vim did not protect against it either.
t 'pty-esc: a bare BEL byte reaches no verb'
if esc_case $'\a'; then
	esc_assert_inert 'a bare BEL byte'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi

# ---------------------------------------------------------------------------
# The positive controls, without which every negative above proves nothing.
# ---------------------------------------------------------------------------
# b is the browse verb, and browse is the exact verb the BEL case used to reach.
t 'pty-esc: a real b still browses, so the negatives are not vacuous'
if esc_open; then
	pty_key b
	if pty_wait_exit; then
		assert_eq 'ctrl-g' "$(esc_key)" 'a real b no longer dispatches the browse verb'
		assert_eq 'gh' "$(esc_verbs)" 'a real b no longer reaches the gh binary'
	else
		_hop_t_bad 'b never made the picker exit' "$(pty_trace)"
	fi
else
	_hop_t_bad 'esc_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# y is the copy verb, whose stub is the one an OSC 52 reply used to clobber the real clipboard through.
t 'pty-esc: a real y still copies, so the negatives are not vacuous'
if esc_open; then
	pty_key y
	if pty_wait_exit; then
		assert_eq 'ctrl-y' "$(esc_key)" 'a real y no longer dispatches the copy verb'
		assert_eq 'pbcopy' "$(esc_verbs)" 'a real y no longer reaches the clipboard binary'
	else
		_hop_t_bad 'y never made the picker exit' "$(pty_trace)"
	fi
else
	_hop_t_bad 'esc_open: the picker never reported ready' "$(pty_err)"
fi
pty_close
