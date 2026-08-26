#!/usr/bin/env zsh
# suite_cache: bin/hop-kinds' per-kind count cache must track the git INDEX, not just HEAD.
# - lib/providers.zsh enumerates via `git ls-files --cached`, which reads the index.
# - `git add` changes what that returns while HEAD stays put; the old (root, HEAD) key missed it.
# - Warming is detached and only runs when the cache file is absent, so every test here polls
#   for it rather than sleeping a fixed amount, the same idea as tests/lib/pty.zsh's own poll.
# - Neither `menu` nor `rows` ever runs fzf, so nothing here needs a stub or a pty.

# cc_repo -> REPLY is a fresh, committed repo with no terraform/ yet, so `tg` starts at 0.
cc_repo() {
	emulate -L zsh
	fixture_repo cachedefect || return 1
	local d=$REPLY
	fixture_write docs/README.md 'hi' || return 1
	fixture_commit initial || return 1
	REPLY=$d
	return 0
}

# cc_menu <root> <cachedir> -> the raw stdout of `hop-kinds menu <root>`.
# - Each caller hands its own throwaway cache dir, so tests never share or race on one cache.
cc_menu() {
	emulate -L zsh
	local root=$1 cachedir=$2
	hop_probe "export XDG_CACHE_HOME=${(q)cachedir}
\${HOP_HOME}/bin/hop-kinds menu ${(q)root}"
}

# cc_has <menu-output> <kind> -> "yes" or "no", read off field 2, which carries no colour codes.
cc_has() {
	emulate -L zsh
	if print -r -- "$1" | cut -f2 | command grep -qx -- "$2"; then
		print -rn -- yes
	else
		print -rn -- no
	fi
}

# cc_wait_files <cachedir> <want> [timeout] -> block until that many counts-* files exist.
cc_wait_files() {
	emulate -L zsh
	local dir=$1
	local -i want=$2
	local -F budget=${3:-5} spent=0
	local -a f
	while (( spent < budget )); do
		f=("$dir/hop"/counts-*(N))
		(( $#f >= want )) && return 0
		sleep 0.05
		(( spent += 0.05 ))
	done
	return 1
}

# cc_wait_other <cachedir> <old-path> [timeout] -> prints a counts-* file that is NOT <old-path>.
# - Sidesteps mtime ordering: the only thing that matters is that a DIFFERENT entry showed up.
cc_wait_other() {
	emulate -L zsh
	local dir=$1 old=$2
	local -F budget=${3:-5} spent=0
	local -a f
	while (( spent < budget )); do
		f=("$dir/hop"/counts-*(N))
		f=(${f:#$old})
		(( $#f )) && { print -rn -- "${f[1]}"; return 0 }
		sleep 0.05
		(( spent += 0.05 ))
	done
	return 1
}

# cc_only <cachedir> -> the sole counts-* file, or empty if there's zero or more than one.
cc_only() {
	emulate -L zsh
	local -a f=("$1/hop"/counts-*(N))
	(( $#f == 1 )) && print -rn -- "${f[1]}"
}

# cc_count <cache-file> <kind> -> the cached count for that kind, or empty if absent.
cc_count() {
	emulate -L zsh
	local f=$1 kind=$2 ck cn
	[[ -r $f ]] || return 1
	while IFS=$'\t' read -r ck cn; do
		[[ $ck == $kind ]] && { print -rn -- "$cn"; return 0 }
	done < "$f"
	return 1
}

# ---------------------------------------------------------------------------
# Baseline: a genuinely empty kind still warms to a real 0 and gets hidden.
# - Not the bug. This is here so the regression test below has something to contrast with.
# ---------------------------------------------------------------------------
t 'a kind with zero targets warms to a real 0 and is then hidden'
cc_repo
local root=$REPLY
local cd
fixture_tmpdir cachedir
cd=$REPLY
local out
out=$(cc_menu "$root" "$cd")
assert_eq 'yes' "$(cc_has "$out" tg)" 'the first render is a cache MISS, so every kind must show, unfiltered'
if cc_wait_files "$cd" 1; then
	out=$(cc_menu "$root" "$cd")
	assert_eq 'no' "$(cc_has "$out" tg)" 'a genuinely empty kind must be hidden once the cache is warm'
	assert_eq '0' "$(cc_count "$(cc_only "$cd")" tg)" 'the warmed cache must record the real, current count'
else
	_hop_t_bad 'the detached warm never wrote a cache file'
fi

# ---------------------------------------------------------------------------
# The bug: `git add`, HEAD unchanged, must not leave a newly staged kind invisible forever.
# ---------------------------------------------------------------------------
t 'git add with HEAD unchanged surfaces a newly staged kind instead of hiding it forever'
cc_repo
root=$REPLY
fixture_tmpdir cachedir2
cd=$REPLY
cc_menu "$root" "$cd" >/dev/null
if ! cc_wait_files "$cd" 1; then
	_hop_t_bad 'the detached warm never wrote a cache file'
else
	local first=$(cc_only "$cd")
	out=$(cc_menu "$root" "$cd")
	assert_eq 'no' "$(cc_has "$out" tg)" 'sanity: tg starts hidden, same as the shipped default install'

	local head_before head_after
	head_before=$(_hop_fix_git -C "$root" rev-parse HEAD)
	mkdir -p -- "$root/terraform/acct/prod"
	print -r -- 'include {}' > "$root/terraform/acct/prod/terragrunt.hcl"
	_hop_fix_git -C "$root" add -A
	head_after=$(_hop_fix_git -C "$root" rev-parse HEAD)
	assert_eq "$head_before" "$head_after" 'sanity: a plain `git add` really does not move HEAD'

	out=$(cc_menu "$root" "$cd")
	assert_eq 'yes' "$(cc_has "$out" tg)" 'a kind staged but not yet committed must not stay invisible'

	local newest
	if newest=$(cc_wait_other "$cd" "$first"); then
		assert_eq '1' "$(cc_count "$newest" tg)" 'the freshly warmed cache must record the real post-add count'
	else
		_hop_t_bad '`git add` did not produce a NEW cache entry: the key is still (root, HEAD) alone'
	fi
fi
