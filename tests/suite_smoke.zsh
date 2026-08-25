#!/usr/bin/env zsh
# suite_smoke: the harness proving itself, plus the three checks nothing else should ever break.
# - Every shipped file parses under `zsh -n`, which is the cheapest guard against a bad edit.
# - The two bin/ helpers are executable, since fzf runs them as commands and not as source.
# - Sourcing hop.zsh in a bare shell defines the three public entry points.

# ---------------------------------------------------------------------------
# Every file parses.
# ---------------------------------------------------------------------------
# bin/ and completions/ are globbed by content rather than listed, so a new file is covered free.
typeset -a parseable=(
	"$HOP_HOME/hop.zsh"
	"$HOP_HOME"/lib/*.zsh(N)
	"$HOP_HOME"/presets/*.zsh(N)
	"$HOP_HOME"/config.example.zsh(N)
	"$HOP_HOME"/bin/*(N.)
	"$HOP_HOME"/completions/_*(N.)
	"$HOP_TESTS/run"
	"$HOP_TESTS"/lib/*.zsh(N)
	"$HOP_TESTS"/suite_*.zsh(N)
)

typeset f rel
for f in "${parseable[@]}"; do
	rel=${f#${HOP_HOME}/}
	t "zsh -n  ${rel}"
	assert_status 0 zsh -n "$f"
done

t 'the file list is not silently empty'
assert_ge $#parseable 8 'a glob typo would make every parse check vanish'

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
t 'an inherited HOP_HOME naming the wrong install is overridden, not honoured'
typeset stale
stale=$(HOP_HOME=/nonexistent/hop zsh -f -c "source ${(q)HOP_HOME}/hop.zsh 2>&1; print -r -- \$HOP_HOME")
assert_eq "$HOP_HOME" "$stale" 'a stale HOP_HOME was honoured, so every lib source would fail'

t 'sourcing with a stale HOP_HOME emits nothing on stderr'
typeset stalenoise
stalenoise=$(HOP_HOME=/nonexistent/hop zsh -f -c "source ${(q)HOP_HOME}/hop.zsh" 2>&1 >/dev/null)
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

# --doctor is the only way a bug report can carry the shell state, since fzf cannot be captured.
t 'hop --doctor exits 0 and reports install, config, tools and the confusable keys'
typeset doc
doc=$(hop_probe 'hop --doctor')
assert_contains "$doc" 'HOP_HOME'
assert_contains "$doc" 'HOP_CONFIG'
assert_contains "$doc" 'tools'
assert_contains "$doc" 'keys people mix up'

t 'hop --doctor works outside a git repo, where it is most often needed'
typeset docout
docout=$(hop_probe "builtin cd -q ${(q)HOP_FIX_TMPROOT} && hop --doctor" 2>&1)
assert_contains "$docout" 'NONE, so hop opens the workspace or repo picker'
assert_contains "$help" "$HOP_FIX_NOCONFIG" 'the help must name the config file you would create'

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
