#!/usr/bin/env zsh
# hop pty suite: nine things that only a real keystroke on a real terminal can prove.
# - Everything checkable from the bind strings belongs in suite_keymap.zsh, not here.
# - What is left is the part SMOKE.md called unscriptable: a KEY reaching its action.
# - Each test spawns its own picker, sends one key at a time, and reads fzf's own state file.
# - Nothing asserts on rendered output: zpty cannot size the window, so the UI never paints usefully.
# - Nine is the budget. Each test costs about a second, and the rest of the run costs nine.

source "$HOP_TESTS/lib/pty.zsh"

# The gate has two halves, and the second one is what stops "skipped" becoming permanent.
# - No zsh/zpty at all is an honest skip: the module is a build option.
# - zpty present but a keystroke not arriving is a BROKEN RUNNER, and under $CI that must be red.
if ! pty_supported; then
	skip 'pty: canary reaches fzf with one keystroke' 'zsh/zpty is not available'
	skip 'pty: j moves the cursor in NORMAL' 'zsh/zpty is not available'
	skip 'pty: o fires the open verb on the focused row' 'zsh/zpty is not available'
	skip 'pty: o on a dir-preview row opens a new window, never code -r' 'zsh/zpty is not available'
	skip 'pty: enter cds to the focused row' 'zsh/zpty is not available'
	skip 'pty: / enters SEARCH and letters type' 'zsh/zpty is not available'
	skip 'pty: esc returns to NORMAL and keeps the filter' 'zsh/zpty is not available'
	skip 'pty: a query matching nothing survives two escs' 'zsh/zpty is not available'
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
	skip 'pty: o on a dir-preview row opens a new window, never code -r' 'no pty capability on this machine'
	skip 'pty: enter cds to the focused row' 'no pty capability on this machine'
	skip 'pty: / enters SEARCH and letters type' 'no pty capability on this machine'
	skip 'pty: esc returns to NORMAL and keeps the filter' 'no pty capability on this machine'
	skip 'pty: a query matching nothing survives two escs' 'no pty capability on this machine'
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

# A dir kind row with no README previews the dir itself, and `code -r <dir>` reloads the focused window onto it.
# - Row 2 is terraform/, which holds no file at its top, so its preview is the dir.
t 'pty: o on a dir-preview row opens a new window, never code -r'
if pty_open 'hop -k dir'; then
	pty_key_ev j
	pty_key o
	if pty_wait_exit; then
		assert_eq "code	-n	${HOP_PTY_REPO}/terraform" "$(pty_calls code)" \
			'a dir preview must reach code as -n'
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
# esc out of SEARCH keeps the query, so NORMAL walks the filtered rows rather than the whole list.
# - `a/` matches alpha and delta only, so a count of 2 is the filter still applying in NORMAL.
# - The prompt change fires no fzf event, so j is what makes the trace report the NORMAL state.
t 'pty: esc returns to NORMAL and keeps the filter'
if pty_open 'hop -k tg'; then
	pty_key_ev '/'
	pty_key_ev a
	pty_key_ev '/'
	pty_key esc
	pty_key_ev j
	assert_eq '> ' "$(pty_get prompt)" 'esc did not restore the NORMAL prompt'
	assert_eq 'a/' "$(pty_get query)" 'esc dropped the query instead of keeping it'
	assert_eq '2' "$(pty_get count)" 'NORMAL stopped filtering on the kept query'
	assert_eq '2' "$(pty_get pos)" 'j did not move within the filtered rows'
	assert_empty "$(pty_pwd)" 'esc quit the picker instead of returning to NORMAL'
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ---------------------------------------------------------------------------
# 7. The unbind/rebind round trip, and the regression that once made it worthless.
# ---------------------------------------------------------------------------
# `zzz` matches nothing ON PURPOSE, because that is the case that used to leave a DEAD list.
# - NORMAL used to be search-off, and a cleared query was never re-matched, so the list froze empty.
# - Search now stays on in NORMAL, so the second esc's clear-query re-filters by itself.
# - r is a reload, which fires the result event the bare prompt change does not.
# - The non-empty accepted path is the assertion the original bug report turned on.
t 'pty: a query matching nothing survives two escs'
if pty_open 'hop -k tg'; then
	pty_key_ev '/'
	pty_key_ev z
	pty_key_ev z
	pty_key_ev z
	pty_key esc
	pty_key_ev r
	assert_eq '> ' "$(pty_get prompt)" 'esc did not restore the NORMAL prompt'
	assert_eq 'zzz' "$(pty_get query)" 'the first esc dropped the query'
	assert_eq '0' "$(pty_get count R)" 'NORMAL should show the empty filtered list'
	pty_key_ev esc
	assert_eq '> ' "$(pty_get prompt)" 'the second esc left NORMAL'
	assert_eq '' "$(pty_get query)" 'the second esc left the query in place'
	assert_eq '4' "$(pty_get count R)" 'the match set stayed frozen: NORMAL got a dead list'
	assert_empty "$(pty_pwd)" 'the second esc quit instead of clearing the query'
	assert_eq '1' "$(pty_get pos)" 'the round trip did not leave the cursor on row 1'
	pty_key_ev j
	assert_eq '2' "$(pty_get pos)" 'j typed instead of moving: the rebind did not restore it'
	pty_key o
	if pty_wait_exit; then
		assert_eq "code	-r	$(pty_row 2)/terragrunt.hcl" "$(pty_calls code)" \
			'o accepted an empty selection after the round trip'
	else
		_hop_t_bad 'o never made the picker exit' "$(pty_trace)"
	fi
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
	# A menu row's dir field is a kind name, so the always-cd key must leave the picker open.
	pty_key c
	assert_eq '' "$(pty_pwd)" 'c accepted a menu row, whose dir is a kind name'
	assert_eq ': ' "$(pty_get prompt)" 'c left the view menu'
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
