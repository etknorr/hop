#!/usr/bin/env zsh
# hop pty suite: eight things that only a real keystroke on a real terminal can prove.
# - Everything checkable from the bind strings belongs in suite_keymap.zsh, not here.
# - What is left is the part SMOKE.md called unscriptable: a KEY reaching its action.
# - Each test spawns its own picker, sends one key at a time, and reads fzf's own state file.
# - Nothing asserts on rendered output: zpty cannot size the window, so the UI never paints usefully.
# - Eight is the budget. Each test costs about a second, and the rest of the run costs nine.

source "$HOP_TESTS/lib/pty.zsh"

# The gate has two halves, and the second one is what stops "skipped" becoming permanent.
# - No zsh/zpty at all is an honest skip: the module is a build option.
# - zpty present but a keystroke not arriving is a BROKEN RUNNER, and under $CI that must be red.
if ! pty_supported; then
	skip 'pty: canary reaches fzf with one keystroke' 'zsh/zpty is not available'
	skip 'pty: j moves the cursor in NORMAL' 'zsh/zpty is not available'
	skip 'pty: o fires the open verb on the focused row' 'zsh/zpty is not available'
	skip 'pty: enter cds to the focused row' 'zsh/zpty is not available'
	skip 'pty: / enters SEARCH and letters type' 'zsh/zpty is not available'
	skip 'pty: esc returns to NORMAL and clears the query' 'zsh/zpty is not available'
	skip 'pty: j moves again after the SEARCH round trip' 'zsh/zpty is not available'
	skip 'pty: the : view menu comes back with esc' 'zsh/zpty is not available'
	return 0
fi

pty_fixture_repo || return 1
pty_env || return 1

typeset -i PTY_OK=0
pty_canary && PTY_OK=1

if (( ! PTY_OK )) && [[ -z ${CI:-} ]]; then
	skip 'pty: canary reaches fzf with one keystroke' 'no pty capability on this machine'
	skip 'pty: j moves the cursor in NORMAL' 'no pty capability on this machine'
	skip 'pty: o fires the open verb on the focused row' 'no pty capability on this machine'
	skip 'pty: enter cds to the focused row' 'no pty capability on this machine'
	skip 'pty: / enters SEARCH and letters type' 'no pty capability on this machine'
	skip 'pty: esc returns to NORMAL and clears the query' 'no pty capability on this machine'
	skip 'pty: j moves again after the SEARCH round trip' 'no pty capability on this machine'
	skip 'pty: the : view menu comes back with esc' 'no pty capability on this machine'
	return 0
fi

# ---------------------------------------------------------------------------
# 1. The gate, asserted rather than merely consulted.
# ---------------------------------------------------------------------------
# print(key)+accept is the exact mechanism every NORMAL-mode letter verb rides.
t 'pty: canary reaches fzf with one keystroke'
assert_eq 'ctrl-o' "$HOP_PTY_CANARY" 'the canary keystroke did not come back out of fzf'

# A red canary under $CI means the runner lost pty capability, which must never pass quietly.
if (( ! PTY_OK )); then
	return 0
fi

# ---------------------------------------------------------------------------
# 2. A keystroke reaching a navigation action.
# ---------------------------------------------------------------------------
# fzf exports FZF_POS, so the cursor's row is readable without looking at the screen at all.
t 'pty: j moves the cursor in NORMAL'
if pty_open 'hop -k tg'; then
	assert_eq '1' "$(pty_get pos)" 'the picker did not start on row 1'
	assert_eq '> ' "$(pty_get prompt)" 'the picker did not start in NORMAL'
	pty_key_ev j
	assert_eq '2' "$(pty_get pos)" 'j did not move the cursor down one row'
	pty_key_ev j
	assert_eq '3' "$(pty_get pos)" 'a second j did not move the cursor again'
	pty_key_ev k
	assert_eq '2' "$(pty_get pos)" 'k did not move the cursor back up'
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ---------------------------------------------------------------------------
# 3. A keystroke reaching a real verb, all the way into the process it shells out to.
# ---------------------------------------------------------------------------
# The path is key -> print(ctrl-o)+accept -> _hop_dispatch -> _hop_act_open -> code.
# - It doubles as proof that the PATH stubs genuinely intercept, since `code` here is a stub.
t 'pty: o fires the open verb on the focused row'
if pty_open 'hop -k tg'; then
	pty_key_ev j
	pty_key o
	if pty_wait_exit; then
		assert_eq "code	-r	$(pty_row 2)/terragrunt.hcl" "$(pty_calls code)" \
			'o did not open the row j had moved to'
		assert_eq "$HOP_PTY_REPO" "$(pty_pwd)" 'a side-effect verb must leave the shell where it was'
	else
		_hop_t_bad 'o never made the picker exit' "$(pty_trace)"
	fi
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ---------------------------------------------------------------------------
# 4. Enter, which is the only verb allowed to move the shell.
# ---------------------------------------------------------------------------
t 'pty: enter cds to the focused row'
if pty_open 'hop -k tg'; then
	pty_key enter
	if pty_wait_exit; then
		assert_eq "$(pty_row 1)" "$(pty_pwd)" 'enter did not cd to the first row'
		# Only the verbs, never the whole log: `bat` in it is the PREVIEW pane doing its job.
		assert_empty "$(pty_calls code)" 'enter opened an editor as well as cd-ing'
		assert_empty "$(pty_calls gh)" 'enter reached the browse verb'
	else
		_hop_t_bad 'enter never made the picker exit' "$(pty_trace)"
	fi
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ---------------------------------------------------------------------------
# 5. The mode boundary, in the direction that unbinds ~100 keys.
# ---------------------------------------------------------------------------
# b and r are both NORMAL verbs (gh browse, refresh), so them TYPING is the proof of the unbind.
t 'pty: / enters SEARCH and letters type'
if pty_open 'hop -k tg'; then
	pty_key_ev '/'
	assert_eq '/ ' "$(pty_get prompt)" '/ did not switch the prompt to SEARCH'
	pty_key_ev b
	pty_key_ev r
	assert_eq 'br' "$(pty_get query)" 'b and r acted as verbs instead of typing'
	assert_eq 'enabled' "$(pty_get state)" 'SEARCH left filtering switched off'
	assert_empty "$(pty_calls gh)" 'b typed and fired gh browse as well'
	assert_empty "$(pty_calls code)" 'a letter in SEARCH reached a verb'
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ---------------------------------------------------------------------------
# 6. The mode boundary, back.
# ---------------------------------------------------------------------------
# esc has three meanings, resolved inside fzf from $FZF_PROMPT and $FZF_INPUT_STATE alone.
# - Getting NORMAL's state back is what makes the NEXT esc quit instead of looping here.
t 'pty: esc returns to NORMAL and clears the query'
if pty_open 'hop -k tg'; then
	pty_key_ev '/'
	pty_key_ev b
	pty_key_ev r
	pty_key_ev esc
	assert_eq '> ' "$(pty_get prompt)" 'esc did not restore the NORMAL prompt'
	assert_eq '' "$(pty_get query)" 'esc left the query in place'
	assert_eq 'disabled' "$(pty_get state)" 'esc left filtering on, so the next esc would not quit'
	assert_empty "$(pty_pwd)" 'esc quit the picker instead of returning to NORMAL'
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ---------------------------------------------------------------------------
# 7. The unbind/rebind round trip, which SMOKE.md calls the whole restore.
# ---------------------------------------------------------------------------
# Query `a` matches all four scopes, so the list is still intact on the way back out.
# - A narrower query exposes a SEPARATE bug: disable-search never re-filters the frozen match set.
t 'pty: j moves again after the SEARCH round trip'
if pty_open 'hop -k tg'; then
	pty_key_ev '/'
	pty_key_ev a
	pty_key_ev esc
	assert_eq '1' "$(pty_get pos)" 'the round trip did not leave the cursor on row 1'
	pty_key_ev j
	assert_eq '2' "$(pty_get pos)" 'j typed instead of moving: the rebind did not restore it'
	assert_eq '' "$(pty_get query)" 'j reached the query, so it was never rebound'
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ---------------------------------------------------------------------------
# 8. The `:` view menu, and esc regenerating the list you came from.
# ---------------------------------------------------------------------------
# Enter means "switch view" in the menu and "cd" everywhere else, so a cd afterwards is the proof.
t 'pty: the : view menu comes back with esc'
if pty_open 'hop -k tg'; then
	pty_key_ev ':'
	assert_eq ': ' "$(pty_get prompt)" ': did not open the view menu'
	pty_key_ev esc
	assert_eq '> ' "$(pty_get prompt)" 'esc did not come back out of the view menu'
	pty_key enter
	if pty_wait_exit; then
		assert_eq "$(pty_row 1)" "$(pty_pwd)" 'enter after the menu round trip did not cd to row 1'
	else
		_hop_t_bad 'enter never made the picker exit' "$(pty_trace)"
	fi
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close
