#!/usr/bin/env zsh
# suite_runner: the RUNNER's own behaviour, proven by spawning a NESTED tests/run and reading it.
# - Every other suite asserts about hop, or about a lib file's text; this one runs the runner itself.
# - The subject is the tally a bound-killed suite reports, which only executes when a suite is KILLED.
# - No ordinary suite is ever killed, so nothing else in this repo can reach that code path at all.
# - It needs perl: hop_bound runs UNBOUNDED without it, so the nested suite would finish normally.
# - That case skips and says so, rather than asserting against a suite that was never killed.
# - A skip is legitimate here where suite_harness forbids one, because that suite only reads file text.

typeset -g RU_TREE='' RU_OUT='' RU_SUITE=''
# Seconds the nested runner gives its one suite. Small on purpose: the whole point is that it fires.
typeset -gi RU_BOUND=3
# How many tests the fixture suite CLOSES before it hangs, which is the exact tally expected back.
typeset -gi RU_CLOSED=3

# ru_build -> REPLY is a throwaway test tree holding a copy of the runner and one hanging suite.
# - The runner is COPIED, never symlinked, because tests/run derives HOP_TESTS from ${0:A}.
# - `:A` resolves a symlink back to the REAL tests dir, which would run every real suite instead.
# - lib is symlinked, which is safe, because it is reached through $HOP_TESTS and never through $0.
# - The fixture suite closes three tests, then opens a fourth and hangs.
# - Markers print LAZILY, from _hop_t_finish when the NEXT test opens, so the open fourth emits none.
# - `sleep` is external, and zsh flushes its output buffer before forking, which is what files them.
# - A builtin-only spin would leave the markers unflushed and the KILL would take them with it.
ru_build() {
	emulate -L zsh
	local REPLY
	fixture_tmpdir runnertree || return 1
	RU_TREE=$REPLY
	mkdir -p -- "$RU_TREE/tests" "$RU_TREE/tmp" "$RU_TREE/home" || return 1
	cp -- "$HOP_TESTS/run" "$RU_TREE/tests/run" || return 1
	ln -s -- "$HOP_TESTS/lib" "$RU_TREE/tests/lib" || return 1
	RU_SUITE="$RU_TREE/tests/suite_bound.zsh"
	print -rl -- \
		'# A fixture suite for suite_runner: three closed tests, then one that never finishes.' \
		"t 'closed one'" \
		'assert_eq 1 1' \
		"t 'closed two'" \
		'assert_eq 2 2' \
		"t 'closed three'" \
		'assert_eq 3 3' \
		"t 'this one is still open when the bound kills the suite'" \
		'sleep 30' > "$RU_SUITE" || return 1
	return 0
}

# ru_run -> RU_OUT is everything the nested runner printed; the return status is the runner's own.
# - env -i, so no HOP_* from this process reaches it and HOP_T_COLOR is off, leaving plain markers.
# - TMPDIR is pinned inside the tree, so the fixtures the KILLED child cannot clean up land there.
# - Unpinned they would leak into the real temp root, where suite_smoke's zero-leak guard reads.
# - The outer hop_bound is a backstop and not the subject: a wedged nested run must cost one test.
ru_run() {
	emulate -L zsh
	local out
	out=$(hop_bound 60 env -i PATH="$PATH" TERM=dumb SHELL=/bin/zsh \
		HOME="$RU_TREE/home" TMPDIR="$RU_TREE/tmp" \
		HOP_T_TIMEOUT=$RU_BOUND HOP_T_REAP_HOURS=0 \
		zsh "$RU_TREE/tests/run" 2>&1 </dev/null)
	local -i st=$?
	RU_OUT=$out
	return $st
}

# ru_markers -> how many passing markers the nested runner actually printed.
ru_markers() {
	emulate -L zsh
	local -a lines=("${(@f)RU_OUT}")
	print -r -- ${#${(M)lines:#'  ✓ '*}}
}

# ru_reported -> the pass count the nested runner's own summary line claims, or empty.
# - Found by locating the `passed,` token and taking the one before it, never by field position.
# - That way the FAIL/ok prefix, and any colour wrapping around it, cannot shift the field read.
# - The needle is held in a variable because a literal comma inside a subscript is a SLICE separator.
# - Written inline as ${w[(I)passed,]} it parses as a range and zsh fails with `invalid subscript`.
ru_reported() {
	emulate -L zsh
	local -a lines=("${(@f)RU_OUT}")
	local -a sum=(${(M)lines:#*' passed, '*})
	(( $#sum )) || return 1
	local -a w=(${=sum[-1]})
	local needle='passed,'
	local -i i=${w[(I)$needle]}
	(( i > 1 )) || return 1
	print -r -- "${w[i-1]}"
}

# ---------------------------------------------------------------------------
# A suite killed by the bound still reports the results it had already produced.
# ---------------------------------------------------------------------------
if (( ! ${+commands[perl]} )); then
	skip 'a bound-killed suite reports the passes it had already printed' \
		'hop_bound runs unbounded without perl, so no suite would be killed'
	skip 'the bound-killed tally is the KILL path, not a trapped signal' \
		'hop_bound runs unbounded without perl, so no suite would be killed'
	return 0
fi

typeset -i RU_ST RU_MARK RU_REP
ru_build || return 1
ru_run
RU_ST=$?
RU_MARK=$(ru_markers)
RU_REP=$(ru_reported)

# No markers at all means the bound killed the child before it printed anything, which is LOAD.
# - The two states are distinguishable, which is the only reason skipping here is honest at all.
# - The DEFECT reads markers 3 and reported 0: the evidence exists and the runner threw it away.
# - This reads markers 0, so there is nothing to assert over and a red would blame the wrong thing.
# - Measured: the child files its three markers in 0.09s to 0.12s at loadavg 6.2, against a 3s bound.
# - All three are still recovered at a 1s bound on that same machine, so the headroom here is ~30x.
# - Skipping beats raising the bound, which would pay the whole margin in wall time on every run.
# - But note WHAT this skip costs: a deliberate kill censors the very observations being counted.
# - So a chronically loaded runner loses this coverage silently, one skip at a time, and stays green.
# - The skip names load as the cause for that reason, so the reader can tell absence from success.
if (( RU_MARK == 0 )); then
	skip 'a bound-killed suite reports the passes it had already printed' \
		"nothing was printed before the ${RU_BOUND}s bound, so this machine is too loaded to measure"
	skip 'the bound-killed tally is the KILL path, not a trapped signal' \
		"nothing was printed before the ${RU_BOUND}s bound, so this machine is too loaded to measure"
	return 0
fi

t 'a bound-killed suite reports the passes it had already printed'
# The tally the runner prints must equal the markers it printed, and BOTH must be the known 3.
# - The equality alone is NOT the assertion, which is the trap this suite is written around.
# - A nested run that never started prints no markers and claims nothing, satisfying it as 0 == 0.
# - So the exact count is asserted on each side independently, and 3 is what makes it non-vacuous.
# - Exact and never a floor: `>= 1` still passes with two of the three passes silently dropped.
# - That is the defect itself in miniature, and a floor let four assertions rot this release already.
assert_eq $RU_CLOSED $RU_MARK 'the fixture suite did not print the three markers this rests on'
assert_eq $RU_CLOSED $RU_REP 'the runner discarded passes it had already printed, which is the defect'
assert_eq $RU_MARK $RU_REP 'the reported tally and the printed markers disagree'

t 'the bound-killed tally is the KILL path, not a trapped signal'
# This is what stops the test above being read as evidence about a signal it never exercised.
# - hop_bound KILLs the process group and exits 142, and nothing else in the runner exits 142.
# - KILL cannot be trapped, so the child's `trap ... EXIT INT TERM` never runs and no sentinel lands.
# - That absence is precisely why the parent has to count markers, so it is the condition under test.
# - Under TERM the trap WOULD run, close the open fourth test, and emit a sentinel claiming four.
# - That path never reaches the marker counting at all, so it is a different mechanism entirely.
# - 142 is the SUITE CHILD's status, which the nested runner reports in its text, not its own exit.
# - The nested runner itself exits 1 because it reports a failure, so reading $? here proves nothing.
# - A signal from outside would print `came from OUTSIDE this runner` and carry 143, not 142.
assert_eq 1 $RU_ST 'the nested runner should exit 1, having reported the killed suite as a failure'
assert_contains "$RU_OUT" '(exit 142)' 'the suite child was not killed by the bound, so no marker counting ran'
assert_contains "$RU_OUT" "killed by this runner's ${RU_BOUND}s bound" 'the runner did not attribute the kill to its own bound'
# Deliberately NOT covered, and not implied: the same KILL also leaks the killed suite's fixtures.
# - That is the second symptom of this one defect, and suite_smoke's zero-leak guard SKIPS that case.
# - So no test in this repo asserts on the leak under KILL, and this suite does not pretend otherwise.
