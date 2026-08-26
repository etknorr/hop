#!/usr/bin/env zsh
# suite_integration: the whole tool end to end, from a shell prompt down to a cd.
#
# - Everything asserted here runs against SYNTHETIC repos built by this file.
# - A real checkout is exercised only when $HOP_TEST_REPO names one, and skipped otherwise.
# - No path under $HOME is ever hardcoded, so the suite behaves the same on any machine.
#
# fzf appears here in exactly two shapes, and never a third.
#   1. `fzf --exact --filter=QUERY`, which is non-interactive and only ever reports match counts.
#   2. A recording STUB named fzf, which saves argv plus stdin and exits 1 so hop takes its no-match path.
#
# - The stub is what lets a --cwd row set be inspected without a terminal, and it is not fzf.
# - Anything that needs a real terminal is a manual check, and lives in ../SMOKE.md.

zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null
zmodload -F zsh/stat b:zstat 2>/dev/null

# Real hop verbs shell out to these, and an early run opened editor windows on the desktop.
# - bat is deliberately NOT stubbed, because one test below needs it genuinely absent.
stub_bin code gh pbcopy pbpaste open vim nvim

typeset -g IT_WORK IT_ERRFILE IT_ROWS
typeset -g REPLY
fixture_tmpdir integration
IT_WORK=$REPLY
IT_ERRFILE="$IT_WORK/stderr"
IT_ROWS="$IT_WORK/rows"
: > "$IT_ERRFILE"

# A fixture HOME, so nothing resolves a default into the real user's dotfiles.
typeset -g IT_HOME
fixture_tmpdir inthome
IT_HOME=$REPLY
mkdir -p -- "$IT_HOME/.config"

# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

# it_count <text> -> how many non-empty lines it holds, without forking.
it_count() {
	emulate -L zsh
	[[ -n $1 ]] || { print -r -- 0; return 0 }
	local -a l=("${(@f)1}")
	l=(${l:#})
	print -r -- $#l
}

# it_dirs <rows> -> the dir field of every row, which is field 2 of the three.
it_dirs() {
	emulate -L zsh
	local -a out
	local row
	for row in "${(@f)1}"; do
		[[ -n $row ]] || continue
		out+=("${${row#*$'\t'}%$'\t'*}")
	done
	print -rl -- "${out[@]}"
}

# it_slurp <file> -> the file's contents, or empty when it is unreadable.
# - This exists because `zsh -n` EVALUATES a top-level $(<file) and a suite must parse cleanly.
it_slurp() {
	emulate -L zsh
	[[ -n ${1:-} && -r $1 ]] || return 0
	print -r -- "$(<"$1")"
}

# it_err -> the stderr captured by the last it_run, it_gen or it_preview.
it_err() {
	emulate -L zsh
	it_slurp "$IT_ERRFILE"
}

# it_errbytes -> the byte size of the last captured stderr, since a slurp hides a trailing newline.
it_errbytes() {
	emulate -L zsh
	local -a sz
	zstat -A sz +size -- "$IT_ERRFILE" 2>/dev/null || { print -r -- -1; return 0 }
	print -r -- ${sz[1]}
}

# it_env -> the pins every child shell needs in order to be hermetic, against THIS suite's own home.
# - Delegated to fixture_pin_pairs so this list cannot fall behind the one hop_probe uses.
# - It kept its own five-entry list once, and an exported HOP_FZF_MIN or HOP_REPOS walked straight in.
# - Only the home differs from a probe's: this suite owns IT_HOME and builds a real checkout in it.
it_env() {
	emulate -L zsh
	fixture_pin_pairs "$IT_HOME"
}

# it_run <code> [VAR=value...] -> run code in a fresh shell with hop.zsh sourced; stderr to IT_ERRFILE.
# - hop_bound is the timeout on this box, and 20s is far above any honest enumeration.
it_run() {
	emulate -L zsh
	local code=$1
	shift
	local -a pins=("${(@f)$(it_env)}")
	hop_bound 20 env "${pins[@]}" "$@" \
		zsh -f -c "source ${(q)HOP_HOME}/hop.zsh || exit 97
${code}"  2>"$IT_ERRFILE"
}

# it_gen <root> <kind...> -> the rows a kind list produces, with stderr captured separately.
# - Sources hop.zsh, because the kind REGISTRY is what _hop_generate dispatches through.
it_gen() {
	emulate -L zsh
	local root=$1
	shift
	local code="_hop_generate ${(q)root}"
	local k
	for k in "$@"; do
		code+=" ${(q)k}"
	done
	local -a pins=("${(@f)$(it_env)}")
	hop_bound 30 env "${pins[@]}" \
		zsh -f -c "source ${(q)HOP_HOME}/hop.zsh || exit 97
${code}" 2>"$IT_ERRFILE"
}

# it_filter <query> <rows-file> -> the rows fzf's exact matcher keeps, one per line.
# - The flags mirror _hop_pick, so a count here is the count the picker would see.
# - --filter never opens a terminal, which is the only reason fzf may be run at all.
typeset -g IT_FZF=${commands[fzf]:-}
it_filter() {
	emulate -L zsh
	[[ -n $IT_FZF ]] || return 127
	"$IT_FZF" --filter="$1" --exact --ansi --delimiter=$'\t' --with-nth=1 \
		--tiebreak=begin,length < "$2"
}

# it_filter_fuzzy <query> <rows-file> -> the same call with --exact dropped, to price the flag.
it_filter_fuzzy() {
	emulate -L zsh
	[[ -n $IT_FZF ]] || return 127
	"$IT_FZF" --filter="$1" --ansi --delimiter=$'\t' --with-nth=1 \
		--tiebreak=begin,length < "$2"
}

# it_stub_fzf -> a directory holding a recording fzf, put first on PATH only for the runs that ask.
# - It writes its argv and its stdin to files, then exits 1, which is fzf's own no-match status.
# - So hop runs its whole real path and then reports no match, with nothing interactive anywhere.
typeset -g IT_STUBDIR='' IT_FZF_ARGV='' IT_FZF_STDIN=''
it_stub_fzf() {
	emulate -L zsh
	[[ -z $IT_STUBDIR ]] || return 0
	local REPLY
	fixture_tmpdir fzfstub || return 1
	IT_STUBDIR=$REPLY
	IT_FZF_ARGV="$IT_STUBDIR/argv"
	IT_FZF_STDIN="$IT_STUBDIR/stdin"
	print -rl -- \
		'#!/bin/sh' \
		'# hop test stub: records the call, draws nothing, exits 1 like fzf on no match.' \
		': > "$HOP_FZF_ARGV"' \
		'for a in "$@"; do printf "%s\n" "$a" >> "$HOP_FZF_ARGV"; done' \
		'cat > "$HOP_FZF_STDIN"' \
		'exit ${HOP_FZF_EXIT:-1}' > "$IT_STUBDIR/fzf"
	chmod +x "$IT_STUBDIR/fzf" || return 1
	return 0
}

# it_run_stub <code> [VAR=value...] -> it_run with the recording fzf shadowing the real one.
# - _hop_tty_ok is forced true, because hop refuses the picker outright with no controlling terminal.
# - A CI runner and an agent's shell both lack one, and neither can be given one cheaply here.
# - The stub fzf is already a fiction that draws nothing and exits on demand, so the tty is the same one.
# - Without this a probe silently resolves headlessly, and any flag assertion inspects THAT call.
# - Overridden in the CHILD rather than the product, so no environment variable can weaken the guard.
it_run_stub() {
	emulate -L zsh
	it_stub_fzf || return 1
	local code=$1
	shift
	it_run "_hop_tty_ok() { return 0 }
${code}" "PATH=${IT_STUBDIR}:${PATH}" \
		"HOP_FZF_ARGV=${IT_FZF_ARGV}" "HOP_FZF_STDIN=${IT_FZF_STDIN}" "$@"
}

# it_nobat_path -> a PATH holding only what bin/hop-preview needs, with no bat on it.
# - bat may or may not be installed here, and a machine that has it must not silently skip the test.
# - env resolves the `#!/usr/bin/env zsh` shebang through PATH, so zsh has to be one of the links.
typeset -g IT_NOBAT=''
it_nobat_path() {
	emulate -L zsh
	[[ -z $IT_NOBAT ]] || return 0
	local REPLY
	fixture_tmpdir nobat || return 1
	IT_NOBAT=$REPLY
	local c
	for c in zsh git head; do
		[[ -n ${commands[$c]} ]] || return 1
		ln -sf -- "${commands[$c]}" "$IT_NOBAT/$c" || return 1
	done
	return 0
}

# it_preview <arg...> -> bin/hop-preview with bat unreachable; stderr lands in IT_ERRFILE.
it_preview() {
	emulate -L zsh
	it_nobat_path || return 1
	hop_bound 20 env "PATH=${IT_NOBAT}" \
		"$HOP_HOME/bin/hop-preview" "$@" 2>"$IT_ERRFILE"
}

typeset out rows bad d q f line
typeset -i cnt cnt_root cnt_sub st n

typeset -i HAVE_FZF=0
[[ -n $IT_FZF ]] && HAVE_FZF=1

# ---------------------------------------------------------------------------
# The repo everything below is asserted against.
# ---------------------------------------------------------------------------
# Big enough to have a unique query, a fuzzy-overmatch pair, and a narrowable subtree.
typeset -g MAIN
fixture_repo main
MAIN=$REPLY

fixture_write 'README.md' '# integration fixture'

fixture_write 'terraform/platform/production/us-west-2/network/terragrunt.hcl' 'include {}'
fixture_write 'terraform/platform/production/us-west-2/network/main.tf' 'resource "null_resource" "a" {}'
fixture_write 'terraform/platform/production/us-west-2/queueing/terragrunt.hcl' 'include {}'
fixture_write 'terraform/platform/production/us-west-2/queueing/main.tf' 'resource "null_resource" "b" {}'
fixture_write 'terraform/platform/staging/us-west-2/network/terragrunt.hcl' 'include {}'
fixture_write 'terraform/platform/staging/us-west-2/network/main.tf' 'resource "null_resource" "c" {}'

# An exact/fuzzy pair: 'abg' is a substring of one name and a subsequence of the other.
fixture_write 'terraform/sandbox/abg/terragrunt.hcl' 'include {}'
fixture_write 'terraform/sandbox/abg/main.tf' 'resource "null_resource" "d" {}'
fixture_write 'terraform/sandbox/alpha-beta-gamma/terragrunt.hcl' 'include {}'
fixture_write 'terraform/sandbox/alpha-beta-gamma/main.tf' 'resource "null_resource" "e" {}'

fixture_write 'terraform/modules/cloud/network/main.tf' 'variable "x" {}'
fixture_write 'kubernetes/values/widget/values.yaml' 'image: widget'
fixture_write 'kubernetes/values/gizmo/values.yaml' 'image: gizmo'

fixture_commit 'initial'

# ---------------------------------------------------------------------------
# Enumeration, and the performance budget that keeps `hop` feeling instant.
# ---------------------------------------------------------------------------
typeset -F t0 t1
t0=${EPOCHREALTIME:-0}
out=$(it_gen "$MAIN" tg mod helm dir)
t1=${EPOCHREALTIME:-0}
print -r -- "$out" > "$IT_ROWS"
cnt_root=$(it_count "$out")

typeset -i ELAPSED_MS=$(( (t1 - t0) * 1000 ))
typeset verdict=over
(( ELAPSED_MS <= 5000 )) && verdict=under

# A test NAME must be byte-identical across runs, so a measured value belongs in the failure detail.
# - A name carrying a duration cannot be addressed by HOP_T_FILTER, since you cannot predict it.
# - It also defeats diffing one run's names against another's, which is how a phantom delta appears.
# The budget is deliberately loose, because a tight one buys nothing here and costs intermittency.
# - This fixture yields 11 targets, so complexity cannot show: O(n squared) over 11 is still 121.
# - Measured on 18 cores, enumeration is 61-75ms idle and 149ms under real contention.
# - A shared CI runner has 2 to 4 cores, so 1000ms was untested headroom rather than known headroom.
# - A subprocess costs about 9ms here, so a per-row fork storm was already invisible at 1000ms.
# - What this still catches is a hang or a per-row cost heavy enough to make hop feel slow.
# - An intermittent red teaches a maintainer to ignore red, which is worse than a loose bound.
t 'default-kind enumeration is under its 5000ms budget'
assert_eq under "$verdict" "enumeration took ${ELAPSED_MS}ms against a 5000ms budget"

t 'default-kind enumeration yields every target in the fixture, silently'
assert_eq 11 $cnt_root 'five tg units, one module, two values dirs, and root plus two dir rows'
assert_eq 0 "$(it_errbytes)" "enumeration wrote to stderr: $(it_err)"

t 'every enumerated row carries an absolute dir that exists'
bad=''
for d in "${(@f)$(it_dirs "$out")}"; do
	[[ $d == /* && -d $d ]] || bad=$d
done
assert_empty "$bad" 'a row whose dir field is not an existing absolute path'

# ---------------------------------------------------------------------------
# --select-1: the fast path, and the single most valuable behaviour in the tool.
# ---------------------------------------------------------------------------
# A non-unique query would make real fzf try to draw, so uniqueness is asserted BEFORE hop runs.
if (( HAVE_FZF )); then
	typeset -A EXPECT=(
		'queueing'    "$MAIN/terraform/platform/production/us-west-2/queueing"
		'network staging' "$MAIN/terraform/platform/staging/us-west-2/network"
	)
	for q in "${(@ko)EXPECT}"; do
		rows=$(it_filter "$q" "$IT_ROWS")
		cnt=$(it_count "$rows")

		t "'${q}' matches exactly one row under --exact"
		assert_eq 1 $cnt 'uniqueness is what makes --select-1 safe to test headlessly'

		if (( cnt == 1 )); then
			t "hop ${q} cds straight to the match with no interaction"
			out=$(it_run "cd ${(q)MAIN} || exit 96
hop ${q} || exit 95
print -r -- \$PWD")
			st=$?
			assert_eq 0 $st "hop exited ${st}; stderr: $(it_err)"
			assert_eq "${EXPECT[$q]}" "$out"
			assert_eq 0 "$(it_errbytes)" "the fast path must be silent: $(it_err)"
		else
			skip "hop ${q} cds straight to the match with no interaction" \
				"the query matched ${cnt} rows, and driving real fzf is forbidden"
		fi
	done
else
	skip 'hop <unique query> cds straight to the match' 'fzf is not installed'
fi

# ---------------------------------------------------------------------------
# --exact: asserted on the flags hop really passes, then priced against the fuzzy alternative.
# ---------------------------------------------------------------------------
# The recorded argv has to be the PICKER's, and saying which call is inspected is half the assertion.
# - hop resolves headlessly through `fzf --filter` when /dev/tty cannot be opened, as in CI.
# - That call passes --exact as well, so this pair once went green against the wrong invocation.
# - it_run_stub forces the tty predicate true for exactly that reason; these tests prove it worked.
# - Counting exact matches rather than taking an index: a floor admits any index and hides absence.
it_run_stub "cd ${(q)MAIN} || exit 96
hop -k tg" >/dev/null
typeset -a ARGV=()
[[ -r ${IT_FZF_ARGV:-} ]] && ARGV=("${(@f)$(it_slurp "$IT_FZF_ARGV")}")

t 'the recorded fzf call is the interactive picker, not the headless matcher'
assert_eq 0 ${#${(M)ARGV:#--filter=*}} 'a --filter in the argv means the probe never reached the picker'
assert_eq 1 ${#${(M)ARGV:#--expect=*}} 'the picker is the call that passes --expect, so it must be here'

t 'the picker passes --exact to fzf'
assert_eq 1 ${#${(M)ARGV:#--exact}} 'without --exact, fuzzy matching over a ~90-column line overmatches'

t 'the picker passes --select-1, which is what makes a unique query jump'
assert_eq 1 ${#${(M)ARGV:#--select-1}} 'the fast path is --select-1 and nothing else'

if (( HAVE_FZF )); then
	typeset -i xn fn
	xn=$(it_count "$(it_filter 'abg' "$IT_ROWS")")
	fn=$(it_count "$(it_filter_fuzzy 'abg' "$IT_ROWS")")

	t "--exact narrows 'abg' to a single row where fuzzy matches several"
	assert_eq 1 $xn "exact matching is what makes this query a single row, got ${xn}"
	assert_ge $fn 2 "if fuzzy also returned one row this guard has stopped guarding, got ${fn}"
else
	# The skip must carry the SAME name as the t above, or the name varies by environment instead.
	skip "--exact narrows 'abg' to a single row where fuzzy matches several" 'fzf is not installed'
fi

# ---------------------------------------------------------------------------
# -c/--cwd: one flag that narrows EVERY kind to the subtree you are standing in.
# ---------------------------------------------------------------------------
typeset SUB="$MAIN/terraform/sandbox"

it_run_stub "cd ${(q)SUB} || exit 96
hop -c" >/dev/null
rows=''
[[ -r ${IT_FZF_STDIN:-} ]] && rows=$(it_slurp "$IT_FZF_STDIN")
cnt_sub=$(it_count "$rows")

t 'hop -c in a subtree shows fewer rows than the repo root'
assert_ge $cnt_sub 1 'the subtree does hold targets, so an empty list is a bug'
assert_eq 1 $(( cnt_sub < cnt_root )) "scoping must strictly narrow: ${cnt_sub} vs ${cnt_root}"

t 'every row hop -c offers is inside $PWD'
bad=''
for d in "${(@f)$(it_dirs "$rows")}"; do
	[[ $d == $SUB || $d == $SUB/* ]] || bad=$d
done
assert_empty "$bad" 'a scoped row escaped the cwd'

t 'hop -c with no match in the subtree says so and returns non-zero'
out=$(it_run_stub "cd ${(q)MAIN}/kubernetes || exit 96
hop -c -k tg")
st=$?
assert_eq 1 $st 'a no-match must be a failure status, not a silent success'
assert_empty "$out" 'the message belongs on stderr'
assert_contains "$(it_err)" 'no targets under' 'the error must name what was scoped away'
assert_contains "$(it_err)" 'kubernetes' 'the error must name the directory'
assert_eq 1 $(it_count "$(it_err)") 'one clear line, never a shell traceback'

# ---------------------------------------------------------------------------
# hopr and hopw, the two entry points that never open a picker at all.
# ---------------------------------------------------------------------------
typeset WS WSREPO ELSEWHERE
fixture_tmpdir workspace
WS=$REPLY
mkdir -p -- "$WS/proj/deep/deeper"
_hop_fix_git -C "$WS/proj" init -q -b main
WSREPO="$WS/proj"

t 'hopr cds to the repo root from a nested directory'
out=$(it_run "cd ${(q)WSREPO}/deep/deeper || exit 96
hopr || exit 95
print -r -- \$PWD")
st=$?
assert_eq 0 $st "hopr exited ${st}; stderr: $(it_err)"
assert_eq "$WSREPO" "$out"

t 'hopr outside a git repo says so and returns non-zero'
out=$(it_run "cd ${(q)WS} || exit 96
hopr")
st=$?
assert_eq 1 $st 'no repo means failure, not a silent no-op'
assert_contains "$(it_err)" 'not in a git repository'

t 'hopw cds to the workspace containing $PWD'
out=$(it_run "cd ${(q)WSREPO}/deep || exit 96
hopw || exit 95
print -r -- \$PWD" "HOP_WORKSPACES=${WS}")
st=$?
assert_eq 0 $st "hopw exited ${st}; stderr: $(it_err)"
assert_eq "$WS" "$out"

t 'hopw outside every configured workspace errors cleanly'
fixture_tmpdir elsewhere
ELSEWHERE=$REPLY
out=$(it_run "cd ${(q)ELSEWHERE} || exit 96
hopw" "HOP_WORKSPACES=${WS}")
st=$?
assert_eq 1 $st 'outside a workspace is a failure'
assert_empty "$out"
assert_contains "$(it_err)" 'is not inside any configured workspace'
assert_eq 1 $(it_count "$(it_err)") 'one line, no traceback'

# ---------------------------------------------------------------------------
# A scratch repo that matches nothing: one line, non-zero, no hang.
# ---------------------------------------------------------------------------
typeset SCRATCH
fixture_repo scratch
SCRATCH=$REPLY
fixture_write 'notes.txt' 'nothing here resembles an infrastructure repo'
fixture_commit 'initial'

t 'a scratch repo produces no rows for the shaped kinds'
out=$(it_gen "$SCRATCH" tg mod helm serverless)
assert_eq 0 $(it_count "$out") 'no family is present, so no kind may invent a row'
assert_eq 0 "$(it_errbytes)" "a kind complained about an absent family: $(it_err)"

t 'hop in a scratch repo degrades to one stderr line and a non-zero exit'
out=$(it_run_stub "cd ${(q)SCRATCH} || exit 96
hop -k tg,mod,helm,serverless")
st=$?
assert_eq 1 $st 'nothing to show is a failure status'
assert_empty "$out"
assert_contains "$(it_err)" 'no targets in' 'the message must say where it looked'
assert_eq 1 $(it_count "$(it_err)") 'one clear line, never a traceback'

t 'the dir kind still gets a scratch repo out of trouble'
out=$(it_gen "$SCRATCH" dir)
assert_ge $(it_count "$out") 1 'the repo root row is the floor hop never drops below'
assert_contains "$out" '<root>'

# ---------------------------------------------------------------------------
# Worktree correctness: enumerated paths must point INTO the worktree.
# ---------------------------------------------------------------------------
typeset WTMAIN WTREE
fixture_repo wtmain
WTMAIN=$REPLY
fixture_write 'terraform/sandbox/vpc/terragrunt.hcl' 'include {}'
fixture_write 'terraform/sandbox/vpc/main.tf' 'resource "null_resource" "x" {}'
fixture_write 'kubernetes/values/widget/values.yaml' 'image: widget'
fixture_commit 'initial'

fixture_tmpdir wtholder
WTREE="$REPLY/checkout"
_hop_fix_git -C "$WTMAIN" worktree add -q -b wt "$WTREE" 2>/dev/null

t 'the worktree fixture is a real second checkout'
assert_file "$WTREE/terraform/sandbox/vpc/terragrunt.hcl"
assert_eq "$WTREE" "$(_hop_fix_git -C "$WTREE" rev-parse --show-toplevel)"

t 'enumerating a worktree yields paths inside the worktree, never the main checkout'
out=$(it_gen "$WTREE" tg helm dir)
assert_ge $(it_count "$out") 3 'the worktree has a tg unit, a values dir and its dir rows'
bad=''
for d in "${(@f)$(it_dirs "$out")}"; do
	[[ $d == $WTREE || $d == $WTREE/* ]] || bad=$d
done
assert_empty "$bad" 'a worktree row pointed outside the worktree'
assert_not_contains "$out" "$WTMAIN/" 'no row may name the main checkout'

t 'the worktree preview target is the worktree copy of the file'
assert_contains "$out" "$WTREE/terraform/sandbox/vpc/main.tf"

# ---------------------------------------------------------------------------
# become() is banned: it replaces the fzf process, and only the parent shell can cd.
# ---------------------------------------------------------------------------
# Comment lines are stripped first, because ui.zsh documents the ban in a comment.
fixture_sources shipped
typeset -a SRC=("${reply[@]}")

# This runs FIRST: a typo'd glob once dropped all of lib/ while the old numeric floor stayed happy.
t 'every component of the become() scan list found files'
assert_empty "$REPLY" 'a mistyped glob would make the become() scan vacuous'

t 'no become() anywhere in the executable source'
bad=''
for f in "${SRC[@]}"; do
	while IFS= read -r line; do
		[[ ${line##[[:space:]]#} == '#'* ]] && continue
		[[ $line == *'become('* ]] && bad="${f#${HOP_HOME}/}: ${line}"
	done < "$f"
done
assert_empty "$bad" 'become() destroys the return path hop needs in order to cd'

# ---------------------------------------------------------------------------
# bin/hop-preview with bat absent: five shapes, always exit 0 and always silent.
# ---------------------------------------------------------------------------
# fzf renders preview stderr inside the pane, so one stray byte is a visible artefact.
it_nobat_path

t 'the no-bat PATH really has no bat on it'
typeset BATPATH
BATPATH=$(hop_bound 10 env "PATH=${IT_NOBAT}" \
	zsh -f -c 'print -rn -- ${commands[bat]:-}' 2>&1)
assert_empty "$BATPATH" 'the test only means something when bat is unreachable'

t 'hop-preview on a directory exits 0 with empty stderr'
out=$(it_preview "$IT_WORK")
st=$?
assert_eq 0 $st
assert_eq 0 "$(it_errbytes)" "stderr: $(it_err)"
assert_contains "$out" 'directory listing'

t 'hop-preview on a text file exits 0 with empty stderr and shows the content'
print -rl -- '# hello from the fixture' 'second line' > "$SCRATCH/preview-me.md"
out=$(it_preview "$SCRATCH" "$SCRATCH/preview-me.md")
st=$?
assert_eq 0 $st
assert_eq 0 "$(it_errbytes)" "stderr: $(it_err)"
assert_contains "$out" 'hello from the fixture'

t 'hop-preview on a missing path exits 0 with empty stderr and one warning'
out=$(it_preview "$SCRATCH" "$SCRATCH/definitely-absent.yaml")
st=$?
assert_eq 0 $st
assert_eq 0 "$(it_errbytes)" "stderr: $(it_err)"
assert_contains "$out" 'does not exist'

t 'hop-preview with no arguments exits 0 with empty stderr'
out=$(it_preview)
st=$?
assert_eq 0 $st
assert_eq 0 "$(it_errbytes)" "stderr: $(it_err)"
assert_contains "$out" 'nothing to preview'

t 'hop-preview --keys renders both modes for the ? overlay'
out=$(it_preview --keys)
st=$?
assert_eq 0 $st
assert_eq 0 "$(it_errbytes)" "stderr: $(it_err)"
assert_contains "$out" 'NORMAL'
assert_contains "$out" 'SEARCH'

# ---------------------------------------------------------------------------
# A real checkout, only when one is named.
# ---------------------------------------------------------------------------
# This is the one thing a fixture cannot show: that hop stays fast and quiet at real scale.
# - Set HOP_TEST_REPO=/path/to/a/large/checkout to turn these on.
typeset -g TESTREPO=${HOP_TEST_REPO:-}

if [[ -n $TESTREPO && -d $TESTREPO/.git ]]; then
	t0=${EPOCHREALTIME:-0}
	out=$(it_gen "$TESTREPO" tg mod helm dir)
	t1=${EPOCHREALTIME:-0}
	ELAPSED_MS=$(( (t1 - t0) * 1000 ))
	verdict=over
	(( ELAPSED_MS <= 10000 )) && verdict=under

	# Looser than the fixture's budget, and for a stronger reason than load: the INPUT is unknown.
	# - $HOP_TEST_REPO is whatever checkout you point it at, so its row count is not controlled.
	# - A fixed bound over an uncontrolled input asserts repo SIZE while claiming to assert speed.
	# - Aimed at a large monorepo a tight bound goes red saying nothing about a regression.
	t 'real checkout: default-kind enumeration is under its 10000ms budget'
	assert_eq under "$verdict" "enumeration took ${ELAPSED_MS}ms at real scale"

	t 'real checkout: enumeration is silent on stderr'
	assert_eq 0 "$(it_errbytes)" "enumeration wrote to stderr: $(it_err)"

	t 'real checkout: every row carries an absolute dir that exists'
	bad=''
	for d in "${(@f)$(it_dirs "$out")}"; do
		[[ $d == /* && -d $d ]] || bad=$d
	done
	assert_empty "$bad" 'a row whose dir field is not an existing absolute path'
else
	skip 'real checkout: hop stays fast and quiet at real scale' \
		'set HOP_TEST_REPO to a git checkout to enable these'
fi
