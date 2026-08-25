#!/usr/bin/env zsh
# hop's kind registry and generic enumeration engine.
# - A kind is DECLARED with `hop_kind` rather than hand-written, in one of three shapes.
# - --dirs: every child directory of a base, optionally N levels down.
# - --files: every tracked file matching a pathspec.
# - --marker: every directory holding a marker file, its path segments mapped to columns.
# - --fn: the escape hatch for a family too irregular to declare, still registered as a kind.
# - Registration is the one source of truth for --help, the `:` menu and the completions alike.

# The registry. Parallel maps keyed by kind name, plus one array holding the display order.
typeset -ga _HOP_ALL_KINDS=()
typeset -gA _HOP_K_DESC=()
typeset -gA _HOP_K_SHAPE=()
typeset -gA _HOP_K_DIRS=()
typeset -gA _HOP_K_DEPTH=()
typeset -gA _HOP_K_GLOBS=()
typeset -gA _HOP_K_MARKER=()
typeset -gA _HOP_K_UNDER=()
typeset -gA _HOP_K_LAYOUTS=()
typeset -gA _HOP_K_NAMETPL=()
typeset -gA _HOP_K_NAMEFN=()
typeset -gA _HOP_K_STRIPEXT=()
typeset -gA _HOP_K_EXCLUDE=()
typeset -gA _HOP_K_PREVIEW=()
typeset -gA _HOP_K_PREVIEW_SKIP=()
typeset -gA _HOP_K_SCOPE=()
typeset -gA _HOP_K_TRIM=()
typeset -gA _HOP_K_FN=()
typeset -gA _HOP_K_DEFAULT=()

# hop_kind <name> [options] -> declare or redeclare a kind. README.md has the full option table.
# - Redeclaring a name REPLACES it and keeps its menu position, so config can override a preset.
# - Every value-taking option is checked for one, because a typo would otherwise eat the next flag.
hop_kind() {
	emulate -L zsh
	local name=${1:-}
	if [[ -z $name || $name == -* ]]; then
		print -ru2 -- 'hop_kind: first argument must be a kind name'
		return 2
	fi
	shift

	local shape='' dirs='' depth=1 globs='' marker='' under='' nametpl='' namefn=''
	local exclude='' preview='' pskip='' scope='' trim='' fn='' desc='' stripext=0 default=0
	local -a layouts=()
	local opt

	while (( $# )); do
		opt=$1
		# A value-taking flag with no value is rejected here rather than eating the next flag.
		case $opt in
			--default | --strip-ext) ;;
			--*)
				if (( $# < 2 )); then
					print -ru2 -- "hop_kind ${name}: ${opt} needs a value"
					return 2
				fi
				;;
		esac
		case $opt in
			--default) default=1; shift ;;
			--strip-ext) stripext=1; shift ;;
			--desc) desc=$2; shift 2 ;;
			--dirs) dirs=$2; shape=dirs; shift 2 ;;
			--depth) depth=$2; shift 2 ;;
			--files) globs=$2; shape=files; shift 2 ;;
			--marker) marker=$2; shape=marker; shift 2 ;;
			--under) under=${2%/}; shift 2 ;;
			--layout) layouts+=("$2"); shift 2 ;;
			--name-template) nametpl=$2; shift 2 ;;
			--name-fn) namefn=$2; shift 2 ;;
			--exclude) exclude=$2; shift 2 ;;
			--preview) preview=$2; shift 2 ;;
			--preview-skip) pskip=$2; shift 2 ;;
			--scope-literal) scope=$2; shift 2 ;;
			--trim) trim=$2; shift 2 ;;
			--fn) fn=$2; shape=fn; shift 2 ;;
			*)
				print -ru2 -- "hop_kind ${name}: unknown option: ${opt}"
				return 2
				;;
		esac
	done

	if [[ -z $shape ]]; then
		print -ru2 -- "hop_kind ${name}: needs one of --dirs, --files, --marker or --fn"
		return 2
	fi
	if [[ $shape == fn ]] && (( ! ${+functions[$fn]} )); then
		print -ru2 -- "hop_kind ${name}: --fn ${fn} is not a defined function"
		return 2
	fi
	if [[ $depth != <-> ]] || (( depth < 1 )); then
		print -ru2 -- "hop_kind ${name}: --depth must be a positive integer"
		return 2
	fi

	_HOP_K_DESC[$name]=$desc
	_HOP_K_SHAPE[$name]=$shape
	_HOP_K_DIRS[$name]=$dirs
	_HOP_K_DEPTH[$name]=$depth
	_HOP_K_GLOBS[$name]=$globs
	_HOP_K_MARKER[$name]=$marker
	_HOP_K_UNDER[$name]=$under
	_HOP_K_LAYOUTS[$name]=${(pj:\n:)layouts}
	_HOP_K_NAMETPL[$name]=$nametpl
	_HOP_K_NAMEFN[$name]=$namefn
	_HOP_K_STRIPEXT[$name]=$stripext
	_HOP_K_EXCLUDE[$name]=$exclude
	_HOP_K_PREVIEW[$name]=$preview
	_HOP_K_PREVIEW_SKIP[$name]=$pskip
	_HOP_K_SCOPE[$name]=$scope
	_HOP_K_TRIM[$name]=$trim
	_HOP_K_FN[$name]=$fn
	_HOP_K_DEFAULT[$name]=$default

	(( ${_HOP_ALL_KINDS[(I)$name]} )) || _HOP_ALL_KINDS+=("$name")
	return 0
}

# hop_preset <name>... -> load the kind declarations shipped in presets/<name>.zsh.
# - An unknown preset is an error, because loading nothing looks exactly like a typo working.
hop_preset() {
	emulate -L zsh
	local p f
	for p in "$@"; do
		f="$HOP_HOME/presets/${p}.zsh"
		if [[ ! -r $f ]]; then
			print -ru2 -- "hop_preset: no such preset: ${p}"
			return 1
		fi
		source "$f"
	done
	return 0
}

# _hop_default_kinds -> the kinds declared with --default, in menu order, on stdout.
_hop_default_kinds() {
	emulate -L zsh
	local k
	local -a out=()
	for k in "${_HOP_ALL_KINDS[@]}"; do
		(( ${_HOP_K_DEFAULT[$k]:-0} )) && out+=("$k")
	done
	print -r -- "${(j: :)out}"
}

# _hop_set_default_kinds -> sets $HOP_DEFAULT_KINDS from the registry, without forking.
# - This runs during shell startup, where even one subshell is worth avoiding.
_hop_set_default_kinds() {
	emulate -L zsh
	local k
	local -a out=()
	for k in "${_HOP_ALL_KINDS[@]}"; do
		(( ${_HOP_K_DEFAULT[$k]:-0} )) && out+=("$k")
	done
	typeset -g HOP_DEFAULT_KINDS="${(j: :)out}"
}

# _hop_dsl_preview <dir> <kind> -> REPLY, the first candidate resolving to a non-empty file.
# - A candidate holding * or ? is a glob expanded alphabetically, which is "the first real .tf".
# - Zero-byte files are skipped everywhere: a 0-byte main.tf and values.yaml both render blank.
# - Falls back to the directory, so a row never carries a preview path that cannot be read.
_hop_dsl_preview() {
	emulate -L zsh
	setopt local_options no_nomatch
	local dir=$1 kind=$2
	local -a cands=(${(s:,:)${_HOP_K_PREVIEW[$kind]:-}})
	local -a skips=(${(s:,:)${_HOP_K_PREVIEW_SKIP[$kind]:-}})
	local c f pat
	local -i skip
	for c in "${cands[@]}"; do
		[[ -n $c ]] || continue
		if [[ $c == *'*'* || $c == *'?'* ]]; then
			for f in $dir/${~c}(N.L+0); do
				skip=0
				for pat in "${skips[@]}"; do
					if [[ ${f:t} == ${~pat} ]]; then
						skip=1
						break
					fi
				done
				(( skip )) && continue
				REPLY=$f
				return 0
			done
		else
			[[ -s $dir/$c ]] || continue
			skip=0
			for pat in "${skips[@]}"; do
				if [[ ${c:t} == ${~pat} ]]; then
					skip=1
					break
				fi
			done
			(( skip )) && continue
			REPLY="$dir/$c"
			return 0
		fi
	done
	REPLY=$dir
	return 0
}

# _hop_dsl_excluded <kind> <relative-path> -> true when an --exclude glob matches.
_hop_dsl_excluded() {
	emulate -L zsh
	local kind=$1 rel=$2 pat
	local -a pats=(${(s:,:)${_HOP_K_EXCLUDE[$kind]:-}})
	for pat in "${pats[@]}"; do
		[[ -n $pat ]] || continue
		[[ $rel == ${~pat} ]] && return 0
	done
	return 1
}

# _hop_dsl_columns <kind> <path> -> `reply` is (scope env region name); 1 when no layout fits.
# - Layouts are tried LONGEST FIRST, so a deep path cannot be captured by a shallower layout.
# - A trailing `...` swallows every remaining segment, rendering a nested unit as parent/child.
# - A path matching no layout is not a target, which is what excludes a shared partial at depth 1.
_hop_dsl_columns() {
	emulate -L zsh
	local kind=$1 path=$2
	local -a segs=(${(s:/:)path})
	local -i n=$#segs
	local -a lays=(${(f)${_HOP_K_LAYOUTS[$kind]:-}})
	lays=(${lays:#})

	local scope='-' env='-' region='-' name='-'

	if (( $#lays == 0 )); then
		# No layout declared: the basename is the name and its parent directory is the scope.
		name=${path:t}
		scope=${path:h}
		[[ $scope == $path ]] && scope='-'
		reply=("$scope" "$env" "$region" "$name")
		return 0
	fi

	# Zero-padded counts let a plain reverse sort order the layouts by width, longest first.
	local -a keyed=()
	local l
	for l in "${lays[@]}"; do
		keyed+=("${(l:3::0:)${#${(s:,:)l}}}"$'\t'"$l")
	done
	keyed=("${(@O)keyed}")

	local -a cols
	local col val
	local -i i want greedy matched=0
	for l in "${keyed[@]}"; do
		l=${l#*$'\t'}
		cols=(${(s:,:)l})
		want=$#cols
		greedy=0
		[[ ${cols[-1]} == *... ]] && greedy=1
		if (( greedy )); then
			(( n >= want )) || continue
		else
			(( n == want )) || continue
		fi
		for (( i = 1; i <= want; i++ )); do
			col=${cols[$i]}
			if [[ $col == *... ]]; then
				col=${col%...}
				val=${(j:/:)segs[$i,-1]}
			else
				val=${segs[$i]}
			fi
			case $col in
				scope) scope=$val ;;
				env) env=$val ;;
				region) region=$val ;;
				name) name=$val ;;
			esac
		done
		matched=1
		break
	done
	(( matched )) || return 1

	# --trim drops a prefix that is an artefact of a directory convention, not information.
	local spec c p
	for spec in ${(s:,:)${_HOP_K_TRIM[$kind]:-}}; do
		[[ $spec == *:* ]] || continue
		c=${spec%%:*}
		p=${spec#*:}
		case $c in
			scope) scope=${scope#$p} ;;
			env) env=${env#$p} ;;
			region) region=${region#$p} ;;
			name) name=${name#$p} ;;
		esac
	done

	# The template runs after trimming, so a composed name inherits the trimmed columns.
	local tpl=${_HOP_K_NAMETPL[$kind]:-}
	if [[ -n $tpl ]]; then
		tpl=${tpl//'{scope}'/$scope}
		tpl=${tpl//'{env}'/$env}
		tpl=${tpl//'{region}'/$region}
		name=$tpl
	fi

	reply=("$scope" "$env" "$region" "$name")
	return 0
}

# _hop_dsl_dirs <root> <kind> -> one row per child directory of each base, --depth levels down.
_hop_dsl_dirs() {
	emulate -L zsh
	local root=$1 kind=$2
	local -i depth=${_HOP_K_DEPTH[$kind]:-1}
	local lit=${_HOP_K_SCOPE[$kind]:-}
	local base child dir REPLY
	local -a reply kids
	for base in ${(s:,:)${_HOP_K_DIRS[$kind]:-}}; do
		[[ -n $base && -d $root/$base ]] || continue
		_hop_child_dirs "$root" "$base" $depth || continue
		kids=("${reply[@]}")
		for child in "${kids[@]}"; do
			dir="$root/$base/$child"
			_hop_dsl_preview "$dir" "$kind"
			_hop_row "$kind" "${lit:-$base}" '-' '-' "$child" "$dir" "$REPLY"
		done
	done
}

# _hop_dsl_files <root> <kind> -> one row per tracked file; dir is its parent, preview is the file.
_hop_dsl_files() {
	emulate -L zsh
	local root=$1 kind=$2
	local under=${_HOP_K_UNDER[$kind]:-}
	local lit=${_HOP_K_SCOPE[$kind]:-}
	local namefn=${_HOP_K_NAMEFN[$kind]:-}
	local -i stripext=${_HOP_K_STRIPEXT[$kind]:-0}
	local -a globs=(${(s:,:)${_HOP_K_GLOBS[$kind]:-}})
	local -a reply
	_hop_ls "$root" "${globs[@]}" || return 0

	local rel path abs REPLY
	local -a rows=("${reply[@]}")
	for rel in "${rows[@]}"; do
		abs="$root/$rel"
		# A tracked path is not always a regular file: a submodule gitlink is one, and previews as nothing.
		[[ -f $abs ]] || continue
		_hop_dsl_excluded "$kind" "$rel" && continue
		path=$rel
		[[ -n $under ]] && path=${path#$under/}
		(( stripext )) && path=${path%.*}
		_hop_dsl_columns "$kind" "$path" || continue
		if [[ -n $namefn ]]; then
			"$namefn" "$root/$rel"
			reply[4]=$REPLY
		fi
		# :h of the ABSOLUTE path, because :h of a root-level relative path is '.'.
		_hop_row "$kind" "${lit:-${reply[1]}}" "${reply[2]}" "${reply[3]}" "${reply[4]}" \
			"${abs:h}" "$abs"
	done
}

# _hop_dsl_marker <root> <kind> -> one row per directory holding the marker file.
_hop_dsl_marker() {
	emulate -L zsh
	local root=$1 kind=$2
	local marker=${_HOP_K_MARKER[$kind]}
	local under=${_HOP_K_UNDER[$kind]:-}
	local lit=${_HOP_K_SCOPE[$kind]:-}
	local spec
	if [[ -n $under ]]; then
		[[ -d $root/$under ]] || return 0
		spec="${under}/**/${marker}"
	else
		spec="**/${marker}"
	fi

	local -a reply
	_hop_ls "$root" "$spec" || return 0

	local rel path dir abs REPLY
	local -a rows=("${reply[@]}")
	for rel in "${rows[@]}"; do
		_hop_dsl_excluded "$kind" "$rel" && continue
		path=${rel%/$marker}
		[[ -n $under ]] && path=${path#$under/}
		_hop_dsl_columns "$kind" "$path" || continue
		# :h of the ABSOLUTE path, because :h of a root-level relative path is '.'.
		abs="$root/$rel"
		dir=${abs:h}
		_hop_dsl_preview "$dir" "$kind"
		_hop_row "$kind" "${lit:-${reply[1]}}" "${reply[2]}" "${reply[3]}" "${reply[4]}" "$dir" "$REPLY"
	done
}

# _hop_dsl_emit <root> <kind> -> the rows for one registered kind, whatever its shape.
_hop_dsl_emit() {
	emulate -L zsh
	local root=$1 kind=$2
	case ${_HOP_K_SHAPE[$kind]:-} in
		dirs) _hop_dsl_dirs "$root" "$kind" ;;
		files) _hop_dsl_files "$root" "$kind" ;;
		marker) _hop_dsl_marker "$root" "$kind" ;;
		fn) "${_HOP_K_FN[$kind]}" "$root" ;;
		*) return 1 ;;
	esac
	return 0
}
