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

t 'hop --help exits 0 and lists the registry, not a hardcoded kind list'
typeset help
help=$(hop_probe 'hop --help')
assert_contains "$help" 'usage: hop'
typeset hk
for hk in tg mod helm serverless puppet backstage dir file; do
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

t 'hop --doctor=short never prints $HOME, even forced to try'
typeset docshortplain
docshortplain=$(HOP_DEBUG_LOG="${HOP_FIX_HOME}/hop-doctor-sentinel.log" hop_probe 'hop --doctor=short')
assert_not_contains "$docshortplain" "$HOP_FIX_HOME"
assert_not_contains "$docshortplain" '/Users/'
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
typeset -a helplines=(${(f)help})
typeset fileline=${${(M)helplines:#*[[:space:]]file[[:space:]]*}[1]}
assert_nonempty "$fileline" 'no registry line for the file kind'
assert_not_contains "$fileline" '*' 'file is opt-in, so it must not carry the default marker'

# ---------------------------------------------------------------------------
# The harness itself: fixtures, stubs and the probe.
# ---------------------------------------------------------------------------
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
