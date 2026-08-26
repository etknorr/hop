#!/usr/bin/env zsh
# suite_completions: completions/_hop, specifically _hop_versions and its release-tag listing.
# - Tested directly, not through a real Tab press: driving compinit is heavier than this needs.
# - `_describe` is stubbed to capture the array it was handed, the one thing the bug corrupts.
# - Sourcing the file also runs its trailing `_hop "$@"`, which needs the real `_arguments`
#   completion builtin; that one harmless "command not found" is swallowed along with it.
_describe() {
	emulate -L zsh
	print -rl -- "${(@P)argv[-1]}"
}
{ source "$HOP_HOME/completions/_hop" } 2>/dev/null

# ct_repo -> REPLY is a fixture repo carrying three release tags, oldest first.
ct_repo() {
	emulate -L zsh
	fixture_repo comptags || return 1
	local d=$REPLY
	fixture_write hop.zsh '# fixture' || return 1
	fixture_commit 'v1.0.0' || return 1
	_hop_fix_git -C "$d" tag v1.0.0 || return 1
	fixture_commit 'v1.1.0' || return 1
	_hop_fix_git -C "$d" tag v1.1.0 || return 1
	fixture_commit 'v2.0.0' || return 1
	_hop_fix_git -C "$d" tag v2.0.0 || return 1
	REPLY=$d
	return 0
}

typeset -g CT_REPO
ct_repo
CT_REPO=$REPLY

# ---------------------------------------------------------------------------
# The bug: `git tag --list` honours column.ui and joins every tag onto one line.
# ---------------------------------------------------------------------------
t '_hop_versions offers every tag, newest first, by default'
typeset out
out=$(HOP_HOME=$CT_REPO _hop_versions)
assert_eq $'v2.0.0\nv1.1.0\nv1.0.0' "$out"

t '_hop_versions still offers every tag as SEPARATE candidates under column.ui=always'
_hop_fix_git -C "$CT_REPO" config column.ui always
out=$(HOP_HOME=$CT_REPO _hop_versions)
_hop_fix_git -C "$CT_REPO" config --unset column.ui
assert_eq $'v2.0.0\nv1.1.0\nv1.0.0' "$out"

# ---------------------------------------------------------------------------
# No tags at all: nothing to offer, and _hop_versions must say so via its exit status.
# ---------------------------------------------------------------------------
t '_hop_versions has nothing to offer when the repo has no release tags'
fixture_repo comptags-empty
typeset empty=$REPLY
fixture_write hop.zsh '# fixture'
fixture_commit 'no releases yet'
out=$(HOP_HOME=$empty _hop_versions)
typeset -i st=$?
assert_empty "$out"
assert_eq '1' "$st"
