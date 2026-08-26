#!/usr/bin/env zsh
# hop pty reload suite: alt-a through a REAL fzf, which is the one thing a stub cannot prove.
# - suite_core evals the reload string in zsh; fzf runs it through its own `sh -c` instead.
# - So a string that survives `eval` can still be mangled by the layer that actually runs it.
# - Kept out of suite_pty.zsh, whose header sets an explicit eight-test budget.

source "$HOP_TESTS/lib/pty.zsh"

typeset -g PR_NAME='pty: alt-a reloads with the user config, not the shipped presets'

if ! pty_supported; then
	skip "$PR_NAME" 'zsh/zpty is not available'
	return 0
fi

pty_fixture_repo || return 1
pty_env || return 1

typeset -i PR_OK=0
pty_canary && PR_OK=1

if (( ! PR_OK )) && [[ -z ${CI:-} ]]; then
	skip "$PR_NAME" 'no pty capability on this machine'
	return 0
fi
if (( ! PR_OK )); then
	# Under CI a dead canary is a broken runner, which suite_pty already turns red.
	skip "$PR_NAME" 'the pty canary failed; suite_pty reports it'
	return 0
fi

# A kind that exists ONLY in the config, so the shipped presets cannot supply it by accident.
# - pty_env deliberately points HOP_CONFIG at a missing file, so this overrides that for one suite.
# - The marker file has to be committed, because every provider enumerates the git index.
typeset PR_CFG
fixture_tmpdir ptycfg || return 1
PR_CFG="$REPLY/config.zsh"
print -rl -- \
	'hop_preset terragrunt' \
	'hop_kind mine --default --marker OWNER --under mine --layout "name..." --desc "my own kind"' \
	> "$PR_CFG"
# Three rows, not one: _hop_pick passes --select-1, so a single match auto-accepts and never paints.
typeset PR_D
for PR_D in onlyhere alsohere andhere; do
	fixture_write "mine/${PR_D}/OWNER" 'me' || return 1
done
fixture_commit 'a kind only the config knows' || return 1

# HOP_CONFIG is assigned PLAINLY inside the pty child, never exported into it, and that is the point.
# - pty_env exports it, and an already-exported value reaches the reload child on its own.
# - So exporting the test config here would pass whether hop.zsh says `-g` or `-gx`: a vacuous test.
# - Unsetting and assigning plainly is what a `.zshrc` line does, and it is what `-gx` has to fix.
# - hop.zsh is re-sourced afterwards because the driver already sourced it before this runs.
typeset PR_CMD="unset HOP_CONFIG; HOP_CONFIG=${(q)PR_CFG}"
PR_CMD+='; source "$HOP_HOME/hop.zsh"; hop -k mine'

t "$PR_NAME"
if pty_open "$PR_CMD"; then
	assert_eq '3' "$(pty_get count R)" 'the config kind should start as its own three rows'

	# alt-a is ESC-prefixed, sent as ONE write so fzf reads it as a key and not as bare esc.
	pty_key_ev $'\ea'

	# The EXACT count is the whole assertion, and a floor would not do.
	# - alt-a reloads with every registered kind, which here is the tg preset plus the config kind.
	# - Deprived of HOP_CONFIG the child still knows tg, so it returns the tg rows and drops mine.
	# - A `>= 2` floor therefore passes on the tg rows alone: measured, it did.
	# - Counting both kinds is what tells the two registries apart.
	assert_eq "$(( ${#HOP_PTY_ROWS} + 3 ))" "$(pty_get count R)" \
		'alt-a reloaded without the config kind, so the child got the shipped presets'

	# Proving the reloaded list still WORKS, since a reload can leave a picker that accepts nothing.
	pty_key enter
	if pty_wait_exit; then
		assert_nonempty "$(pty_pwd)" 'enter after alt-a accepted nothing at all'
	else
		_hop_t_bad 'enter never made the picker exit after alt-a' "$(pty_trace)"
	fi
else
	_hop_t_bad 'pty_open: the picker never reported ready' "$(pty_err)"
fi
pty_close
