#!/usr/bin/env zsh
# hop workspaces: the level ABOVE a repo.
# - A workspace is just a directory that holds repos, e.g. ~/src or ~/work/code.
# - Configured in a plain file so it is editable without touching any code.
# - Precedence: $HOP_WORKSPACES (ad-hoc) beats the file, the file beats the built-in default.

typeset -g HOP_WORKSPACES_FILE=${HOP_WORKSPACES_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/hop/workspaces}

# _hop_ws_expand <string> -> REPLY, with a leading ~ and any $VAR resolved.
# - Never eval: this file lives in the user's dotfiles, so a stray backtick would be code execution.
# - Only a LEADING tilde expands, because a mid-path ~ is a legal character in a real filename.
# - An unset variable expands to empty, matching how a shell would treat it.
_hop_ws_expand() {
	emulate -L zsh
	local s=$1
	case $s in
		'~') s=$HOME ;;
		'~/'*) s="${HOME}/${s#\~/}" ;;
	esac

	local out='' rest=$s name
	while [[ $rest == *'$'* ]]; do
		out+="${rest%%\$*}"
		rest=${rest#*\$}
		if [[ $rest == '{'* ]]; then
			name=${${rest#\{}%%\}*}
			rest=${rest#*\}}
		else
			# The leading run of identifier characters is the name; anything else ends it.
			name=${rest%%[^A-Za-z0-9_]*}
			rest=${rest#$name}
		fi
		[[ -n $name ]] && out+="${(P)name}"
	done
	REPLY="${out}${rest}"
}

# _hop_ws_parse -> sets `reply` to "name<TAB>path" entries, in file order.
# - Accepts `name = path` and a bare `path`, whose name is then the basename.
# - A configured path that is missing or unreadable is skipped SILENTLY, per the spec:
#   the user listed a personal directory that does not exist yet.
# - Only a full-line `#` or a ` #` run starts a comment, so a path containing # still works.
_hop_ws_parse() {
	emulate -L zsh
	# extended_glob is what makes [[:space:]]## strip a RUN; a bare ' ' pattern strips one space.
	setopt local_options no_nomatch extended_glob
	reply=()

	local -a raw
	if [[ -n ${HOP_WORKSPACES:-} ]]; then
		raw=("${(s.:.)HOP_WORKSPACES}")
	elif [[ -r $HOP_WORKSPACES_FILE ]]; then
		raw=("${(@f)$(<"$HOP_WORKSPACES_FILE")}")
	else
		# With no config, guess the conventional places people keep checkouts.
		# - A path that does not exist is dropped below, so listing several costs nothing.
		raw=("$HOME/src" "$HOME/code" "$HOME/projects" "$HOME/dev" "$HOME/work")
	fi

	local line name path REPLY
	local -A seen
	for line in "${raw[@]}"; do
		# CRLF files are common enough to be worth one substitution.
		line=${line%$'\r'}
		line=${line##[[:space:]]##}
		[[ -z $line || $line == '#'* ]] && continue
		line=${line%%[[:space:]]##\#*}
		line=${line%%[[:space:]]##}
		[[ -z $line ]] && continue

		if [[ $line == *=* ]]; then
			name=${line%%=*}
			path=${line#*=}
		else
			name=''
			path=$line
		fi
		name=${${name##[[:space:]]##}%%[[:space:]]##}
		path=${${path##[[:space:]]##}%%[[:space:]]##}
		[[ -z $path ]] && continue

		_hop_ws_expand "$path"
		path=${REPLY:A}
		[[ -d $path && -x $path ]] || continue
		[[ -n $name ]] || name=${path:t}

		# First occurrence of a name wins, so an earlier line is never silently overridden.
		[[ -n ${seen[$name]:-} ]] && continue
		seen[$name]=$path
		reply+=("${name}"$'\t'"${path}")
	done
	(( $#reply ))
}

# _hop_ws_repos <workspace-path> -> sets `reply` to git repos directly inside it.
# - Depth 1 only: a workspace often holds a worktrees dir, and recursing would enumerate every one.
# - A worktree counts as a repo because .git is a FILE there, so -e rather than -d is required.
_hop_ws_repos() {
	emulate -L zsh
	setopt local_options null_glob
	local ws=$1
	reply=()
	local g
	for g in "$ws"/*/.git(N); do
		reply+=("${g:h}")
	done
	reply=("${(@o)reply}")
	(( $#reply ))
}

# _hop_ws_for <dir> -> REPLY, the configured workspace containing <dir>, longest prefix wins.
# - ~/work and ~/work/code are both worth configuring and are nested, so shortest-match is wrong.
_hop_ws_for() {
	emulate -L zsh
	local d=${1:A}
	REPLY=''
	local -a entries
	_hop_ws_parse || return 1
	entries=("${reply[@]}")

	local e p best=''
	for e in "${entries[@]}"; do
		p=${e#*$'\t'}
		if [[ $d == $p || $d == $p/* ]]; then
			(( ${#p} > ${#best} )) && best=$p
		fi
	done
	[[ -n $best ]] || return 1
	REPLY=$best
}

# _hop_provider_ws -> one row per configured workspace, with its repo count.
# - Kept out of _HOP_ALL_KINDS: a workspace is a different scale from a terragrunt unit,
#   and mixing them into one flat list is what the `:` picker exists to avoid.
_hop_provider_ws() {
	emulate -L zsh
	local -a entries
	_hop_ws_parse || return 0
	entries=("${reply[@]}")

	local e name path n
	for e in "${entries[@]}"; do
		name=${e%%$'\t'*}
		path=${e#*$'\t'}
		if _hop_ws_repos "$path"; then
			n=$#reply
		else
			n=0
		fi
		local unit=repos
		(( n == 1 )) && unit=repo
		_hop_row ws "${path/#$HOME/~}" "${n} ${unit}" - "$name" "$path" "$path"
	done
}
