#!/usr/bin/env zsh
# hop with NO controlling terminal: the picker must not be launched, and must not hang.
# - fzf 0.73.1 does not error when /dev/tty cannot be opened; it blocks forever writing nothing.
# - Measured before the fix: 8.03s to the bound, 0 bytes on stdout, 0 bytes on stderr.
# - So every probe here is bounded by perl, and a bound that fires IS the failure being tested.
# - The bound is fork + POSIX::setsid + parent alarm + KILL of the NEGATIVE pid, per tests/run.
# - setsid rather than setpgrp, because dropping the ctty is the whole condition under test.
# - The alarm stays in the parent, which the child cannot reach, so a trapped ALRM cannot defeat it.
# - KILL and never TERM: a TERM would run an inherited EXIT trap in somebody else's fork.
# - Nothing here starts interactive fzf, and `--filter` is the only mode the fix itself uses.

typeset -gi NT_SECS=${NT_SECS:-8}
typeset -g  NT_BOUND=''
typeset -g  NT_REPO4='' NT_REPO1=''
typeset -g  NT_OUT='' NT_ERR='' NT_ST='' NT_PWD=''
typeset -gi NT_HUNG=0

stub_bin

# ---------------------------------------------------------------------------
# The bound, and the two fixture repos.
# ---------------------------------------------------------------------------
# nt_setup -> write the perl bound and build both repos, or return non-zero.
# - FOUR units in the first repo, because --select-1 makes a ONE-row list auto-accept.
# - An earlier no-tty investigation burned a whole experiment on a one-row fixture that proved nothing.
# - The second repo has exactly one unit, because that auto-accept is itself a case worth testing.
nt_setup() {
	emulate -L zsh
	local REPLY
	fixture_tmpdir nttools || return 1
	NT_BOUND="$REPLY/bound.pl"
	print -rl -- \
		'use POSIX ();' \
		'my $secs = shift @ARGV;' \
		'my $pid  = fork();' \
		'die "fork: $!" unless defined $pid;' \
		'if ($pid == 0) { POSIX::setsid(); exec @ARGV; exit 127 }' \
		'$SIG{ALRM} = sub { kill("KILL", -$pid); kill("KILL", $pid); waitpid($pid, 0); exit 142 };' \
		'alarm $secs;' \
		'waitpid($pid, 0);' \
		'my $st = $?;' \
		'alarm 0;' \
		'exit($st & 127 ? 128 + ($st & 127) : $st >> 8);' > "$NT_BOUND" || return 1

	fixture_repo nt4 || return 1
	local u
	for u in alpha bravo charlie delta; do
		fixture_write "terraform/${u}/vpc/terragrunt.hcl" "# unit ${u}" || return 1
	done
	fixture_commit 'four units' || return 1
	NT_REPO4=$HOP_FIX_REPO

	fixture_repo nt1 || return 1
	fixture_write 'terraform/solo/vpc/terragrunt.hcl' '# unit solo' || return 1
	fixture_commit 'one unit' || return 1
	NT_REPO1=$HOP_FIX_REPO
	return 0
}

# nt_pins -> the pins fixture_pins does NOT cover, each one able to reach the real user otherwise.
# - fixture_pins already handles HOME, the XDG roots, HOP_CONFIG, HOP_HOPRC, HOP_DEBUG and PATH.
# - FZF_DEFAULT_OPTS is the load-bearing one here: it would inject flags into the --filter call.
# - An injected --literal or --no-exact there would change which rows match and how many.
# - HOP_WORKSPACES is pinned empty so the workspace probe can set it and be the only thing that does.
# - HOP_FZF_HEIGHT is unset rather than empty, because the default 80% is the shape that hangs.
# - HOP_VIM is unset so each probe exercises hop's own default rather than an inherited value.
nt_pins() {
	emulate -L zsh
	print -rl -- \
		"export HOP_DEBUG_LOG=${(q)HOP_FIX_HOME}/.local/state/hop/debug.log" \
		"export HOP_WORKSPACES=''" \
		"export HOP_WORKSPACES_FILE=${(q)HOP_FIX_HOME}/.config/hop/workspaces" \
		"export HOP_REPOS='' HOP_DEFAULT_KINDS='' HOP_CLIPBOARD='' HOP_HIST_MAX='' HOP_FZF_MIN=''" \
		"export FZF_DEFAULT_COMMAND='' FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null" \
		'unset HOP_FZF_HEIGHT' \
		'unset HOP_VIM'
}

# nt_run <hop-command> <repo> [extra-export-line...] -> run it with no ctty, bounded.
# - Fills NT_HUNG, NT_ST, NT_OUT, NT_ERR and NT_PWD; NT_HUNG=1 means the bound had to kill it.
# - stdin is /dev/null on purpose: the point is that stdin is NOT what makes the picker work.
# - The extra lines come last, so a probe can override any pin above it.
nt_run() {
	emulate -L zsh
	local cmd=$1 repo=$2
	shift 2
	local REPLY
	fixture_tmpdir ntrun || return 1
	local d=$REPLY
	local of="$d/out" ef="$d/err" sf="$d/st" pf="$d/pwd"
	: > "$of"
	: > "$ef"

	print -rl -- \
		"$(fixture_pins)" \
		"$(nt_pins)" \
		"$@" \
		"source ${(q)HOP_HOME}/hop.zsh || exit 97" \
		"builtin cd -q -- ${(q)repo} || exit 96" \
		"eval ${(q)cmd} > ${(q)of} 2> ${(q)ef} < /dev/null" \
		"print -r -- \$? > ${(q)sf}" \
		"print -r -- \$PWD > ${(q)pf}" \
		'exit 0' > "$d/child.zsh" || return 1

	perl "$NT_BOUND" "$NT_SECS" zsh -f "$d/child.zsh"
	local -i bst=$?
	NT_HUNG=0
	(( bst == 142 )) && NT_HUNG=1
	NT_ST=''
	NT_PWD=''
	[[ -s $sf ]] && read -r NT_ST < "$sf"
	[[ -s $pf ]] && read -r NT_PWD < "$pf"
	NT_OUT=$(<"$of")
	NT_ERR=$(<"$ef")
	return 0
}

if ! (( ${+commands[perl]} )); then
	skip 'no controlling terminal' 'perl is the bound on this box, and an unbounded probe could hang forever'
	skip 'the tty predicate under a real pty' 'needs the bounded probes above to be meaningful'
	return 0
fi

if ! nt_setup; then
	t 'the fixture built'
	assert_eq 'built' 'failed' 'nt_setup could not write the bound or build the repos'
	return 0
fi

# ---------------------------------------------------------------------------
# The hang is gone: a query that cannot be resolved alone now explains itself.
# ---------------------------------------------------------------------------
t 'no ctty, MULTI-match query: a diagnostic naming the count, not a hang'
nt_run 'hop -k tg vpc' "$NT_REPO4"
assert_eq 0 "$NT_HUNG" 'the bound had to kill it, so hop still hangs with no terminal'
assert_eq 1 "$NT_ST" 'a query needing a human must fail, not succeed and not hang'
assert_contains "$NT_ERR" 'no terminal available' 'the message has to name the actual cause'
assert_contains "$NT_ERR" '4 targets matched the query: vpc' 'the COUNT is what ends the bug hunt'
assert_eq '' "$NT_OUT" 'a diagnostic belongs on stderr, so stdout stays usable in a pipeline'
assert_eq "$NT_REPO4" "$NT_PWD" 'an unresolvable query must leave the shell where it was'

t 'no ctty, EMPTY query: the diagnostic still names the count'
nt_run 'hop -k tg' "$NT_REPO4"
assert_eq 0 "$NT_HUNG" 'the bound had to kill it, so an empty query still hangs'
assert_eq 1 "$NT_ST"
assert_contains "$NT_ERR" 'no terminal available'
assert_contains "$NT_ERR" '4 targets matched, and picking one needs a terminal'
assert_eq "$NT_REPO4" "$NT_PWD"

# A typo'd query hung too, which is the second and likelier trigger for this whole bug.
# - _hop_pick passes no --exit-0, deliberately, so the picker opens for the typo to be corrected.
# - With no terminal there is nobody to correct it, so zero matches has to fail loudly instead.
t 'no ctty, ZERO-match query: says nothing matched rather than hanging'
nt_run 'hop -k tg zzzz' "$NT_REPO4"
assert_eq 0 "$NT_HUNG" 'the bound had to kill it, so a typo still hangs with no terminal'
assert_eq 1 "$NT_ST"
assert_contains "$NT_ERR" 'no terminal available'
assert_contains "$NT_ERR" 'nothing matched the query: zzzz'
assert_eq "$NT_REPO4" "$NT_PWD"

# ---------------------------------------------------------------------------
# The working case still works, which is the constraint the whole design is built around.
# ---------------------------------------------------------------------------
# `hop -k tg alpha` with no ctty returns in ~0.1s and cds, because --select-1 never needs a terminal.
# - A guard placed in FRONT of the picker would refuse this, and that is why there is no such guard.
t 'no ctty, UNIQUE-match query: still cds, exactly as before the fix'
nt_run 'hop -k tg alpha' "$NT_REPO4"
assert_eq 0 "$NT_HUNG"
assert_eq 0 "$NT_ST" 'a unique match from a script must still succeed'
assert_eq "${NT_REPO4}/terraform/alpha/vpc" "$NT_PWD" 'it has to cd to the one matching target'
assert_eq '' "$NT_ERR" 'a case that works must stay silent'
assert_eq '' "$NT_OUT"

# The real rule is "exactly one match", not "a query was given", and this is the case that proves it.
t 'no ctty, ONE-ROW list and an EMPTY query: still cds'
nt_run 'hop -k tg' "$NT_REPO1"
assert_eq 0 "$NT_HUNG"
assert_eq 0 "$NT_ST" 'one row auto-accepts today, with no query at all, and must keep doing so'
assert_eq "${NT_REPO1}/terraform/solo/vpc" "$NT_PWD"
assert_eq '' "$NT_ERR"

# ---------------------------------------------------------------------------
# The second picker entry point: _hop_ws_picker reaches _hop_pick without going through _hop_run.
# ---------------------------------------------------------------------------
# A check covering only _hop_run would be a partial fix, so the workspace level gets its own probe.
t 'no ctty, WORKSPACE picker: a diagnostic naming the count, not a hang'
nt_run 'hop -w' "$NT_REPO4" "export HOP_WORKSPACES=${(q)NT_REPO4}:${(q)NT_REPO1}"
assert_eq 0 "$NT_HUNG" 'the bound had to kill it, so the workspace picker still hangs'
assert_eq 1 "$NT_ST"
assert_contains "$NT_ERR" 'no terminal available'
assert_contains "$NT_ERR" '2 targets matched, and picking one needs a terminal'
assert_eq "$NT_REPO4" "$NT_PWD"

# ---------------------------------------------------------------------------
# --filter and --select-1 have to agree about what "unique" means, or the fix is subtly wrong.
# ---------------------------------------------------------------------------
# --select-1 fires when exactly one row matches, and --filter prints every row that matches.
# - So "exactly one line out of --filter" is the same condition, given the same matcher flags.
# - --disabled is the one flag --filter ignores, and _hop_pick adds it ONLY for an empty query.
# - With an empty query every row matches either way, so that discrepancy is unreachable.
export NT_REPO4
t '--filter and --select-1 agree on what "unique" means'
typeset NT_AGREE
NT_AGREE=$(hop_probe '
builtin cd -q -- "$NT_REPO4" || exit 96
typeset targets q
typeset -i n
targets=$(_hop_generate "$PWD" tg)
for q in alpha vpc zzzz ""; do
	n=$(print -r -- "$targets" | fzf --filter="$q" --delimiter=$'"'"'\t'"'"' \
		--with-nth=1 --accept-nth=2,3 --exact --tiebreak=begin,length | grep -c .)
	print -r -- "${q:-<empty>}=${n}"
done')
assert_eq 'alpha=1
vpc=4
zzzz=0
<empty>=4' "$NT_AGREE" 'the headless matcher must count rows exactly as --select-1 would'

# ---------------------------------------------------------------------------
# The predicate itself: a terminal, not stdin, is what it reads.
# ---------------------------------------------------------------------------
# fzf reads keys from /dev/tty and never from stdin, which is why every redirected shape works today.
# - `hop < /dev/null`, `hop | cat`, `echo x | hop` and `hop 0<&-` all keep their controlling terminal.
# - A guard written against stdin would refuse all four, so this pins the predicate in both directions.
typeset -g NT_SHAPES=''
NT_SHAPES=$(print -rl -- \
	"source ${(q)HOP_HOME}/hop.zsh || exit 97" \
	'{' \
	"	if _hop_tty_ok;                   then print -r -- 'plain=OPEN';      else print -r -- 'plain=CLOSED';      fi" \
	"	if _hop_tty_ok < /dev/null;       then print -r -- 'devnull=OPEN';    else print -r -- 'devnull=CLOSED';    fi" \
	"	if _hop_tty_ok 0<&-;              then print -r -- 'closedfd=OPEN';   else print -r -- 'closedfd=CLOSED';   fi" \
	"	if print -rn -- '' | _hop_tty_ok; then print -r -- 'pipedstdin=OPEN'; else print -r -- 'pipedstdin=CLOSED'; fi" \
	'} > "$NT_RES"' \
	"{ if _hop_tty_ok; then print -r -- 'pipeout=OPEN'; else print -r -- 'pipeout=CLOSED'; fi } | cat >> \"\$NT_RES\"")

typeset -g NT_WANT_OPEN='plain=OPEN
devnull=OPEN
closedfd=OPEN
pipedstdin=OPEN
pipeout=OPEN'

t 'no ctty: the predicate is false in every redirected shape'
typeset NT_CLOSED_RES=''
if fixture_tmpdir ntshapes; then
	typeset ntd=$REPLY
	print -rl -- "$(fixture_pins)" "$(nt_pins)" "export NT_RES=${(q)ntd}/res" "$NT_SHAPES" > "$ntd/shapes.zsh"
	: > "$ntd/res"
	perl "$NT_BOUND" "$NT_SECS" zsh -f "$ntd/shapes.zsh" < /dev/null > /dev/null 2>&1
	NT_CLOSED_RES=$(<"$ntd/res")
fi
assert_eq 'plain=CLOSED
devnull=CLOSED
closedfd=CLOSED
pipedstdin=CLOSED
pipeout=CLOSED' "$NT_CLOSED_RES" 'with no ctty every shape must be false, whatever stdin is'

# zpty is the only way to manufacture a controlling terminal here, and it starts no fzf at all.
# - The suite process itself may have no ctty: an agent's shell and a CI runner both lack one.
# - So the positive direction cannot be tested in-process, and without a pty it has to skip.
# - Only `zpty -d` is ever used to tear this down, never TERM, and the child exits on its own.
if zmodload zsh/zpty 2>/dev/null && fixture_tmpdir ntpty; then
	typeset ntp=$REPLY
	print -rl -- "$(fixture_pins)" "$(nt_pins)" "export NT_RES=${(q)ntp}/res" "$NT_SHAPES" > "$ntp/shapes.zsh"
	: > "$ntp/res"
	typeset NT_PTY_RES='' junk
	typeset -F spent=0
	zpty -b NTPTY "zsh -f ${ntp}/shapes.zsh"
	while (( spent < NT_SECS )); do
		while zpty -r -t NTPTY junk 2>/dev/null; do :; done
		[[ -s $ntp/res ]] && (( $(grep -c . "$ntp/res") == 5 )) && break
		sleep 0.02
		(( spent += 0.02 ))
	done
	zpty -d NTPTY 2>/dev/null
	NT_PTY_RES=$(<"$ntp/res")

	t 'a ctty present: the predicate is true in every redirected shape'
	assert_eq "$NT_WANT_OPEN" "$NT_PTY_RES" 'a stdin test would report CLOSED here and refuse four working shapes'
else
	skip 'a ctty present: the predicate is true in every redirected shape' 'zsh/zpty did not load, so no ctty can be manufactured'
fi
