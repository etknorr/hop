#!/usr/bin/env zsh
# suite_harness: structural invariants about the TEST HARNESS itself, never about hop.
# - Each check reads a lib file and asks a question about how it is written, not what it does.
# - Everything here runs everywhere: no zpty, no fzf, no network, and no conditional skips.
# - A skip would defeat the purpose, since these exist to catch an edit nobody thought to test.

typeset -g HA_PTY="$HOP_TESTS/lib/pty.zsh"

# ha_spawns_in_text -> how many `zpty -b` spawns the FILE contains, comments excluded.
# - A function body, because `zsh -n` evaluates a top-level $(<file) and this suite must parse clean.
ha_spawns_in_text() {
	emulate -L zsh
	local -a lines hits=()
	local line
	lines=("${(@f)$(<"$HA_PTY")}")
	for line in "${lines[@]}"; do
		[[ ${line%%\#*} == *'zpty -b'* ]] && hits+=("$line")
	done
	print -r -- $#hits
}

# ha_spawns_in_functions -> the same count, but only where zsh's own PARSER puts it in a function body.
# - Sourced in a throwaway child with a scratch TMPDIR, so any fixture side effect lands there.
# - Sourcing alone spawns nothing today, precisely because every spawn is inside a function.
ha_spawns_in_functions() {
	emulate -L zsh
	local scratch REPLY
	fixture_tmpdir harness-parse || return 1
	scratch=$REPLY
	hop_bound 20 env "TMPDIR=${scratch}" "HOP_TESTS=${HOP_TESTS}" "HOP_HOME=${HOP_HOME}" \
		zsh -f -c "source ${(q)HA_PTY} 2>/dev/null || exit 97
integer n=0
local f body rest
for f in \${(k)functions}; do
	body=\${functions[\$f]}
	rest=\$body
	while [[ \$rest == *'zpty -b'* ]]; do
		(( n++ ))
		rest=\${rest#*zpty -b}
	done
done
print -r -- \$n"
}

# ---------------------------------------------------------------------------
# tests/lib/pty.zsh: every zpty spawn must sit inside a function.
# ---------------------------------------------------------------------------
# `zpty -b` at a script's TOP LEVEL makes the spawned shell inherit the caller's EXIT trap.
# - Reproduce in ten lines rather than take this on trust: install an EXIT trap that prints, spawn `zpty -b P "zsh -f -c :"` at a script's top level and the trap fires, move that same spawn inside a function and it does not.
# - pty.zsh's own EXIT trap removes the shared pty fixtures, which every pty test reads.
# - So hoisting a spawn out of pty_open or pty_canary would delete those fixtures mid-run.
# - Nothing enforced that: the safety was incidental and undocumented, which is what this pins.
# - `pgrep -x zpty` could never have caught it either, since zpty is a builtin and the child carries the spawned command's name.
t 'the pty spawn scan can see pty.zsh and really does match a spawn'
# The positive control, and it is the load-bearing half of this guard.
# - The invariant below is an EQUALITY, and a scan that reads nothing at all satisfies it as 0 == 0.
# - A wrong path, an unreadable file or a rotted pattern each produce that, and each looks healthy.
# - So the pattern is proven to find the spawns that are really there before it is trusted at all.
typeset -i HA_TEXT HA_INFN
HA_TEXT=$(ha_spawns_in_text)
assert_eq 2 $HA_TEXT 'pty.zsh should hold exactly two zpty spawns, in pty_open and pty_canary'

t 'every zpty spawn in tests/lib/pty.zsh sits inside a function'
# Compared as counts through zsh's parser, rather than by looking at the column the line starts in.
# - A column-0 grep was the obvious check and is a FORMATTING proxy: a spawn indented inside a top-level `if` is still top level and would pass it.
# - A brace-depth counter was tried and rejected: parameter expansions unbalance it, and its own "final depth must be 0" check reported 6 and caught it.
# - This asks the parser instead, so the question it answers is the one the defect is actually about.
HA_INFN=$(ha_spawns_in_functions)
assert_eq 2 $HA_INFN 'zsh could not find both spawns in a function body, so one of them is at top level'
assert_eq $HA_TEXT $HA_INFN 'a spawn exists in the file that no function body holds, which is the inherited-trap bug'
