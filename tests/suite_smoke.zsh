#!/usr/bin/env zsh
# suite_smoke: the harness proving itself, plus the three checks nothing else should ever break.
# - Every shipped file parses under `zsh -n`, which is the cheapest guard against a bad edit.
# - The two bin/ helpers are executable, since fzf runs them as commands and not as source.
# - Sourcing hop.zsh in a bare shell defines the three public entry points.

# ---------------------------------------------------------------------------
# Every file parses.
# ---------------------------------------------------------------------------
# Directories are read whole rather than listed, so a new file is covered free.
fixture_sources parseable
typeset -a parseable=("${reply[@]}")

# This runs BEFORE the parse loop, because a short list makes every check below vacuous.
t 'every component of the file list found files'
assert_empty "$REPLY" 'a mistyped glob would make these parse checks vanish without a failure'

typeset f rel
for f in "${parseable[@]}"; do
	rel=${f#${HOP_HOME}/}
	t "zsh -n  ${rel}"
	assert_status 0 zsh -n "$f"
done

# ---------------------------------------------------------------------------
# The two helpers fzf execs must be executable.
# ---------------------------------------------------------------------------
t 'bin/hop-preview is executable'
assert_exec "$HOP_HOME/bin/hop-preview"

t 'bin/hop-kinds is executable'
assert_exec "$HOP_HOME/bin/hop-kinds"

# ---------------------------------------------------------------------------
# Sourcing hop.zsh defines the public entry points.
# ---------------------------------------------------------------------------
t 'sourcing hop.zsh defines hop, hopr and hopw'
typeset defined
defined=$(hop_probe 'for f in hop hopr hopw; do (( ${+functions[$f]} )) && print -r -- $f; done')
assert_eq $'hop\nhopr\nhopw' "$defined"

t 'sourcing hop.zsh in a non-interactive shell is silent'
typeset noise
noise=$(hop_probe 'true' 2>&1)
assert_empty "$noise"

# A stale HOP_HOME naming an OLD install location made `source ~/.zshrc` fail on every lib.
# - It must be overridden by this file's own path, never honoured, or a move breaks a live shell.
# - These two cannot use hop_probe, which derives HOP_HOME rather than letting a caller set it.
# - They take fixture_pins anyway: unpinned, both SOURCED the real config.zsh and ran the user's code.
# - Measured unpinned: the child registered 11 kinds instead of the shipped 8.
typeset stalepins="$(fixture_pins)"$'\n''export HOP_HOME=/nonexistent/hop'

t 'an inherited HOP_HOME naming the wrong install is overridden, not honoured'
typeset stale
stale=$(zsh -f -c "${stalepins}
source ${(q)HOP_HOME}/hop.zsh 2>&1
print -r -- \$HOP_HOME")
assert_eq "$HOP_HOME" "$stale" 'a stale HOP_HOME was honoured, so every lib source would fail'

t 'sourcing with a stale HOP_HOME emits nothing on stderr'
typeset stalenoise
stalenoise=$(zsh -f -c "${stalepins}
source ${(q)HOP_HOME}/hop.zsh" 2>&1 >/dev/null)
assert_empty "$stalenoise"

# Named once, because the registry-block assertion further down compares against the same set.
typeset -a SHIPPED_KINDS=(tg mod helm serverless puppet backstage dir file)

t 'hop --help exits 0 and lists the registry, not a hardcoded kind list'
typeset help
help=$(hop_probe 'hop --help')
assert_contains "$help" 'usage: hop'
typeset hk
for hk in "${SHIPPED_KINDS[@]}"; do
	assert_contains "$help" "$hk"
done

t 'hop --help marks the default kinds with a star and names the config path'
# The star column is what tells you which kinds a bare `hop` will search.
assert_contains "$help" '* tg'
assert_contains "$help" '* dir'
assert_contains "$help" "$HOP_FIX_NOCONFIG" 'the help must name the config file you would create'

# --doctor is the only way a bug report can carry the shell state, since fzf cannot be captured.
t 'hop --doctor exits 0 and reports install, config, tools and the confusable keys'
typeset doc
doc=$(hop_probe 'hop --doctor')
assert_contains "$doc" 'HOP_HOME'
assert_contains "$doc" 'HOP_CONFIG'
assert_contains "$doc" 'tools'
assert_contains "$doc" 'keys people mix up'

t 'hop --doctor works outside a git repo, where it is most often needed'
# This case previously carried one real assertion plus one about --help, which reported here on failure.
typeset docout
typeset -i docst
docout=$(hop_probe "builtin cd -q ${(q)HOP_FIX_TMPROOT} && hop --doctor" 2>&1)
docst=$?
assert_eq 0 $docst 'outside a repo is the case a bug reporter is most often in'
assert_contains "$docout" 'NONE, so hop opens the workspace or repo picker'
assert_contains "$docout" 'HOP_HOME' 'the install location must still be reported outside a repo'
assert_contains "$docout" 'keys people mix up'

# --doctor=short is the mode a public issue form tells reporters to paste.

# The sentinel sits in the probe's OWN $HOME, which is a fixture dir, never the real one.
t 'hop --doctor collapses $HOME to ~ and never prints it literally'
typeset dochome
dochome=$(HOP_DEBUG_LOG="${HOP_FIX_HOME}/hop-doctor-sentinel.log" hop_probe 'hop --doctor')
assert_not_contains "$dochome" "$HOP_FIX_HOME"
assert_contains "$dochome" '~/hop-doctor-sentinel.log'

# There was a literal `/Users/` scan here, and it was green for two accidents rather than one reason.
# - --doctor=short shows the INSTALL path in full on purpose, so an absolute path is expected output.
# - It only passed because HOME was inherited, which collapsed a checkout under HOME to ~.
# - On macOS CI, where the checkout IS under /Users, pinning HOME made the accident visible.
# - It could never fail on Linux either way, so the Ubuntu leg was never checking it.
# - The probe's own HOME is the whole claim, and the assert below covers every path under it.
t 'hop --doctor=short never prints $HOME, even forced to try'
typeset docshortplain
docshortplain=$(HOP_DEBUG_LOG="${HOP_FIX_HOME}/hop-doctor-sentinel.log" hop_probe 'hop --doctor=short')
assert_not_contains "$docshortplain" "$HOP_FIX_HOME"
assert_contains "$docshortplain" '(customised, withheld)' 'a forced custom path must be withheld, not shown'

t 'hop --doctor=short exits 0, inside and outside a git repo'
typeset shortrepo
fixture_repo shortmode
shortrepo=$REPLY
typeset -i shortst
hop_probe "builtin cd -q ${(q)shortrepo} && hop --doctor=short" >/dev/null
shortst=$?
assert_eq 0 "$shortst" 'inside a repo'
hop_probe "builtin cd -q ${(q)HOP_FIX_TMPROOT} && hop --doctor=short" >/dev/null
shortst=$?
assert_eq 0 "$shortst" 'outside a repo'

# - This is the test that actually proves the leak is closed.
# - A sentinel kind and workspace name must show up in full --doctor and vanish from --doctor=short.
# - The FULL-output asserts below are the control: without them a short-mode pass could be vacuous.
t 'hop --doctor=short omits a sentinel kind name and workspace name that hop --doctor shows'
typeset sentroot sentwstarget sentwsfile
fixture_repo sentinel
sentroot=$REPLY
fixture_tmpdir sentinelwstarget
sentwstarget=$REPLY
fixture_tmpdir sentinelwscfg
sentwsfile="${REPLY}/workspaces"
print -rl -- "zzsentinelws = ${sentwstarget}" > "$sentwsfile"
fixture_config 'hop_kind zzsentinel --dirs "no-such-family" --desc "sentinel kind for doctor tests"'

typeset sentfull sentshort
sentfull=$(HOP_WORKSPACES_FILE=$sentwsfile hop_probe "builtin cd -q ${(q)sentroot} && hop --doctor")
sentshort=$(HOP_WORKSPACES_FILE=$sentwsfile hop_probe "builtin cd -q ${(q)sentroot} && hop --doctor=short")
fixture_config_reset

assert_contains "$sentfull" 'zzsentinel' 'control: the sentinel kind never loaded'
assert_contains "$sentfull" 'zzsentinelws' 'control: the sentinel workspace never loaded'
assert_contains "$sentfull" "$sentwstarget" 'control: the sentinel workspace path never loaded'

assert_not_contains "$sentshort" 'zzsentinel'
assert_not_contains "$sentshort" 'zzsentinelws'
assert_not_contains "$sentshort" "$sentwstarget"

# A bare `typeset REPLY` further down would otherwise echo whatever REPLY still holds here.
unset REPLY

# ---------------------------------------------------------------------------
# --version: the release contract other tooling (hop upgrade) depends on.
# ---------------------------------------------------------------------------
t 'VERSION is a bare semver, no v prefix'
typeset ver ok
read -r ver < "$HOP_HOME/VERSION"
assert_nonempty "$ver" 'VERSION must not be empty'
if [[ $ver == <->.<->.<-> ]]; then ok=1; else ok=0; fi
assert_eq 1 "$ok" "VERSION does not match ^[0-9]+.[0-9]+.[0-9]+\$: got ${ver}"

t 'hop --version exits 0 and contains the VERSION contents'
typeset verout
verout=$(hop_probe 'hop --version')
assert_contains "$verout" "$ver"
assert_contains "$verout" 'hop '

t 'hop -V is the same as --version'
typeset vshort
vshort=$(hop_probe 'hop -V')
assert_eq "$verout" "$vshort"

t 'CHANGELOG.md keeps an Unreleased heading, so a release cannot strand entries'
typeset changelog
changelog=$(<"$HOP_HOME/CHANGELOG.md")
assert_contains "$changelog" '## [Unreleased]'

t 'hop --help does not star an opt-in kind'
# A star only means anything inside the kinds registry block, so the block is isolated first.
# - This used to select by first substring match on ' file ', which hit six lines of the help text.
# - The first of those is the usage line `hop -k file x.yml`, a static string with no star column.
# - So it could never fail: forcing mark='*' for every kind in _hop_usage left this suite 67/0.
# - Quoted (@f), not bare (f): bare drops the empty lines that delimit the block.
typeset -a helplines=("${(@f)help}")
typeset -a reglines=()
typeset hline inreg=0
for hline in "${helplines[@]}"; do
	if (( inreg )); then
		[[ -n ${hline//[[:space:]]/} ]] || break
		reglines+=("$hline")
	elif [[ $hline == *'kinds, * being in the default set:' ]]; then
		inreg=1
	fi
done
# The exact set of names in the block, not a floor on how many lines it has.
# - A floor of 2 also passed with six of the eight kinds missing, and that is the real risk:
#   a kind that never reaches the registry is invisible, since nobody reads --help in a test.
# - Names, not a count, so a rename fails here too rather than silently substituting.
# - Two-step array assignments on both sides: `${(o)a}` inside a scalar expansion does NOT sort.
typeset -a regkinds=()
for hline in "${reglines[@]}"; do
	# The line is `printf '    %s %-12s %s'`, so the name starts at column 7 and ends at a space.
	[[ $hline == '    '?' '* ]] || continue
	regkinds+=("${${hline:6}%% *}")
done
typeset -a regsorted=(${(o)regkinds}) shipsorted=(${(o)SHIPPED_KINDS})
assert_eq "${(j:,:)shipsorted}" "${(j:,:)regsorted}" 'the registry block must list every shipped kind, exactly'

# A registry line is `printf '    %s %-12s %s'`: four spaces, the mark, a space, the padded name.
# - Anchoring on those columns is what keeps a prose mention of a kind out of the match.
typeset -a filelines=(${(M)reglines:#'    '?' file '*})
assert_eq 1 $#filelines "no registry line for the file kind in: ${(j:|:)reglines}"
assert_not_contains "$filelines[1]" '*' 'file is opt-in, so it must not carry the default marker'

# ---------------------------------------------------------------------------
# The harness itself: fixtures, stubs and the probe.
# ---------------------------------------------------------------------------
# The pin list claims a new hop setting is one new line in it, and nothing enforced that claim.
# - Three helpers each kept a private list, and an unpinned HOP_FZF_MIN or HOP_REPOS walked in.
# - So the list is derived from the product here instead of trusted, and drift fails rather than leaks.
# - hop's convention is the discriminator: `_HOP_*` with a leading underscore is INTERNAL state,
#   and a bare `HOP_*` is a user setting, which is why the pattern refuses a preceding word character.
# - HOP_HOME is excluded because hop.zsh derives it unconditionally, so no inherited value survives.
# - HOP_VIM_* are excluded because lib/ui.zsh assigns them; they are computed keymaps, not settings.
# - XDG_* is scanned too, because every hop default path resolves through one of those three roots.
# - Dropping the XDG_STATE_HOME or XDG_CACHE_HOME pin failed nothing until they were scanned here.
t 'every hop setting the product reads is covered by the fixture pin list'
typeset -a pinnames prodvars unpinned rawvars
fixture_sources shipped
rawvars=(${(f)"$(grep -rhoE '(^|[^A-Za-z0-9_])(HOP|XDG)_[A-Z_]+' "${reply[@]}")"})
prodvars=(${(u)rawvars/#[^A-Z_]/})
prodvars=(${prodvars:#HOP_HOME})
prodvars=(${prodvars:#HOP_VIM_*})
# An EXACT set, not a `>=` floor: a floor lets the scan rot down to it and still report healthy.
# - At `>= 10` against 14 found, a scan degrading to 10 would have passed with an empty diff.
# - A >= floor produced a vacuous or false-passing test four times this release, this one included.
# - A setting appearing or disappearing in the source now forces a deliberate edit of both lists.
typeset -a expected=(
	HOP_CLIPBOARD HOP_CONFIG HOP_DEBUG HOP_DEBUG_LOG HOP_DEFAULT_KINDS
	HOP_FZF_HEIGHT HOP_FZF_MIN HOP_GUARD_WINDOW HOP_HISTFILE HOP_HIST_MAX
	HOP_HOPRC HOP_REPOS HOP_VIM HOP_WORKSPACES HOP_WORKSPACES_FILE
	XDG_CACHE_HOME XDG_CONFIG_HOME XDG_STATE_HOME
)
# Sorted through an array, because `(o)` does not sort inside a quoted scalar expansion.
typeset -a expsorted=(${(o)expected}) gotsorted=(${(o)prodvars})
assert_eq "${(j:, :)expsorted}" "${(j:, :)gotsorted}" \
	'the settings the source reads changed; update this list and the pin list together'
pinnames=(${${(f)"$(fixture_pin_pairs /nonexistent)"}%%=*})
unpinned=(${prodvars:|pinnames})
assert_empty "${(j:, :)unpinned}" 'a probe could inherit these from the developer running the suite'

# fzf reads its own settings, which hop never names, so the scan above is blind to them by construction.
# - They are therefore written out by hand, and this test exists to notice if one is dropped.
# - Measured: FZF_DEFAULT_OPTS='--exact' disabled the CONTROL arm of the --exact guard in
#   suite_integration, so its fuzzy comparison returned one row and the test proved nothing.
t 'the fzf settings hop never names, and so cannot be scanned for, are pinned anyway'
typeset fzfvar
for fzfvar in FZF_DEFAULT_OPTS FZF_DEFAULT_COMMAND; do
	assert_nonempty "${pinnames[(r)$fzfvar]}" "${fzfvar} is unpinned, and fzf reads it even if hop does not"
done

# Deleting the HOME or XDG pin from fixture_pins failed NOTHING, so the pin was load-bearing yet unguarded.
# - The leak it stops is the original defect: a probe READ the real ~/.config/hop and SOURCED its config.
# - The suite process keeps the REAL $HOME deliberately, which is what makes it a usable needle here.
t 'a probe child gets the throwaway $HOME and XDG roots, never the real ones'
typeset -a probeenv
probeenv=(${(f)"$(hop_probe 'print -rl -- $HOME $XDG_CONFIG_HOME $HOP_WORKSPACES_FILE')"})
assert_eq "$HOP_FIX_HOME" "${probeenv[1]}" 'the probe ran with a $HOME the fixture does not own'
assert_ne "$HOME" "${probeenv[1]}" 'the probe inherited the REAL $HOME, so every default path is the real one'
assert_eq "${HOP_FIX_HOME}/.config" "${probeenv[2]}" 'XDG_CONFIG_HOME must move with $HOME or it still resolves home'
assert_contains "${probeenv[3]}" "$HOP_FIX_HOME" 'the workspaces file a probe would READ is outside the fixture'

t 'fixture_repo builds a throwaway git repo'
typeset REPLY repo top
fixture_repo smoke
repo=$REPLY
fixture_write 'terraform/sandbox/vpc/terragrunt.hcl' 'include {}'
fixture_write 'README.md' '# fixture'
fixture_commit 'initial'
top=$(_hop_fix_git -C "$repo" rev-parse --show-toplevel)
assert_eq "$repo" "$top" 'the fixture path must survive the symlink under /var'
assert_file "$repo/terraform/sandbox/vpc/terragrunt.hcl"

t 'the fixture repo is under the temp root, never anywhere in $HOME'
assert_contains "$repo" "$HOP_FIX_TMPROOT"
assert_not_contains "$repo" "$HOME/"

t '_hop_generate runs against a fixture with no interactive fzf'
typeset rows
rows=$(hop_probe "_hop_generate ${(q)repo} dir")
assert_nonempty "$rows"
assert_contains "$rows" '<root>'
assert_contains "$rows" 'terraform'

t 'stub_bin shadows code, gh and bat on PATH'
stub_bin code gh bat
assert_eq "$HOP_FIX_STUBDIR/code" "${commands[code]}"
assert_eq "$HOP_FIX_STUBDIR/gh" "${commands[gh]}"
assert_eq "$HOP_FIX_STUBDIR/bat" "${commands[bat]}"

t 'a stubbed command records its argv and opens nothing'
stub_reset
code -r "$repo/README.md"
assert_eq "code	-r	${repo}/README.md" "$(stub_calls code)"

t 'stub_bin redirects $EDITOR away from a real editor'
assert_eq "$HOP_FIX_STUBDIR/editor" "$EDITOR"
assert_eq "$HOP_FIX_STUBDIR/editor" "$VISUAL"

if (( ${+commands[fzf]} )); then
	t 'fzf --filter matches a row without opening a terminal'
	typeset hit
	hit=$(print -rl -- $'vpc  tg\t/a/vpc\t/a/vpc/main.tf' $'sqs  tg\t/a/sqs\t/a/sqs/main.tf' | fzf_filter vpc)
	assert_contains "$hit" '/a/vpc'
	assert_not_contains "$hit" '/a/sqs'
else
	skip 'fzf --filter matches a row without opening a terminal' 'fzf is not installed'
fi

# ---------------------------------------------------------------------------
# Repo governance: the files a contributor or an issue reporter actually hits.
# ---------------------------------------------------------------------------
typeset -a governance=(
	"$HOP_HOME/CONTRIBUTING.md"
	"$HOP_HOME/.editorconfig"
	"$HOP_HOME/.github/pull_request_template.md"
	"$HOP_HOME/.github/ISSUE_TEMPLATE/bug_report.yml"
	"$HOP_HOME/.github/ISSUE_TEMPLATE/feature_request.yml"
	"$HOP_HOME/.github/ISSUE_TEMPLATE/config.yml"
)

typeset gf grel
for gf in "${governance[@]}"; do
	grel=${gf#${HOP_HOME}/}
	t "${grel} exists"
	assert_file "$gf"
done

# A missing python3, or a python3 with no PyYAML, is a skip here, not a failure.
if (( ${+commands[python3]} )) && python3 -c 'import yaml' 2>/dev/null; then
	typeset -a yamlfiles=("$HOP_HOME"/.github/**/*.yml(N))
	t 'the .github yml glob finds exactly the files that are there'
	# The exact list, not a floor: `>= 1` passed on a glob that had rotted to one subdirectory.
	# - The parse loop below only covers what the glob returned, so a partial match checks nothing, reports nothing, and drops exactly the files nobody would think to look for.
	# - Adding a workflow is meant to fail this line once. That is the tripwire, not friction.
	# - The array assignment is what makes `(o)` sort here: inside a quoted scalar it silently does not.
	typeset -a yamlsorted=(${(o)${yamlfiles[@]#${HOP_HOME}/}})
	typeset -a yamlwant=(
		.github/ISSUE_TEMPLATE/bug_report.yml
		.github/ISSUE_TEMPLATE/config.yml
		.github/ISSUE_TEMPLATE/feature_request.yml
		.github/workflows/ci.yml
	)
	assert_eq "${(j:,:)yamlwant}" "${(j:,:)yamlsorted}" 'the yml glob no longer matches the files in .github'

	typeset yf yrel
	for yf in "${yamlfiles[@]}"; do
		yrel=${yf#${HOP_HOME}/}
		t "${yrel} parses as YAML"
		assert_status 0 python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$yf"
	done
else
	skip 'every .github yml file parses as YAML' 'python3 or its yaml module is not installed'
fi

# ---------------------------------------------------------------------------
# A version probe must not be able to read the caller's stdin.
# ---------------------------------------------------------------------------
# The `fzf` on PATH is not always the real binary, and a wrapper that reads stdin never returns.
# - fzf-tmux ships beside fzf and runs `cat <&0 > $fifo1` whenever stdin is not a tty.
# - So `hop --doctor` from a script could hang forever, and that is the command a bug report asks for.
# - _hop_doctor_tool probes SIX tools this way, so the drainer is installed as bat as well as fzf.
# - A fix that special-cased fzf alone would leave bat hanging, and the --doctor cases below would catch it.
# - The fifo is opened READ-WRITE, so EOF can never arrive and a reader blocks with no writer to wait on.
typeset SM_DRAIN SM_NOFEED smt
fixture_tmpdir drainer || return 1
SM_DRAIN=$REPLY
for smt in fzf bat; do
	print -rl -- '#!/bin/sh' 'cat > /dev/null' 'echo "0.60.3 (drainer)"' > "$SM_DRAIN/$smt"
	chmod +x "$SM_DRAIN/$smt" || return 1
done
# gh and code are inert rather than absent, so no real browser or editor is launched by a doctor probe.
for smt in gh code; do
	print -rl -- '#!/bin/sh' 'echo inert 1.0' > "$SM_DRAIN/$smt"
	chmod +x "$SM_DRAIN/$smt" || return 1
done
fixture_tmpdir nofeed || return 1
SM_NOFEED="$REPLY/pipe"
mkfifo -- "$SM_NOFEED"

# sm_drain <code> -> the child's status, with a draining fzf on PATH and stdin that never ends.
# - The only assertion any caller makes is on 142, never on elapsed time.
# - Measured: a healthy `hop --doctor` took 25.3s on a loaded box, so a tight bound reads as a false hang.
# - It cds to the temp root first, because _hop_doctor_body counts rows per kind and so scales with PWD.
sm_drain() {
	emulate -L zsh
	hop_bound 45 zsh -f -c "$(fixture_pins)
export PATH=${(q)SM_DRAIN}:\$PATH
builtin cd -q ${(q)HOP_FIX_TMPROOT}
source ${(q)HOP_HOME}/hop.zsh || exit 97
${1}" >/dev/null 2>&1 <> "$SM_NOFEED"
	return $?
}

t 'the draining wrapper really is the only fzf a probe can see'
typeset drainseen
drainseen=$(hop_bound 20 zsh -f -c "$(fixture_pins)
export PATH=${(q)SM_DRAIN}:\$PATH
source ${(q)HOP_HOME}/hop.zsh || exit 97
print -r -- \${commands[fzf]}" 2>/dev/null </dev/null)
assert_eq "$SM_DRAIN/fzf" "$drainseen" 'the real fzf answers --version without reading, so it hides this defect'

typeset -i drainst
t '_hop_fzf_ver returns even when fzf is a wrapper that drains stdin'
sm_drain '_hop_fzf_ver'
drainst=$?
assert_ne 142 "$drainst" 'the version probe inherited stdin, so any reading wrapper hangs hop for good'

t 'hop --doctor returns too, which is the command a bug report is told to run'
sm_drain 'hop --doctor'
drainst=$?
assert_ne 142 "$drainst" 'a hung --doctor gives a reporter no diagnostic at all, which is the worst case'

t 'and hop --doctor=short returns, since both bodies share _hop_doctor_tool'
sm_drain 'hop --doctor=short'
drainst=$?
assert_ne 142 "$drainst" 'the short body probes the same six tools through the same helper'

# ---------------------------------------------------------------------------
# An inventory of every fzf invocation in the shipped source.
# ---------------------------------------------------------------------------
# This detects an UNREVIEWED call site, and does NOT claim any call site is safe.
# - A text match cannot claim that: `cmd 2>&1 | head -1 </dev/null` binds the redirect to head.
# - That spelling looks fixed, leaves cmd inheriting stdin, and passes any grep for the redirect.
# - It was written that way here first, and it hung 3 of 3 while looking correct.
# - The executed cases above are the proof; this only asserts nobody added a site without review.
# - lib/doctor.zsh runs git with stdin inherited too, excluded deliberately: git reads no stdin here.
fixture_sources shipped
typeset -a smshipped=("${reply[@]}")

t 'the shipped file list found files, or the inventory below matches nothing and passes'
assert_empty "$REPLY" 'a mistyped glob would make this inventory vacuous instead of failing'
assert_ge $#smshipped 5 'too few shipped files for this to be the real tree'

typeset -a fzfcalls=()
typeset sf smrel smhits smline
for sf in "${smshipped[@]}"; do
	smrel=${sf#${HOP_HOME}/}
	smhits=$(grep -E '(^[[:space:]]*|[|(][[:space:]]*)fzf[[:space:]]|_hop_doctor_tool[[:space:]]+fzf([[:space:]]|$)' -- "$sf" | sed 's/^[[:space:]]*//')
	[[ -n $smhits ]] || continue
	for smline in ${(f)smhits}; do
		fzfcalls+=("${smrel}: ${smline}")
	done
done

# Sorted through arrays, because `(o)` is silently dropped inside a quoted scalar expansion.
typeset -a fzfexpected=(
	'hop.zsh: out=$(print -r -- "$targets" | fzf --filter="$query" \'
	'lib/doctor.zsh: _hop_doctor_tool fzf --version'
	'lib/doctor.zsh: _hop_doctor_tool fzf --version'
	'lib/ui.zsh: fzf "${args[@]}"'
	'lib/ui.zsh: out=$(fzf --version </dev/null 2>/dev/null)'
)
typeset -a fzfexpsorted=(${(o)fzfexpected}) fzfgotsorted=(${(o)fzfcalls})

t 'the fzf invocations in the shipped source are exactly the reviewed set'
assert_eq "${(F)fzfexpsorted}" "${(F)fzfgotsorted}" \
	'an fzf call site was added or changed; check whether it inherits stdin, then update this list'

# ---------------------------------------------------------------------------
# Every caller of _hop_pick pipes into it, which is what makes ITS inherited stdin correct.
# ---------------------------------------------------------------------------
# _hop_pick's own fzf MUST inherit stdin, because that is how the target rows arrive.
# - So the safety property lives at the CALL SITE, as a pipe, and not on the fzf line itself.
# - A new caller that forgot the pipe would leave the picker reading a terminal, or a script's stdin.
# - That makes the whitelist a checked precondition rather than an exception to the rule above.
typeset -a pickcalls=()
for sf in "${smshipped[@]}"; do
	smrel=${sf#${HOP_HOME}/}
	smhits=$(grep -E '_hop_pick[[:space:]]+"' -- "$sf" | sed 's/^[[:space:]]*//')
	[[ -n $smhits ]] || continue
	for smline in ${(f)smhits}; do
		pickcalls+=("${smrel}: ${smline}")
	done
done

t 'every _hop_pick call site is fed by a pipe, so what it inherits is rows and never a terminal'
assert_ge $#pickcalls 2 'the call-site scan found nothing, which would make the loop below vacuous'
typeset pickcall
for pickcall in "${pickcalls[@]}"; do
	assert_contains "$pickcall" '| _hop_pick' 'this caller does not pipe, so the picker reads whatever stdin is'
done

# ---------------------------------------------------------------------------
# A completed suite must leave nothing behind in a temp root of its own.
# ---------------------------------------------------------------------------
# Pinning TMPDIR is the whole isolation, and it is what removes the need for a baseline to subtract.
# - fixture.zsh derives HOP_FIX_TMPROOT from TMPDIR, so every fixture the child makes lands inside it.
# - lib/ui.zsh reads ${TMPDIR:-/tmp} for its guard dir too, so the shipped code is pinned by the same move.
# - Anything left in there afterwards is a leak from that run, and never another agent's live fixture.
# - suite_core is the subject because that is where the four `$(co_dbg` leaks lived, so this is not vacuous.
# - HOP_T_REAP_HOURS=0 in the child, or the new reaper could hide the very leak this exists to see.
# - A KILLED run leaks BY DESIGN, since KILL cannot run the EXIT trap, so that case SKIPS and never fails.
# - Without that skip this would fail on machine load instead of on a leak, making it a load detector.
typeset SM_LEAKDIR SM_LEAKTMP SM_LEAKHOME
typeset -i leakst
typeset -a leaked leakedowned
fixture_tmpdir leakroot || return 1
SM_LEAKDIR=$REPLY
SM_LEAKTMP="$SM_LEAKDIR/tmp"
SM_LEAKHOME="$SM_LEAKDIR/home"
mkdir -p -- "$SM_LEAKTMP" "$SM_LEAKHOME" || return 1

hop_bound 300 env -i PATH="$PATH" TERM=dumb SHELL=/bin/zsh \
	HOME="$SM_LEAKHOME" TMPDIR="$SM_LEAKTMP" HOP_T_TIMEOUT=900 HOP_T_REAP_HOURS=0 \
	zsh "${HOP_HOME}/tests/run" core >/dev/null 2>&1 </dev/null
leakst=$?
leaked=("$SM_LEAKTMP"/*(N))
# hop-guard was excluded here while lib/ui.zsh could still leak one, and that exclusion is now gone.
# - _hop_pick reaps stale guard dirs before creating its own, so a healthy run leaves none behind.
# - Nothing is filtered any more, which is the whole point: an exclusion is a hole in the only leak check.
leakedowned=(${leaked[@]:t})

if (( leakst != 0 )); then
	skip 'a completed suite_core run leaves no fixture behind in its own temp root' \
		"the nested run exited ${leakst}, and a killed run leaks by design"
else
	t 'a completed suite_core run leaves no fixture behind in its own temp root'
	assert_eq '' "${(j:, :)leakedowned}" 'these fixture entries outlived the run that created them'
fi
