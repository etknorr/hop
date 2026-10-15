#!/usr/bin/env zsh
# hop pty filter suite: esc out of SEARCH keeps the query, and NORMAL then works on the filtered rows.
# - Kept out of suite_pty.zsh, whose header sets an explicit nine-test budget.
# - Four is this suite's budget, at about a second each.
# - `a/` is the query throughout because it matches exactly alpha and delta, rows 1 and 4.
# - So filtered row 2 is delta while full-list row 2 is bravo, and a cd tells the two lists apart.
# - Leaving SEARCH changes only the prompt, which fires no fzf event, so a later key reads the state.

source "$HOP_TESTS/lib/pty.zsh"

typeset -ga PF_NAMES=(
	'pty-filter: enter in NORMAL cds to a row of the kept filter'
	'pty-filter: esc in NORMAL clears the query, and the next esc quits'
	'pty-filter: / after esc edits the kept query from its end'
	'pty-filter: hop <words> opens in SEARCH, and esc keeps the words'
)

# pf_skip_all <why> -> skip every test this suite owns, with one reason.
pf_skip_all() {
	emulate -L zsh
	local n
	for n in "${PF_NAMES[@]}"; do
		skip "$n" "$1"
	done
}

if ! pty_supported; then
	pf_skip_all 'zsh/zpty is not available'
	return 0
fi

pty_fixture_repo || return 1
pty_env || return 1

# Losing pty capability is suite_pty.zsh's canary to report, and it turns CI red on its own.
if ! pty_canary; then
	pf_skip_all 'no pty capability on this machine'
	return 0
fi

# pf_filter -> from a fresh picker's NORMAL, type `a/` in SEARCH and esc back out with it kept.
pf_filter() {
	emulate -L zsh
	pty_key_ev '/'
	pty_key_ev a
	pty_key_ev '/'
	pty_key esc
}

t "${PF_NAMES[1]}"
if pty_open 'hop -k tg'; then
	pf_filter
	pty_key_ev j
	assert_eq '> ' "$(pty_get prompt)" 'esc did not restore the NORMAL prompt'
	assert_eq '2' "$(pty_get count)" 'NORMAL stopped filtering on the kept query'
	pty_key enter
	if pty_wait_exit; then
		assert_eq "$(pty_row 4)" "$(pty_pwd)" 'enter did not cd to the second FILTERED row'
		assert_ne "$(pty_row 2)" "$(pty_pwd)" 'enter cd to row 2 of the full list, outside the filter'
	else
		_hop_t_bad 'enter never made the picker exit' "$(pty_trace)"
	fi
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

t "${PF_NAMES[2]}"
if pty_open 'hop -k tg'; then
	pf_filter
	pty_key_ev esc
	assert_eq '> ' "$(pty_get prompt)" 'the second esc left NORMAL'
	assert_eq '' "$(pty_get query)" 'the second esc left the query in place'
	assert_eq '4' "$(pty_get count R)" 'clearing the query did not bring the full list back'
	assert_empty "$(pty_pwd)" 'the second esc quit instead of clearing the query'
	pty_key esc
	if pty_wait_exit; then
		assert_eq "$HOP_PTY_REPO" "$(pty_pwd)" 'esc on an empty query must quit without a cd'
		assert_empty "$(pty_calls code)" 'quitting reached a verb'
	else
		_hop_t_bad 'esc on an empty query did not quit' "$(pty_trace)"
	fi
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# ctrl-a is fzf's beginning-of-line and not a NORMAL key, so it really can move the cursor there.
t "${PF_NAMES[3]}"
if pty_open 'hop -k tg'; then
	pf_filter
	pty_key $'\x01'
	pty_key_ev '/'
	assert_eq '/ ' "$(pty_get prompt)" '/ did not switch back to SEARCH'
	assert_eq 'a/' "$(pty_get query)" '/ dropped the kept query'
	pty_key_ev x
	assert_eq 'a/x' "$(pty_get query)" 'the next letter did not land at the end of the kept query'
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close

# A CLI query opens in SEARCH through the start bind, the one path that never passes --disabled.
# - The count is compared to itself rather than pinned, since how a CLI query ranks rows is the resolver's business.
t "${PF_NAMES[4]}"
if pty_open 'hop -k tg vpc'; then
	pty_quiesce
	assert_eq '/ ' "$(pty_get prompt)" 'a CLI query did not open in SEARCH'
	assert_eq 'vpc' "$(pty_get query)" 'the CLI query did not reach the picker'
	typeset pf_n
	pf_n=$(pty_get count)
	pty_key esc
	pty_key_ev j
	assert_eq '> ' "$(pty_get prompt)" 'esc did not restore the NORMAL prompt'
	assert_eq 'vpc' "$(pty_get query)" 'esc dropped the CLI query'
	assert_eq "$pf_n" "$(pty_get count)" 'esc changed which rows the CLI query matches'
	assert_eq '2' "$(pty_get pos)" 'j did not move in NORMAL after a CLI query'
	assert_empty "$(pty_pwd)" 'esc quit the picker instead of returning to NORMAL'
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close
