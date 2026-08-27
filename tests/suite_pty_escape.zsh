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
	'pty-esc: an OSC 11 background-colour reply reaches no verb'
	'pty-esc: the same OSC 11 reply BEL-terminated reaches no verb'
	'pty-esc: a truncated OSC 11 reply reaches no verb'
	'pty-esc: an OSC 10 foreground-colour reply reaches no verb'
	'pty-esc: an OSC 52 clipboard reply reaches no verb'
	'pty-esc: a DCS version reply reaches no verb'
	'pty-esc: a long APC payload cannot outlast the guard'
	'pty-esc: a real b still browses, so the negatives are not vacuous'
	'pty-esc: a real y still copies, so the negatives are not vacuous'
	'pty-esc: with the guard off, the same reply DOES reach the browse verb'
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

# The guard times a verb against the PREVIOUS check's clock reading, so its discriminator is its own fork.
# - At loadavg 35 that fork measured 425ms mean, which is past the shipped 0.15 threshold.
# - A check that slow reads as a real keypress and fails open, so the forged payload runs a verb.
# - Reproduced here 3 times in 4 under 24-way load, dispatching ctrl-o and reaching the code stub.
# - So the shipped default cannot hold these negatives green, and no retry count would change that.
# - Pinning the window past any plausible fork latency keeps every link they exist to prove intact.
# - Those links are: introducer, bindable alt-key, mark written, verb consults the guard, verb refused.
# - What the pin removes is failure caused by a slow fork, which is not why any case below was written.
# - It does NOT claim the shipped 0.15 is adequate under load; bin/hop-guard now records that it is not.
# - 300s, because the worst check fork measured 5.5s at loadavg 35 and the pin has to clear that outright.
# - Nothing leaks between cases: lib/ui.zsh mktemp -d's the mark dir per picker under an EXIT trap.
export HOP_GUARD_WINDOW=300

# Losing pty capability is suite_pty.zsh's canary to report, and it turns CI red on its own.
# - Duplicating that assertion here would give one broken runner nine red tests for one cause.
if ! pty_canary; then
	esc_skip_all 'no pty capability on this machine'
	return 0
fi

# The verb binaries; bat is deliberately absent, since bat running IS the preview pane doing its job.
typeset -ga ESC_VERB_BINS=(gh pbcopy pbpaste code editor vim nvim open xclip xsel wl-copy)

# Every stub pty.zsh installs, which is the verb list plus the one the preview pane runs.
# - esc_log_corrupt needs the FULL set, because a line naming bat is legitimate and only a garbled one is not.
typeset -ga ESC_STUB_BINS=("${ESC_VERB_BINS[@]}" bat)

# Dropping the bat stub leaves calls.log with exactly ONE writer, which is what makes the log trustworthy.
# - Each stub USED TO append its name, then every argument, then the newline, as 2+N separate appends.
# - The preview pane runs bat on every render, so a second stub was writing throughout every session.
# - Measured: a bat call landed between gh's appends and recorded `batgh<TAB>browse<TAB>--<TAB>...`.
# - esc_verbs matches the first tab field only, so that read as "gh never ran" with an empty stderr.
# - It cost a real b control a red 1 run in 25 under load, blaming the guard for a logging race.
# - bin/hop-preview gates on `bat` being on PATH, so removing it falls through to the cat/head path.
# - That path is what this machine already uses, and no case here asserts the preview pane's contents.
# - HOP_PTY_SHARED is per-process and pty_env has already built it, so this cannot reach another suite.
# - The cost is a coupling to pty.zsh's stub layout, which this suite already has by knowing bat is a stub.
# - The stub's multi-append write was the underlying bug, and it is fixed in tests/lib/pty.zsh, not here.
# - Dropping bat is kept even so: one writer is what makes this suite's log trustworthy by construction.
rm -f -- "$HOP_PTY_SHARED/bat"

typeset -g ESC_DISPATCH='' ESC_FIRED='' ESC_ALIVE=''

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
		(( ${ESC_VERB_BINS[(Ie)$n]} )) && out+=("$n")
	done
	print -rn -- "${(j:,:)out}"
}

# esc_log_corrupt -> the calls.log lines no single stub could have written, joined for a message.
# - Dropping the bat stub above removed the only concurrent writer this suite currently has.
# - It stays as the tripwire for a future second writer, now that the multi-append write itself is fixed.
# - Without it a second writer would return silently to blaming the guard for an empty verb list.
# - Proven reachable: 60 concurrent stub calls produced `batbat<TAB>...` and a line starting with a tab.
esc_log_corrupt() {
	emulate -L zsh
	local -a all=("${(@f)$(pty_calls)}")
	all=(${all:#})
	local -a bad=()
	local l n
	for l in "${all[@]}"; do
		n=${l%%$'\t'*}
		[[ -n $n ]] && (( ${ESC_STUB_BINS[(Ie)$n]} )) && continue
		bad+=("$l")
	done
	print -rn -- "${(j: | :)bad}"
}

# esc_case <bytes> -> drive one sequence in as a single write, then describe what it did.
# - ONE write, because a real terminal reply arrives as one burst and that is the reported case.
# - ESC_ALIVE is empty while the picker is still up, so a non-empty value means the burst accepted.
# - It asserts NOTHING about the cursor row or the mode, and that is a deliberate line, not laziness.
# - j/k/g/G stay unguarded so they stay fork-free, and / and : stay unguarded because esc undoes them.
# - So a payload legitimately moves the cursor and switches mode: `\e]11;rgb:...` carries g, : and three /.
# - Three separate attempts to pin those effects each asserted the payload instead of the fix.
esc_case() {
	emulate -L zsh
	ESC_DISPATCH='' ESC_FIRED='' ESC_ALIVE=''
	esc_open || return 1
	if ! zpty -w -n "$HOP_PTY_NAME" "$1"; then
		pty_close
		return 1
	fi
	pty_quiesce
	ESC_DISPATCH=$(esc_key)
	ESC_FIRED=$(esc_verbs)
	ESC_ALIVE=$(pty_pwd)
	pty_close
	return 0
}

# esc_assert_inert <what> -> the three things every suppressed sequence must be true of at once.
# - Two independent things stop these from being vacuous, and neither is inside this function.
# - esc_case returns non-zero unless pty_open saw a focus event, so the picker demonstrably started.
# - The bare-b and bare-y controls below prove this same harness still sees a verb when one runs.
esc_assert_inert() {
	emulate -L zsh
	local what=$1
	assert_empty "$ESC_DISPATCH" "${what} dispatched a verb"
	assert_empty "$ESC_FIRED" "${what} reached a verb binary"
	assert_empty "$ESC_ALIVE" "${what} made the picker accept and exit"
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
# The string-payload escape classes, one test each, every one reproduced before it was fixed.
# ---------------------------------------------------------------------------
# fzf consumes CSI correctly, so DA1 and CPR were never a problem and are not tested here.
# - What leaks is the introducers that carry a STRING payload: OSC, DCS, APC, PM and SOS.
# - fzf surfaces the unparsed introducer as alt-<char>, and that is the only hook the guard needs.

# The reported sequence. `1e1e` alone holds the `e` verb, and `rgb` holds `b`.
t 'pty-esc: an OSC 11 background-colour reply reaches no verb'
if esc_case $'\e]11;rgb:1e1e/1e1e/1e1e\e\\'; then
	esc_assert_inert 'an OSC 11 reply'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi

# BEL is the other legal OSC terminator, and it is ALSO ctrl-g, so this covers both fixes at once.
t 'pty-esc: the same OSC 11 reply BEL-terminated reaches no verb'
if esc_case $'\e]11;rgb:1e1e/1e1e/1e1e\a'; then
	esc_assert_inert 'a BEL-terminated OSC 11 reply'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi

# What a partial read of a reply looks like, which is the shape with no terminator to lean on.
t 'pty-esc: a truncated OSC 11 reply reaches no verb'
if esc_case $'\e]11;rgb:1e1e'; then
	esc_assert_inert 'a truncated OSC 11 reply'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi

t 'pty-esc: an OSC 10 foreground-colour reply reaches no verb'
if esc_case $'\e]10;rgb:c5c5/c8c8/c6c6\e\\'; then
	esc_assert_inert 'an OSC 10 reply'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi

# This one used to clobber the real clipboard, because `Y` in the payload is the copy-file verb.
t 'pty-esc: an OSC 52 clipboard reply reaches no verb'
if esc_case $'\e]52;c;YmFzZTY0\e\\'; then
	esc_assert_inert 'an OSC 52 clipboard reply'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi

# XTVERSION, which every modern terminal answers, and whose payload holds the `e` verb.
t 'pty-esc: a DCS version reply reaches no verb'
if esc_case $'\eP>|WezTerm 20240203\e\\'; then
	esc_assert_inert 'a DCS version reply'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi

# The case that made the guard re-arm on every refusal rather than trust one mark.
# - A kitty graphics APC carries kilobytes of base64, so a long payload is not hypothetical.
# - Measured: letters arrive ~20ms apart, so timing from the introducer alone breaks through at letter 8.
# - This body is four verbs repeated, so it is 64 separate attempts to run one.
# - Disclosure: with the window pinned above, timing from the introducer alone would pass this too.
# - So this case no longer discriminates re-arm, and pretending otherwise would be the vacuous kind of green.
# - suite_guard's 'a refused verb pushes the window forward' is where re-arm is pinned instead.
# - That test compares the mark before and after a refusal, which is exact and needs no pty.
# - Its window is pinned there too, because its refusal step used to run on the load-sensitive default.
# - What this case still proves is that a 64-letter payload reaches no verb through the real picker.
t 'pty-esc: a long APC payload cannot outlast the guard'
if esc_case $'\e_G'"${(l:64::obey:)}"$'\e\\'; then
	esc_assert_inert 'a long APC payload'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi

# ---------------------------------------------------------------------------
# The positive controls, without which every negative above proves nothing.
# ---------------------------------------------------------------------------
# Both controls send a bare letter, and a plain letter never marks, so only an alt-<char> arms the guard.
# - lib/ui.zsh mktemp -d's the mark dir per picker under an EXIT trap, so a fresh picker has no mark at all.
# - That is what rules out a mark left behind by one of the negatives above, which the pin would prolong.
# - With no mark file to read, `check` fails open at ANY window, so the pin above cannot suppress these.
# - That makes the pin part of the claim rather than a caveat on it: an unmarked key fires regardless.
# - hop's stderr is reported on failure, because a verb can bail AFTER dispatch has logged the key.
# - `dispatch key=` is written before the verb runs, so the first assert passing proves nothing about the second.

# b is the browse verb, and browse is the exact verb the BEL case used to reach.
t 'pty-esc: a real b still browses, so the negatives are not vacuous'
if esc_open; then
	pty_key b
	if pty_wait_exit; then
		typeset esc_bwhy="$(pty_err)" esc_bbad="$(esc_log_corrupt)"
		assert_eq 'ctrl-g' "$(esc_key)" "a real b no longer dispatches the browse verb; hop said: ${esc_bwhy}"
		assert_eq 'gh' "$(esc_verbs)" "a real b no longer reaches the gh binary; hop said: ${esc_bwhy}; interleaved log lines: ${esc_bbad}"
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
		typeset esc_ywhy="$(pty_err)" esc_ybad="$(esc_log_corrupt)"
		assert_eq 'ctrl-y' "$(esc_key)" "a real y no longer dispatches the copy verb; hop said: ${esc_ywhy}"
		assert_eq 'pbcopy' "$(esc_verbs)" "a real y no longer reaches the clipboard binary; hop said: ${esc_ywhy}; interleaved log lines: ${esc_ybad}"
	else
		_hop_t_bad 'y never made the picker exit' "$(pty_trace)"
	fi
else
	_hop_t_bad 'esc_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ---------------------------------------------------------------------------
# The characterization test: the reported bug, reproduced on demand.
# ---------------------------------------------------------------------------
# HOP_GUARD_WINDOW=0 is the product's own off switch, so this drives the ORIGINAL behaviour.
# - It is what permanently pins non-vacuity for every negative above, in one picker session.
# - Without it, a change that stopped the payload reaching fzf at all would turn them ALL green.
# - Exact values on all three, because that is the whole point of reproducing rather than asserting.
t 'pty-esc: with the guard off, the same reply DOES reach the browse verb'
export HOP_GUARD_WINDOW=0
if esc_case $'\e]11;rgb:1e1e/1e1e/1e1e\e\\'; then
	assert_eq 'ctrl-g' "$ESC_DISPATCH" 'the harness no longer sees the leak the guard exists to stop'
	assert_eq 'gh' "$ESC_FIRED" 'the harness no longer sees the verb binary run'
	assert_nonempty "$ESC_ALIVE" 'the payload no longer makes the picker accept and exit'
else
	_hop_t_bad 'esc_case: the picker never reported ready' "$(pty_err)"
fi
# Back to this suite's pin, not to empty, so nothing after this point runs on the load-sensitive default.
export HOP_GUARD_WINDOW=300
