#!/usr/bin/env zsh
# hop test assertions.
# - A suite is plain top-level zsh: `t <name>` opens a test, the asserts after it belong to it.
# - An assertion never exits, so one test can report every way it went wrong in a single run.
# - Failures print AFTER the test's marker line, which is why detail lines are buffered.
# - Nothing here forks unless the assertion is about a command's exit status.

typeset -g  HOP_T_SUITE=${HOP_T_SUITE:-suite}
typeset -g  HOP_T_NAME=''
typeset -gi HOP_T_OPEN=0
typeset -gi HOP_T_BAD=0
typeset -gi HOP_T_SKIP=0
typeset -gi HOP_T_PASS=0
typeset -gi HOP_T_FAIL=0
typeset -gi HOP_T_SKIPPED=0
typeset -ga HOP_T_DETAIL=()

# How many lines of a multi-line expected/actual value a failure is allowed to dump.
# - A provider returns ~1k rows, and 2k lines of diff buries every other failure in the run.
typeset -gi HOP_T_MAX_DIFF=${HOP_T_MAX_DIFF:-12}

# Colour is decided by the runner, because a suite's own stdout is always a pipe.
if [[ ${HOP_T_COLOR:-0} == 1 ]]; then
	typeset -g HOP_T_GREEN=$'\e[32m'
	typeset -g HOP_T_RED=$'\e[31m'
	typeset -g HOP_T_DIM=$'\e[2m'
	typeset -g HOP_T_BOLD=$'\e[1m'
	typeset -g HOP_T_OFF=$'\e[0m'
else
	typeset -g HOP_T_GREEN='' HOP_T_RED='' HOP_T_DIM='' HOP_T_BOLD='' HOP_T_OFF=''
fi

# _hop_t_match <name> -> 0 when HOP_T_FILTER selects this test.
# - The filter is matched against `suite/test`, so `smoke/executable` addresses one test.
# - It is a zsh pattern with implicit wildcards on both ends, so `run 'zsh -n*'` works.
_hop_t_match() {
	emulate -L zsh
	local key="${HOP_T_SUITE}/$1"
	# ${~pat} is required: zsh does not treat a plain parameter's value as a pattern.
	local pat=${(L)HOP_T_FILTER}
	[[ ${(L)key} == *${~pat}* ]]
}

# _hop_t_finish -> close the open test, print its marker line, then its buffered detail.
_hop_t_finish() {
	emulate -L zsh
	(( HOP_T_OPEN )) || return 0
	HOP_T_OPEN=0
	if (( HOP_T_BAD )); then
		(( HOP_T_FAIL++ ))
		print -r -- "  ${HOP_T_RED}✗${HOP_T_OFF} ${HOP_T_NAME}"
		local d
		for d in "${HOP_T_DETAIL[@]}"; do
			print -r -- "      ${d}"
		done
	else
		(( HOP_T_PASS++ ))
		print -r -- "  ${HOP_T_GREEN}✓${HOP_T_OFF} ${HOP_T_NAME}"
	fi
	return 0
}

# t <name> -> close the previous test and open this one.
t() {
	emulate -L zsh
	_hop_t_finish
	HOP_T_NAME=$1
	HOP_T_BAD=0
	HOP_T_SKIP=0
	HOP_T_DETAIL=()
	if [[ -n ${HOP_T_FILTER:-} ]] && ! _hop_t_match "$1"; then
		HOP_T_SKIP=1
		HOP_T_OPEN=0
		return 0
	fi
	HOP_T_OPEN=1
	return 0
}

# skip <name> <reason> -> record a test that deliberately did not run.
# - Anything needing a real terminal belongs in SMOKE.md, and this is how the suite says so.
skip() {
	emulate -L zsh
	_hop_t_finish
	HOP_T_NAME=$1
	HOP_T_OPEN=0
	if [[ -n ${HOP_T_FILTER:-} ]] && ! _hop_t_match "$1"; then
		return 0
	fi
	(( HOP_T_SKIPPED++ ))
	print -r -- "  ${HOP_T_DIM}-${HOP_T_OFF} ${HOP_T_NAME} ${HOP_T_DIM}(skipped: ${2:-no reason given})${HOP_T_OFF}"
	return 0
}

# skip_cap <name> <reason> -> a skip on a developer's machine, a NAMED failure under $CI.
# - A missing tool is honest locally. On a CI runner it is coverage vanishing, and must be red.
# - The skip TALLY cannot carry this: one skip line routinely stands in for several suppressed tests.
# - Measured: suite_smoke's PyYAML branch emits one skip while suppressing five tests, so the count
#   moves by 1 where coverage moves by 5, which is why the reason is named rather than counted.
# - Use it at exactly ONE site per cause. Every other site for the same cause stays a plain `skip`
#   whose reason names the canonical one, because nine reds for one absent tool is noise, not signal.
# - The HOP_T_OPEN test is required: `t` leaves it 0 when HOP_T_FILTER excludes this name, and
#   _hop_t_bad would then reopen it as `(assertion outside any test)` under the wrong name.
skip_cap() {
	emulate -L zsh
	if [[ -z ${CI:-} ]]; then
		skip "$1" "$2"
		return 0
	fi
	t "$1"
	(( HOP_T_OPEN )) && _hop_t_bad "$2" 'this coverage vanished on CI instead of merely skipping'
	return 0
}

# _hop_t_bad <label> [detail...] -> mark the open test failed and buffer its report.
# - An assertion outside any `t` still reports, under a name that says the suite forgot one.
_hop_t_bad() {
	emulate -L zsh
	if (( ! HOP_T_OPEN )); then
		HOP_T_NAME='(assertion outside any test)'
		HOP_T_DETAIL=()
		HOP_T_OPEN=1
		HOP_T_BAD=0
	fi
	HOP_T_BAD=1
	HOP_T_DETAIL+=("${HOP_T_BOLD}${1}${HOP_T_OFF}")
	shift
	(( $# )) && HOP_T_DETAIL+=("$@")
	return 1
}

# _hop_t_side <sigil> <colour> <label> <text> -> buffer one side of a diff, capped in length.
_hop_t_side() {
	emulate -L zsh
	local sigil=$1 colour=$2 label=$3
	local -a lines=("${(@f)4}")
	if (( $#lines == 1 )); then
		HOP_T_DETAIL+=("${colour}${sigil} ${label}: ${lines[1]}${HOP_T_OFF}")
		return 0
	fi
	HOP_T_DETAIL+=("${colour}${sigil} ${label}:${HOP_T_OFF}")
	local -i n=0
	local l
	for l in "${lines[@]}"; do
		if (( ++n > HOP_T_MAX_DIFF )); then
			HOP_T_DETAIL+=("${HOP_T_DIM}  … $(( $#lines - HOP_T_MAX_DIFF )) more lines${HOP_T_OFF}")
			break
		fi
		HOP_T_DETAIL+=("${colour}${sigil} ${l}${HOP_T_OFF}")
	done
	return 0
}

# _hop_t_diff <expected> <actual> -> the two sides, git's way round: - is wanted, + is got.
_hop_t_diff() {
	emulate -L zsh
	_hop_t_side '-' "$HOP_T_RED" 'expected' "$1"
	_hop_t_side '+' "$HOP_T_GREEN" 'actual' "$2"
	return 0
}

# assert_eq <expected> <actual> [message]
assert_eq() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	[[ $1 == "$2" ]] && return 0
	_hop_t_bad "${3:-assert_eq: values differ}"
	_hop_t_diff "$1" "$2"
	return 1
}

# assert_ne <unwanted> <actual> [message]
assert_ne() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	[[ $1 != "$2" ]] && return 0
	_hop_t_bad "${3:-assert_ne: values are equal}"
	_hop_t_side '=' "$HOP_T_RED" 'both' "$1"
	return 1
}

# assert_contains <haystack> <needle> [message]
assert_contains() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	[[ $1 == *"$2"* ]] && return 0
	_hop_t_bad "${3:-assert_contains: substring not found}"
	_hop_t_side '-' "$HOP_T_RED" 'needle' "$2"
	_hop_t_side '+' "$HOP_T_GREEN" 'haystack' "$1"
	return 1
}

# assert_not_contains <haystack> <needle> [message]
assert_not_contains() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	[[ $1 != *"$2"* ]] && return 0
	_hop_t_bad "${3:-assert_not_contains: substring is present}"
	_hop_t_side '-' "$HOP_T_RED" 'needle' "$2"
	_hop_t_side '+' "$HOP_T_GREEN" 'haystack' "$1"
	return 1
}

# assert_ge <actual> <minimum> [message] -> a numeric floor, for "at least N rows" checks.
# - A row count is the honest assertion about a provider: the exact total changes every week.
assert_ge() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	local got=$1 min=$2
	if [[ $got != (-|)<-> || $min != (-|)<-> ]]; then
		_hop_t_bad "${3:-assert_ge: not an integer}"
		_hop_t_diff ">= ${min}" "$got"
		return 1
	fi
	(( got >= min )) && return 0
	_hop_t_bad "${3:-assert_ge: below the floor}"
	_hop_t_diff ">= ${min}" "$got"
	return 1
}

# assert_empty <value> [message]
assert_empty() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	[[ -z $1 ]] && return 0
	_hop_t_bad "${2:-assert_empty: value is not empty}"
	_hop_t_side '+' "$HOP_T_GREEN" 'actual' "$1"
	return 1
}

# assert_nonempty <value> [message]
assert_nonempty() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	[[ -n $1 ]] && return 0
	_hop_t_bad "${2:-assert_nonempty: value is empty}"
	return 1
}

# assert_file <path> [message] -> a readable regular file.
assert_file() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	[[ -f $1 && -r $1 ]] && return 0
	_hop_t_bad "${2:-assert_file: not a readable file}"
	_hop_t_side '+' "$HOP_T_GREEN" 'path' "$1"
	if [[ -e $1 ]]; then
		_hop_t_side '+' "$HOP_T_GREEN" 'mode' "$(command ls -ld -- "$1" 2>&1)"
	else
		_hop_t_side '+' "$HOP_T_GREEN" 'state' 'does not exist'
	fi
	return 1
}

# assert_exec <path> [message] -> an existing file with the executable bit set.
# - The chezmoi source names it `executable_hop-kinds`, so only the applied copy can pass this.
assert_exec() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	[[ -f $1 && -x $1 ]] && return 0
	_hop_t_bad "${2:-assert_exec: not an executable file}"
	_hop_t_side '+' "$HOP_T_GREEN" 'path' "$1"
	if [[ -e $1 ]]; then
		_hop_t_side '+' "$HOP_T_GREEN" 'mode' "$(command ls -ld -- "$1" 2>&1)"
	else
		_hop_t_side '+' "$HOP_T_GREEN" 'state' 'does not exist'
	fi
	return 1
}

# assert_status <expected> <command> [arg...] -> run it, compare the exit status.
# - Output is captured rather than printed, so a noisy command cannot corrupt the result lines.
# - Never pass an interactive command here: fzf must only ever be run with --filter.
assert_status() {
	emulate -L zsh
	(( HOP_T_SKIP )) && return 0
	local -i want=$1
	shift
	local out
	local -i st
	out=$("$@" 2>&1)
	st=$?
	(( st == want )) && return 0
	_hop_t_bad "assert_status: ${(j: :)@}" \
		"${HOP_T_RED}- expected status ${want}${HOP_T_OFF}" \
		"${HOP_T_GREEN}+ actual status ${st}${HOP_T_OFF}"
	[[ -n $out ]] && _hop_t_side '+' "$HOP_T_GREEN" 'output' "$out"
	return 1
}
