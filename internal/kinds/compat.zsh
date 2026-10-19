#!/usr/bin/env zsh
# hop compat layer: lets a --fn provider written for zsh hop run as a Go hop exec kind.
# - Sourced by the exec line `hop config import` writes, BEFORE the user's config.zsh.
# - hop_kind and hop_preset become no-ops, so sourcing a whole config.zsh only defines its functions.
# - _hop_row prints the exec protocol instead of hop's padded display row.
# - The helpers below are copied verbatim from hop's lib/providers.zsh, so a provider calling them behaves the same.

hop_kind() { : }
hop_preset() { : }

# _hop_row <kind> <scope> <env> <region> <name> <dir> <preview> [f] -> name TAB path TAB preview TAB scope TAB env TAB region
_hop_row() {
	emulate -L zsh
	local dir=$6 preview=${7:-$6} target=$6
	[[ -n ${8:-} ]] && target=$preview
	print -r -- "${5:--}	${target}	${preview}	${2:--}	${3:--}	${4:--}"
}

_hop_ls() {
	emulate -L zsh
	local root=$1
	shift
	local -a specs
	local s
	for s in "$@"; do
		if [[ $s == :* ]]; then specs+=("$s"); else specs+=(":(glob)$s"); fi
	done

	local out msg
	local -i st
	out=$(git -C "$root" ls-files -z --cached -- "${specs[@]}" 2>/dev/null)
	st=$?
	if (( st )); then
		# Failure is rare, so a second git call to recover the message costs nothing normally.
		msg=$(git -C "$root" ls-files --cached -- "${specs[@]}" 2>&1 >/dev/null)
		local -a lines=(${(f)msg})
		print -ru2 -- "hop: git ls-files failed in ${root}: ${lines[1]:-exit ${st}}"
		reply=()
		return 1
	fi
	reply=("${(0)out}")
	reply=(${reply:#})
	return 0
}
_hop_child_dirs() {
	emulate -L zsh
	local root=$1 fam=$2
	local -i depth=${3:-1}
	# `reply` is deliberately NOT local: it is the caller's out-param, same as for _hop_ls.
	_hop_ls "$root" "$fam/" || return 1
	local -a rest
	rest=(${reply#$fam/})
	rest=(${rest:#*/.gitkeep})   # a dir whose only tracked file is .gitkeep is empty
	local p
	local -a out=() segs
	for p in "${rest[@]}"; do
		segs=(${(s:/:)p})
		(( $#segs > depth )) || continue
		out+=("${(j:/:)segs[1,depth]}")
	done
	reply=(${(u)out})
	return 0
}
_hop_first_file() {
	emulate -L zsh
	local dir=$1
	shift
	local c
	for c in "$@"; do
		if [[ -f $dir/$c && -s $dir/$c ]]; then
			REPLY="$dir/$c"
			return 0
		fi
	done
	return 1
}
_hop_preview_doc() {
	emulate -L zsh
	local dir=$1
	_hop_first_file "$dir" README.md README CLAUDE.md && return 0
	REPLY="$dir"
}
_hop_preview_helm() {
	emulate -L zsh
	setopt local_options no_nomatch
	local dir=$1
	_hop_first_file "$dir" docs/playbooks.md Chart.yaml values.yaml && return 0
	local -a c
	# L+0 for the same reason as -s above: an empty file is not a preview.
	c=("$dir"/charts/*/Chart.yaml(N.L+0))
	if (( $#c )); then
		REPLY="${c[1]}"
		return 0
	fi
	c=("$dir"/*.y*ml(N.L+0))
	if (( $#c )); then
		REPLY="${c[1]}"
		return 0
	fi
	_hop_first_file "$dir" README.md && return 0
	REPLY="$dir"
}
_hop_entity_name() {
	emulate -L zsh
	setopt local_options extended_glob
	local file=$1 line val
	local -i n=0 inmeta=0
	REPLY=${${file:t}%.yaml}
	[[ -r $file ]] || return 0
	while (( n < 40 )) && IFS= read -r line; do
		(( n++ ))
		if [[ $line == metadata:* ]]; then
			inmeta=1
			continue
		fi
		(( inmeta )) || continue
		[[ $line == [[:space:]]* ]] || break
		if [[ ${line##[[:space:]]##} == name:[[:space:]]#?* ]]; then
			val=${${line##[[:space:]]##name:}##[[:space:]]#}
			val=${val%%[[:space:]]#}
			val=${${val#[\"\']}%[\"\']}
			[[ -n $val ]] && REPLY=$val
			return 0
		fi
	done < "$file"
	return 0
}
