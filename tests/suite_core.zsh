#!/usr/bin/env zsh
# hop core suite: the four defects in hop.zsh itself, each with a case that fails if the fix is reverted.
# - Every fzf here is a STUB that draws nothing and exits with whatever status the test asked for.
# - The real fzf is never started, not even with --filter, so no case in this file can touch a tty.

# ---------------------------------------------------------------------------
# A stub fzf, plus a probe that runs hop() against it.
# ---------------------------------------------------------------------------

# co_stub_fzf -> a directory holding a recording fzf, first on PATH only for the probes that ask.
# - It records argv and stdin, then exits $HOP_FZF_EXIT, which is how a status ladder gets tested.
# - `--version` is answered by the same script, and a non-version string makes _hop_fzf_ok pass.
typeset -g CO_STUBDIR='' CO_ARGV='' CO_STDIN=''
co_stub_fzf() {
	emulate -L zsh
	[[ -z $CO_STUBDIR ]] || return 0
	local REPLY
	fixture_tmpdir fzfstub || return 1
	CO_STUBDIR=$REPLY
	CO_ARGV="$CO_STUBDIR/argv"
	CO_STDIN="$CO_STUBDIR/stdin"
	print -rl -- \
		'#!/bin/sh' \
		'# hop test stub: records the call, draws nothing, exits the status the test picked.' \
		': > "$HOP_FZF_ARGV"' \
		'for a in "$@"; do printf "%s\n" "$a" >> "$HOP_FZF_ARGV"; done' \
		'cat > "$HOP_FZF_STDIN"' \
		'exit ${HOP_FZF_EXIT:-1}' > "$CO_STUBDIR/fzf"
	chmod +x "$CO_STUBDIR/fzf" || return 1
	return 0
}

# co_run <code> [VAR=value...] -> run code in a probe child whose only fzf is the stub.
# - perl's alarm bounds it, because a stub that somehow blocked would otherwise hang the suite.
# - Both streams are captured, since every assertion here is about a message on stderr.
# - The probe's status is this function's OWN status: a caller reads it as $? after the $(...).
# - Setting a global instead would lose it, because $(co_run ...) runs the whole body in a subshell.
co_run() {
	emulate -L zsh
	co_stub_fzf || return 1
	local code=$1
	shift
	: > "$CO_ARGV"
	: > "$CO_STDIN"
	local out st
	out=$(perl -e 'alarm 20; exec @ARGV' env \
		"HOP_FZF_ARGV=${CO_ARGV}" "HOP_FZF_STDIN=${CO_STDIN}" "$@" \
		zsh -f -c "$(fixture_pins)
export PATH=${(q)CO_STUBDIR}:\$PATH
source ${(q)HOP_HOME}/hop.zsh || exit 97
${code}" 2>&1)
	st=$?
	print -r -- "$out"
	return $st
}

# co_ws -> REPLY is a directory usable as a workspace, so `hop -w` renders exactly one row.
# - _hop_provider_ws emits a row for any workspace that EXISTS, repos or not, so one mkdir is enough.
co_ws() {
	emulate -L zsh
	fixture_tmpdir ws || return 1
	return 0
}

# ---------------------------------------------------------------------------
# Item 4: _hop_ws_picker has to read fzf's exit status, like every other picker.
# ---------------------------------------------------------------------------
# Built here at the top level, not inside a $(...), or the stub's path would not survive the subshell.
co_stub_fzf || return 1
typeset CO_WS out
typeset -i st
co_ws
CO_WS=$REPLY

t 'the stub fzf really is the only fzf a probe can see'
out=$(co_run 'print -r -- ${commands[fzf]}')
assert_eq "$CO_STUBDIR/fzf" "$out" 'a real fzf on PATH would make every case below meaningless'

t 'hop -w reports a non-zero fzf status instead of swallowing it'
out=$(co_run 'hop -w' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=2'); st=$?
assert_contains "$out" 'hop: fzf exited with status 2' 'the ws picker skipped the status ladder'
assert_eq 2 "$st" 'the fzf status has to reach the caller, not be replaced by 0'

t 'hop -R reports the same status the same way, so the two pickers cannot drift'
out=$(co_run 'hop -R' "HOP_REPOS=${CO_WS}" 'HOP_FZF_EXIT=2'); st=$?
assert_contains "$out" 'hop: fzf exited with status 2'
assert_eq 2 "$st"

t 'hop -w on a no-match says so, rather than printing nothing at all'
out=$(co_run 'hop -w nosuchworkspace' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=1'); st=$?
assert_contains "$out" 'hop: no match for: nosuchworkspace'
assert_eq 1 "$st"

t 'hop -w on a user cancel stays silent and succeeds'
out=$(co_run 'hop -w' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=130'); st=$?
assert_empty "$out" '130 is esc, and esc must never print anything'
assert_eq 0 "$st" 'cancelling is not a failure'

t 'esc out of the repo picker is silent too, which is what makes 130 a shared rule'
out=$(co_run 'hop -R' "HOP_REPOS=${CO_WS}" 'HOP_FZF_EXIT=130'); st=$?
assert_empty "$out"
assert_eq 0 "$st"

t 'both pickers route through the one _hop_fzf_status, so the ladder cannot be duplicated'
out=$(co_run 'print -r -- ${#${(M)${(f)"$(functions _hop_run _hop_ws_picker)"}:#*fzf exited with status*}}')
assert_eq 0 "$out" 'a picker with its own copy of the message has forked the ladder again'
out=$(co_run 'whence -w _hop_fzf_status')
assert_contains "$out" 'function' 'the shared helper has to exist for either picker to use it'

t '_hop_ws_picker leaves no _hop_key or _hop_st behind in the calling shell'
out=$(co_run 'hop -w >/dev/null 2>&1; print -r -- "key=${_hop_key-unset} st=${_hop_st-unset}"' \
	"HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=130')
assert_eq 'key=unset st=unset' "$out" 'the picker must not leak state into the interactive shell'
