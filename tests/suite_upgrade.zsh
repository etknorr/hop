#!/usr/bin/env zsh
# suite_upgrade: hop upgrade, and above all every path where it must REFUSE to touch a checkout.
# - A self-updater that discards local work is worse than no self-updater, so refusals come first.
# - Nothing here goes near the network: the "remote" is a bare repo under $TMPDIR, cloned by path.
# - Nothing here goes near the real install either, because HOP_HOME is pointed at a throwaway.
# - hop.zsh derives HOP_HOME from its own path on purpose, so a probe sources lib/upgrade.zsh alone.

# ---------------------------------------------------------------------------
# Fixtures: a bare "origin", clones of it, and a probe that can be aimed at one.
# ---------------------------------------------------------------------------

# _up_origin [label] -> REPLY is a bare repo whose main holds v0.1.0 then v0.2.0.
# - REPLY is deliberately NOT localised, because that is how the fixture helpers hand paths back.
_up_origin() {
	emulate -L zsh
	fixture_repo "${1:-up-src}" || return 1
	local src=$REPLY
	fixture_write hop.zsh '# a stand-in for the real entry point' || return 1
	fixture_write VERSION '0.1.0' || return 1
	fixture_commit 'first release' || return 1
	_hop_fix_git -C "$src" tag v0.1.0 || return 1
	fixture_write VERSION '0.2.0' || return 1
	fixture_commit 'second release' || return 1
	_hop_fix_git -C "$src" tag v0.2.0 || return 1
	fixture_tmpdir "${1:-up-src}-bare" || return 1
	local bare="$REPLY/origin.git"
	_hop_fix_git init --bare -q -b main "$bare" || return 1
	_hop_fix_git -C "$src" push -q "$bare" 'refs/heads/main:refs/heads/main' --tags || return 1
	REPLY=$bare
	return 0
}

# _up_origin_untagged -> REPLY is a bare repo with one commit and NO release tags at all.
_up_origin_untagged() {
	emulate -L zsh
	fixture_repo up-src-untagged || return 1
	local src=$REPLY
	fixture_write hop.zsh '# no releases cut yet' || return 1
	fixture_commit 'work in progress' || return 1
	fixture_tmpdir up-src-untagged-bare || return 1
	local bare="$REPLY/origin.git"
	_hop_fix_git init --bare -q -b main "$bare" || return 1
	_hop_fix_git -C "$src" push -q "$bare" 'refs/heads/main:refs/heads/main' || return 1
	REPLY=$bare
	return 0
}

# _up_clone <bare> [label] -> REPLY is a fresh clone of it, on main and clean.
# - A committer identity is set because two tests below make a local commit in the clone.
_up_clone() {
	emulate -L zsh
	local bare=$1
	fixture_tmpdir "${2:-up-clone}" || return 1
	local dir="$REPLY/hop"
	_hop_fix_git clone -q "$bare" "$dir" || return 1
	_hop_fix_git -C "$dir" config user.email 'hop-tests@example.invalid' || return 1
	_hop_fix_git -C "$dir" config user.name 'hop tests' || return 1
	REPLY=$dir
	return 0
}

# _up_probe <home> <code> -> run code with lib/upgrade.zsh sourced and HOP_HOME set to a fixture.
# - Sourcing the one lib rather than hop.zsh is what lets HOP_HOME name a throwaway checkout.
# - The user's git config is cut out for exactly the reasons _hop_fix_git cuts it out.
# - -f skips rc files, so the child cannot pick up an alias or a function from this laptop.
_up_probe() {
	emulate -L zsh
	local home=$1 code=$2
	GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TEMPLATE_DIR='' \
		zsh -f -c "source ${(q)HOP_HOME}/lib/upgrade.zsh || exit 97
typeset -g HOP_HOME=${(q)home}
${code}"
}

# _up_slurp <path> -> the file's text, read WITHOUT `$(<file)`.
# - `zsh -n` opens the file in a `$(<...)` even though it runs nothing, so a variable path warns.
_up_slurp() {
	emulate -L zsh
	[[ -r $1 ]] || return 1
	command cat -- "$1"
}

# _up_sha <dir> -> the full HEAD sha, which is the value a refusal must leave alone.
_up_sha() {
	emulate -L zsh
	_hop_fix_git -C "$1" rev-parse HEAD 2>/dev/null
}

# _up_branch <dir> -> the branch HEAD is on, or the literal DETACHED.
# - A bare upgrade has to leave you somewhere you can upgrade again, so this is the proof.
_up_branch() {
	emulate -L zsh
	local b
	b=$(_hop_fix_git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null) || b=''
	print -r -- "${b:-DETACHED}"
}

typeset ORIGIN=''
typeset UNTAGGED=''
typeset V1='' V2=''
if _up_origin; then
	ORIGIN=$REPLY
	V1=$(_hop_fix_git -C "$ORIGIN" rev-parse 'refs/tags/v0.1.0^{commit}')
	V2=$(_hop_fix_git -C "$ORIGIN" rev-parse 'refs/tags/v0.2.0^{commit}')
fi
_up_origin_untagged && UNTAGGED=$REPLY

typeset out dir before after
typeset -i st

t 'the fixture remote really has two release tags'
assert_nonempty "$ORIGIN" 'no bare origin was built, so every test below is meaningless'
assert_nonempty "$V1" 'v0.1.0 did not resolve in the fixture remote'
assert_nonempty "$V2" 'v0.2.0 did not resolve in the fixture remote'
assert_ne "$V1" "$V2" 'the two tags point at the same commit, so no test can prove a move'

# ---------------------------------------------------------------------------
# Refusals. Each one is a way a naive self-updater destroys work.
# ---------------------------------------------------------------------------
t 'a HOP_HOME that is not a git checkout is refused'
fixture_tmpdir up-plain
dir=$REPLY
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 1 "$st" 'a non-checkout must fail, not fall through to a fetch'
assert_contains "$out" 'not a git checkout'

t 'a copy vendored inside another repo is refused, so that repo is never moved'
fixture_repo up-outer
typeset outer=$REPLY
fixture_write 'vendor/hop/hop.zsh' '# vendored'
fixture_commit 'vendored copy'
out=$(_up_probe "$outer/vendor/hop" '_hop_upgrade' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'sits inside'

t 'a checkout with no origin remote is refused'
_up_clone "$ORIGIN" up-noremote
dir=$REPLY
_hop_fix_git -C "$dir" remote remove origin
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'no `origin` remote'
assert_eq "$before" "$(_up_sha "$dir")" 'a refusal moved HEAD'

t 'a dirty install is refused and the local edit survives'
_up_clone "$ORIGIN" up-dirty
dir=$REPLY
print -r -- '# a local edit nobody wants silently discarded' >> "$dir/hop.zsh"
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade 0.1.0' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'uncommitted changes'
assert_eq "$before" "$(_up_sha "$dir")" 'a dirty tree was moved anyway'
assert_contains "$(_up_slurp "$dir/hop.zsh")" 'nobody wants silently discarded'

t 'a side branch is refused, because that is work in progress'
_up_clone "$ORIGIN" up-branch
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q -b wip
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'not main'
assert_eq "$before" "$(_up_sha "$dir")" 'a side branch was moved anyway'

t 'HEAD detached at a commit that is not a release tag is refused'
_up_clone "$ORIGIN" up-detached
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q --detach
_hop_fix_git -C "$dir" commit -q --allow-empty --no-gpg-sign -m 'a local experiment'
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'not a release tag'
assert_eq "$before" "$(_up_sha "$dir")" 'an unreachable local commit was abandoned'

t 'an unknown release is refused, and the ones that exist are named'
_up_clone "$ORIGIN" up-nosuch
dir=$REPLY
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade 9.9.9' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'no such release: v9.9.9'
assert_contains "$out" 'v0.2.0'
assert_eq "$before" "$(_up_sha "$dir")"

t 'a malformed version is rejected before anything is fetched'
out=$(_up_probe "$dir" '_hop_upgrade not-a-version' 2>&1)
st=$?
assert_eq 2 "$st" 'a usage error is status 2, like every other hop usage error'
assert_contains "$out" 'not a version'

t 'an unknown option is rejected with status 2'
out=$(_up_probe "$dir" '_hop_upgrade --force' 2>&1)
st=$?
assert_eq 2 "$st"
assert_contains "$out" 'unknown option'

t 'two versions at once is rejected'
out=$(_up_probe "$dir" '_hop_upgrade 0.1.0 0.2.0' 2>&1)
st=$?
assert_eq 2 "$st"
assert_contains "$out" 'at most one version'

t 'a remote with no release tags is refused rather than guessed at'
_up_clone "$UNTAGGED" up-untagged
dir=$REPLY
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'no release tags'
assert_eq "$before" "$(_up_sha "$dir")"

# ---------------------------------------------------------------------------
# --check: it reports, and it changes nothing.
# ---------------------------------------------------------------------------
t '--check on an older pin reports both versions and exits 0'
_up_clone "$ORIGIN" up-check-old
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q v0.1.0
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade --check' 2>&1)
st=$?
assert_eq 0 "$st" '--check must exit 0 whether or not an update exists'
assert_contains "$out" 'installed'
assert_contains "$out" '0.1.0'
assert_contains "$out" 'v0.2.0'
assert_contains "$out" 'an update is available'
assert_eq "$before" "$(_up_sha "$dir")" '--check moved HEAD'

t '--check reads the installed version from the VERSION file'
assert_contains "$out" '0.1.0' 'the VERSION file at v0.1.0 says 0.1.0, so --check must too'

t '--check on the newest release says up to date, and still exits 0'
_up_clone "$ORIGIN" up-check-new
dir=$REPLY
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade --check' 2>&1)
st=$?
assert_eq 0 "$st"
assert_contains "$out" 'up to date'
assert_not_contains "$out" 'an update is available'
assert_eq "$before" "$(_up_sha "$dir")"

t '--check leaves a dirty tree alone and still reports'
_up_clone "$ORIGIN" up-check-dirty
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q v0.1.0
print -r -- '# local' >> "$dir/hop.zsh"
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade --check' 2>&1)
st=$?
assert_eq 0 "$st" 'a read-only report has no reason to fail on a dirty tree'
assert_contains "$out" 'v0.2.0'
assert_contains "$out" 'uncommitted changes'
assert_eq "$before" "$(_up_sha "$dir")"

t '--check against a remote with no releases exits 0 and says so'
_up_clone "$UNTAGGED" up-check-untagged
dir=$REPLY
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade --check' 2>&1)
st=$?
assert_eq 0 "$st"
assert_contains "$out" 'none yet'
assert_eq "$before" "$(_up_sha "$dir")"

t '--check on a checkout that is not a git repo fails, since there is nothing to report'
fixture_tmpdir up-check-plain
out=$(_up_probe "$REPLY" '_hop_upgrade --check' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'not a git checkout'

# ---------------------------------------------------------------------------
# The updates that are supposed to happen.
# ---------------------------------------------------------------------------
t 'a bare upgrade fast-forwards main and LEAVES YOU ON IT'
# Detaching here would silently break the next `git pull`, and a yearly upgrader never works it out.
_up_clone "$ORIGIN" up-latest
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q -B main v0.1.0
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 0 "$st"
assert_eq "$V2" "$(_up_sha "$dir")" 'upgrade did not land on v0.2.0'
assert_eq main "$(_up_branch "$dir")" 'a bare upgrade detached HEAD, which it must never do'
assert_contains "$out" 'v0.2.0'
assert_contains "$out" 'on main'
assert_contains "$out" 'exec zsh'

t 'a bare upgrade never merges: main advances by fast-forward only'
# A merge commit would mean main no longer matches any released tree, byte for byte.
assert_eq 0 "$(_hop_fix_git -C "$dir" rev-list --count --merges main)" \
	'a merge commit appeared on main, so this was not a fast-forward'
assert_eq "$V2" "$(_hop_fix_git -C "$dir" rev-parse refs/heads/main)" \
	'the main REF did not move, so only the worktree was updated'

t 'a bare upgrade from a pin says it is leaving the pin, and returns to main'
_up_clone "$ORIGIN" up-frompin
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q v0.1.0
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 0 "$st"
assert_eq main "$(_up_branch "$dir")" 'leaving a pin has to land on main, not on another commit'
assert_contains "$out" 'pinned at v0.1.0'
assert_contains "$out" 'To stay pinned'
assert_contains "$out" 'hop upgrade 0.1.0'
assert_eq "$V2" "$(_up_sha "$dir")"

t 'upgrade to a bare semver pins to that exact release'
_up_clone "$ORIGIN" up-bare-semver
dir=$REPLY
out=$(_up_probe "$dir" '_hop_upgrade 0.1.0' 2>&1)
st=$?
assert_eq 0 "$st"
assert_eq "$V1" "$(_up_sha "$dir")" 'a bare 0.1.0 did not resolve to the v0.1.0 tag'

t 'upgrade to a v-prefixed version pins to the same release'
_up_clone "$ORIGIN" up-v-semver
dir=$REPLY
out=$(_up_probe "$dir" '_hop_upgrade v0.1.0' 2>&1)
st=$?
assert_eq 0 "$st"
assert_eq "$V1" "$(_up_sha "$dir")"

t 'naming a version pins the install, detached, and says how to get back'
assert_eq DETACHED "$(_up_branch "$dir")" 'a named version means a pin, and a pin means detached'
assert_contains "$out" 'pinned at v0.1.0'
assert_contains "$out" 'To follow releases again: hop upgrade'
assert_contains "$out" 'checkout main'

t 'a main already ahead of the newest release is up to date, not an error'
# This is the normal state of an install that follows main between two releases.
_up_clone "$ORIGIN" up-ahead
dir=$REPLY
_hop_fix_git -C "$dir" commit -q --allow-empty --no-gpg-sign -m 'a commit after the release'
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 0 "$st" 'following main between releases must not be an error'
assert_contains "$out" 'already carries v0.2.0'
assert_eq "$before" "$(_up_sha "$dir")"
assert_eq main "$(_up_branch "$dir")"

t '--check on a main ahead of the newest release also says up to date'
out=$(_up_probe "$dir" '_hop_upgrade --check' 2>&1)
st=$?
assert_eq 0 "$st"
assert_contains "$out" 'up to date'
assert_not_contains "$out" 'an update is available'

t 'a main that has diverged from the release is refused, never rebased or merged'
_up_clone "$ORIGIN" up-diverged
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q -B main v0.1.0
_hop_fix_git -C "$dir" commit -q --allow-empty --no-gpg-sign -m 'a local commit on main'
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'diverged'
assert_eq "$before" "$(_up_sha "$dir")"
assert_eq main "$(_up_branch "$dir")" 'a refusal must not move HEAD off the branch either'

t 'a pin with no local main branch is refused, and is told how to make one'
_up_clone "$ORIGIN" up-nomain
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q v0.1.0
_hop_fix_git -C "$dir" branch -q -D main
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'no local main branch'
assert_contains "$out" 'checkout -b main origin/main'
assert_eq "$before" "$(_up_sha "$dir")"

t 'upgrading to the release already checked out changes nothing'
before=$(_up_sha "$dir")
out=$(_up_probe "$dir" '_hop_upgrade v0.1.0' 2>&1)
st=$?
assert_eq 0 "$st"
assert_contains "$out" 'already at v0.1.0'
assert_eq "$before" "$(_up_sha "$dir")"

t 'an untracked file does not block an upgrade, and is not removed by one'
_up_clone "$ORIGIN" up-untracked
dir=$REPLY
_hop_fix_git -C "$dir" checkout -q -B main v0.1.0
print -r -- 'scratch' > "$dir/notes.txt"
out=$(_up_probe "$dir" '_hop_upgrade' 2>&1)
st=$?
assert_eq 0 "$st" 'an untracked file is not dirt, and must not block an update'
assert_eq "$V2" "$(_up_sha "$dir")"
assert_file "$dir/notes.txt" 'the upgrade cleaned an untracked file, which it must never do'

t 'upgrade --help prints usage and exits 0 without touching anything'
out=$(_up_probe "$dir" '_hop_upgrade --help' 2>&1)
st=$?
assert_eq 0 "$st"
assert_contains "$out" 'usage: hop upgrade'

# ---------------------------------------------------------------------------
# The destructive git verbs must not appear at all.
# ---------------------------------------------------------------------------
# Reading the source is the only assertion that covers a path no test happens to reach.
t 'the upgrade code never cleans, hard-resets or forces anything'
typeset src="$HOP_HOME/lib/upgrade.zsh"
assert_file "$src"
typeset body
body=$(_up_slurp "$src")
assert_not_contains "$body" 'git clean'
assert_not_contains "$body" 'clean -'
assert_not_contains "$body" 'reset --hard'
assert_not_contains "$body" 'checkout -f'
assert_not_contains "$body" 'checkout --force'
assert_not_contains "$body" 'push --force'
assert_not_contains "$body" 'fetch --force'
assert_not_contains "$body" 'rm -rf'
assert_not_contains "$body" 'git stash'
assert_not_contains "$body" 'git reset'
assert_not_contains "$body" 'merge --no-ff'
assert_not_contains "$body" 'git rebase'
assert_contains "$body" '--ff-only' 'main is only ever advanced by fast-forward'

# ---------------------------------------------------------------------------
# Wiring: hop.zsh, the usage text and the completion all have to know about it.
# ---------------------------------------------------------------------------
t 'sourcing hop.zsh defines _hop_upgrade'
typeset defined
defined=$(hop_probe '(( ${+functions[_hop_upgrade]} )) && print -r -- yes')
assert_eq yes "$defined"

t 'the usage text lists the upgrade verb'
typeset usage
usage=$(hop_probe '_hop_usage')
assert_contains "$usage" 'hop upgrade'
assert_contains "$usage" 'hop upgrade --check'

t 'the completion offers upgrade and can list local release tags'
typeset comp
comp=$(_up_slurp "$HOP_HOME/completions/_hop")
assert_contains "$comp" 'upgrade'
assert_contains "$comp" '_hop_versions'

t 'hop.plugin.zsh parses, and is nothing but a shim onto hop.zsh'
# It is listed here rather than in suite_smoke because the install recipes are what depend on it.
assert_file "$HOP_HOME/hop.plugin.zsh"
assert_status 0 zsh -n "$HOP_HOME/hop.plugin.zsh"
typeset shim
shim=$(HOP_HOPRC='' HOP_HISTFILE=/dev/null HOP_CONFIG="$(_hop_fix_config)" \
	zsh -f -c "source ${(q)HOP_HOME}/hop.plugin.zsh || exit 97
print -r -- \$HOP_HOME
(( \${+functions[hop]} )) && print -r -- hop")
assert_eq "${HOP_HOME}"$'\nhop' "$shim" 'the shim must define hop and derive the same HOP_HOME'

t 'upgrade is only the verb as the first word, so a query can still contain it'
# `hop -k file upgrade` has to stay a search, or naming a target `upgrade` would be unreachable.
typeset entry
entry=$(_up_slurp "$HOP_HOME/hop.zsh")
assert_contains "$entry" 'if (( $#words || opts )); then'
