#!/usr/bin/env zsh
# hop upgrade: move the checkout at $HOP_HOME onto a release tag, or refuse and say why.
# - The install is a plain git clone, so an update is a fetch plus a checkout and nothing else.
# - Every refusal here exists because the alternative is destroying work that cannot be recovered.
# - Nothing forces, cleans, resets or stashes: git's own refusal to clobber IS the safety net.
# - A sourced function cannot re-source itself mid-call, so the caller is told to run `exec zsh`.
# - People who installed through a plugin manager should update there instead; see the README.

# _hop_up_git <args...> -> git against the install, never against the caller's $PWD.
_hop_up_git() {
	emulate -L zsh
	git -C "$HOP_HOME" "$@"
}

# _hop_up_err <line...> -> one refusal on stderr, reason first, prefixed so it is attributable.
_hop_up_err() {
	emulate -L zsh
	local l
	for l in "$@"; do
		print -ru2 -- "hop upgrade: ${l}"
	done
	return 1
}

_hop_up_usage() {
	emulate -L zsh
	print -r -- 'usage: hop upgrade [--check] [VERSION]'
	print -r -- ''
	print -r -- '  hop upgrade           move the install to the newest release tag'
	print -r -- '  hop upgrade 0.1.0     pin to exactly that release (v0.1.0 works too)'
	print -r -- '  hop upgrade --check   report installed vs released, changing nothing'
	print -r -- ''
	print -r -- "  updates ${HOP_HOME}"
	print -r -- '  refuses when that checkout is dirty, on a side branch, or has no origin'
	print -r -- '  installed through zinit, antidote, sheldon or oh-my-zsh? update there instead'
}

# _hop_up_guard_repo -> 0 when $HOP_HOME is an install this command can even reason about.
# - Both `--check` and a real update need these two facts, so they are separated from the rest.
_hop_up_guard_repo() {
	emulate -L zsh
	local top
	if ! top=$(_hop_up_git rev-parse --show-toplevel 2>/dev/null) || [[ -z $top ]]; then
		_hop_up_err "${HOP_HOME} is not a git checkout, so there is nothing to update." \
			'Reinstall it with a plugin manager or a clone; see the README install section.'
		return 1
	fi
	# A vendored copy inside another repo would make this command move THAT repo's HEAD.
	if [[ ${top:A} != ${HOP_HOME:A} ]]; then
		_hop_up_err "${HOP_HOME} is not a checkout of its own; it sits inside ${top}." \
			'Updating would move that repo rather than hop, so this refuses.'
		return 1
	fi
	if ! _hop_up_git remote get-url origin >/dev/null 2>&1; then
		_hop_up_err 'this checkout has no `origin` remote, so there is nowhere to fetch from.' \
			"Add one: git -C ${HOP_HOME} remote add origin <url>"
		return 1
	fi
	return 0
}

# _hop_up_guard_move -> 0 when HEAD may be moved, else it explains what is in the way.
# - Only a mutating run calls this, because none of it is a reason to refuse a read-only report.
# - Untracked files are deliberately NOT dirt: git's own checkout refuses to overwrite one.
_hop_up_guard_move() {
	emulate -L zsh
	local dirty branch
	dirty=$(_hop_up_git status --porcelain --untracked-files=no 2>/dev/null)
	if [[ -n $dirty ]]; then
		_hop_up_err 'the install has uncommitted changes, and an update would discard them.' \
			'Commit or stash them first. Changed:'
		print -ru2 -- "$dirty"
		return 1
	fi
	if branch=$(_hop_up_git symbolic-ref --quiet --short HEAD 2>/dev/null); then
		if [[ $branch != main ]]; then
			_hop_up_err "HEAD is on branch ${branch}, not main." \
				'That is work in progress as far as this command can tell, so it refuses.'
			return 1
		fi
		return 0
	fi
	# Detached is the NORMAL state after a pin, but only while parked exactly on a tag.
	if ! _hop_up_git describe --tags --exact-match HEAD >/dev/null 2>&1; then
		_hop_up_err 'HEAD is detached at a commit that is not a release tag.' \
			"Get back on main first: git -C ${HOP_HOME} checkout main"
		return 1
	fi
	return 0
}

# _hop_up_tags -> every release tag, newest first, and only the strictly vX.Y.Z shaped ones.
# - A `v0.2.0-rc1` or a topic tag must never be able to become "latest".
_hop_up_tags() {
	emulate -L zsh
	local out
	out=$(_hop_up_git tag --list 'v*' --sort=-v:refname 2>/dev/null)
	local -a tags=(${(f)out})
	tags=(${tags:#})
	tags=(${(M)tags:#v<->.<->.<->})
	(( $#tags )) || return 1
	print -rl -- "${tags[@]}"
}

# _hop_up_norm <version> -> REPLY is the tag name, accepting `0.1.0` and `v0.1.0` alike.
_hop_up_norm() {
	emulate -L zsh
	local v=${1#v}
	if [[ $v != <->.<->.<-> ]]; then
		_hop_up_err "not a version: ${1}" 'Expected X.Y.Z, for example 0.1.0 or v0.1.0.'
		return 1
	fi
	REPLY="v${v}"
	return 0
}

# _hop_up_current -> REPLY is what is installed now, from the VERSION file when there is one.
# - VERSION is the release's own claim about itself, so it is the honest answer when present.
# - `git describe` is the fallback, and is also what a checkout between two tags reports.
_hop_up_current() {
	emulate -L zsh
	local v=''
	if [[ -r $HOP_HOME/VERSION ]]; then
		v=$(<"$HOP_HOME/VERSION")
		v=${v//[[:space:]]/}
	fi
	if [[ -z $v ]]; then
		v=$(_hop_up_git describe --tags --always --dirty 2>/dev/null)
	fi
	REPLY=${v:-unknown}
	return 0
}

# _hop_upgrade [--check] [VERSION] -> the whole verb, and the only function hop() calls.
_hop_upgrade() {
	emulate -L zsh
	setopt local_options no_nomatch
	local -i check=0
	local want=''

	while (( $# )); do
		case $1 in
			--check | --dry-run | -n)
				check=1
				shift
				;;
			-h | --help)
				_hop_up_usage
				return 0
				;;
			-*)
				_hop_up_err "unknown option: $1" 'Try: hop upgrade --help'
				return 2
				;;
			*)
				if [[ -n $want ]]; then
					_hop_up_err "takes at most one version, got ${want} and $1"
					return 2
				fi
				want=$1
				shift
				;;
		esac
	done

	if (( ! ${+commands[git]} )); then
		_hop_up_err 'git is not installed, and the install is a git checkout.'
		return 1
	fi

	_hop_up_guard_repo || return 1

	local REPLY
	local tag=''
	if [[ -n $want ]]; then
		_hop_up_norm "$want" || return 2
		tag=$REPLY
	fi

	# Only tags are ever consulted, so fetching just tags is the entire network step.
	# - git's own message is left visible, because "why did the fetch fail" is the useful part.
	if ! _hop_up_git fetch --quiet --tags origin; then
		_hop_up_err 'could not fetch from origin, so nothing was changed.'
		return 1
	fi

	local out
	out=$(_hop_up_tags)
	local -a tags=(${(f)out})
	tags=(${tags:#})
	local latest=${tags[1]:-}

	_hop_up_current
	local current=$REPLY
	local head at
	head=$(_hop_up_git rev-parse --short HEAD 2>/dev/null)
	at=$(_hop_up_git describe --tags --exact-match HEAD 2>/dev/null)

	if (( check )); then
		printf '  %-10s %s\n' installed "${current}${head:+  (${head})}"
		if [[ -z $latest ]]; then
			printf '  %-10s %s\n' released 'none yet, so there is nothing to update to'
			return 0
		fi
		printf '  %-10s %s\n' released "$latest"
		if [[ -n $at && $at == $latest ]]; then
			print -r -- '  up to date'
			return 0
		fi
		print -r -- "  an update is available: run 'hop upgrade'"
		# Reporting exits 0 regardless, but naming a blocker now beats surprising them later.
		_hop_up_guard_move || true
		return 0
	fi

	_hop_up_guard_move || return 1

	if [[ -z $tag ]]; then
		if [[ -z $latest ]]; then
			_hop_up_err 'origin has no release tags yet, so there is nothing to update to.' \
				"Installed: ${current}${head:+ (${head})}"
			return 1
		fi
		tag=$latest
	fi

	if ! _hop_up_git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null 2>&1; then
		_hop_up_err "no such release: ${tag}"
		(( $#tags )) && print -ru2 -- "hop upgrade: available: ${(j:, :)tags}"
		return 1
	fi

	local from to
	from=$(_hop_up_git rev-parse HEAD 2>/dev/null)
	to=$(_hop_up_git rev-parse "refs/tags/${tag}^{commit}" 2>/dev/null)
	if [[ -n $from && $from == $to ]]; then
		print -r -- "hop is already at ${tag}, so nothing changed."
		return 0
	fi

	# A plain checkout, never a force, so anything in the way stops this instead of being lost.
	# - advice.detachedHead is silenced because parking on a tag is the INTENDED end state.
	if ! _hop_up_git -c advice.detachedHead=false checkout --quiet "refs/tags/${tag}"; then
		_hop_up_err "git refused to check out ${tag}, so nothing was changed." \
			'Its own message above names what is in the way.'
		return 1
	fi

	_hop_up_current
	print -r -- "hop is now at ${tag} (was ${current}${head:+ at ${head}})."
	print -r -- "Run 'exec zsh' to load it: a sourced function cannot replace itself mid-call."
	return 0
}
