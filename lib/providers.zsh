#!/usr/bin/env zsh
# hop's row primitives, plus the few families too irregular to declare with hop_kind.
# - Every provider emits 3 TAB-separated fields: <display> \t <dir> \t <preview_path>.
# - `display` is pre-padded and ANSI-coloured here, because fzf does not align --with-nth fields.
# - Padding wraps the plain text first, since printf counts an escape sequence's bytes as width.
# - Most kinds live in presets/ as hop_kind declarations; only an irregular family is code.

typeset -g _HOP_OFF=$'\e[0m'
typeset -g _HOP_C_KIND=$'\e[1;36m'
# Scope avoids SGR 33: yellow is the one colour unreadable on either a light or a dark terminal.
typeset -g _HOP_C_SCOPE=$'\e[34m'
typeset -g _HOP_C_REGION=$'\e[36m'
typeset -g _HOP_C_NAME=$'\e[1m'
typeset -g _HOP_C_DIM=$'\e[2m'

# Column order puts `name` first.
# - It is the only field that distinguishes one row from another.
# - The list pane is 45% of the terminal, so a 55-column fixed prefix hid it below ~160 columns.
# - It also makes --tiebreak=begin reward a name-prefix match instead of a kind-prefix match.
typeset -g _HOP_W_NAME=28
typeset -g _HOP_W_KIND=5
typeset -g _HOP_W_SCOPE=22
typeset -g _HOP_W_ENV=9

# Tracked top-level dirs that are never destinations: build output and scratch space.
typeset -ga _HOP_DIR_SKIP=(target tmp)

# _hop_fit <text> <width> [tail] -> REPLY, clipped with an ellipsis rather than overflowing.
# - A fixed-width printf pads but never clips, so one 31-character scope shifted every later column.
# - `tail` keeps the END, for a family whose long names share their first 20-odd characters.
_hop_fit() {
	emulate -L zsh
	local s=$1
	local -i w=$2
	if (( ${#s} <= w )); then
		REPLY=$s
	elif [[ -n ${3:-} ]]; then
		REPLY="…${s[$(( ${#s} - w + 2 )),-1]}"
	else
		REPLY="${s[1,w-1]}…"
	fi
}

# _hop_row <kind> <scope> <env> <region> <name> <dir> <preview>
_hop_row() {
	emulate -L zsh
	local kind=${1:--} scope=${2:--} env=${3:--} region=${4:--} name=${5:--}
	local dir=$6 preview=${7:-$6}
	local pn pk ps pe REPLY

	# name is padded to a floor but never clipped, because it is the discriminator.
	printf -v pn "%-${_HOP_W_NAME}s" "$name"
	_hop_fit "$kind" $_HOP_W_KIND
	printf -v pk "%-${_HOP_W_KIND}s" "$REPLY"
	_hop_fit "$scope" $_HOP_W_SCOPE tail
	printf -v ps "%-${_HOP_W_SCOPE}s" "$REPLY"
	_hop_fit "$env" $_HOP_W_ENV
	printf -v pe "%-${_HOP_W_ENV}s" "$REPLY"

	local ce cs cr
	case $env in
		prod) ce=$'\e[31m' ;;
		staging) ce=$'\e[33m' ;;
		dev | playground) ce=$'\e[34m' ;;
		-) ce=$_HOP_C_DIM ;;
		*) ce=$'\e[35m' ;;
	esac
	if [[ $scope == '-' ]]; then cs=$_HOP_C_DIM; else cs=$_HOP_C_SCOPE; fi
	if [[ $region == '-' ]]; then cr=$_HOP_C_DIM; else cr=$_HOP_C_REGION; fi

	print -r -- "${_HOP_C_NAME}${pn}${_HOP_OFF} ${_HOP_C_KIND}${pk}${_HOP_OFF} ${cs}${ps}${_HOP_OFF} ${ce}${pe}${_HOP_OFF} ${cr}${region}${_HOP_OFF}	${dir}	${preview}"
}

# _hop_ls <root> [pathspec...] -> sets `reply` to the matching tracked paths.
# - NUL in, NUL out: `git ls-files` C-escape-quotes any path holding a backslash or a non-ASCII byte.
# - One real repo tracks a path ending in a space and a backslash, which breaks a newline parser.
# - -z plus the (0) split flag never quotes and never splits on a newline inside a name.
# - Every pathspec gets :(glob) if it lacks a magic prefix, since git's bare '*' crosses '/'.
# - A real git failure is reported, not swallowed: silence looks identical to "no such family".
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

# _hop_child_dirs <root> <family> [depth] -> `reply` is child dirs, git-sorted, .gitkeep-only skipped.
# - A target is a DIRECTORY THAT EXISTS, never a directory containing some particular file.
# - Real repos hold many service directories with no manifest at all, and each is still a target.
# - depth 2 is what finds a vendor/module layout, where a one-level listing returns only containers.
# - A dir needs something tracked BELOW its depth, so a container never becomes a target itself.
# - Pure parameter expansion, so nothing has to convert NUL back to newline for awk.
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

# _hop_first_file <dir> <relative-candidate...> -> sets REPLY to the first NON-EMPTY file.
# - Every chain returns through REPLY rather than stdout, which keeps enumeration fork-free.
# - One repo emits ~1k default rows, so one `$(...)` per row cost more than all the rest combined.
# - -s as well as -f: a 0-byte candidate previews as a blank pane, which is worse than the next one.
# - -f stays because -s alone is true of a directory, and a candidate could name one.
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

# README.md -> README -> CLAUDE.md -> dir
_hop_preview_doc() {
	emulate -L zsh
	local dir=$1
	_hop_first_file "$dir" README.md README CLAUDE.md && return 0
	REPLY="$dir"
}

# docs/playbooks.md -> Chart.yaml -> values.yaml -> charts/*/Chart.yaml -> *.y*ml -> README.md -> dir
# - A runbook leads because it is the page you actually want when jumping to a service.
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

# _hop_entity_name <file> -> REPLY, the YAML metadata.name, falling back to the basename minus .yaml.
# - A fork-free line scan, not a parser: a real parser would cost one fork per catalog file.
# - Only an indented key directly under a column-0 `metadata:` counts, so spec.owner can never win.
# - Bails at the first column-0 key after metadata, and at 40 lines, so a stray large file stays cheap.
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

# helm — chart, values and app families, probed rather than assumed so several repo shapes work.
# - Hand-written rather than declared, because this one kind spans four genuinely different shapes.
# - Half the families are not flat directory lists, and each of those gets its own enumeration.
_hop_provider_helm() {
	emulate -L zsh
	local root=$1
	local rel name REPLY
	local -a reply

	local fam child dir
	local -a kids
	for fam in kubernetes/values services charts; do
		[[ -d $root/$fam ]] || continue
		_hop_child_dirs "$root" "$fam" || continue
		kids=("${reply[@]}")
		for child in "${kids[@]}"; do
			dir="$root/$fam/$child"
			_hop_preview_helm "$dir"
			_hop_row helm "$fam" '-' '-' "$child" "$dir" "$REPLY"
		done
	done

	# kubernetes/charts: the marker is Chart.yaml at ANY depth, so a scaffold subchart still counts.
	# - A flat child listing misses a chart one level deeper and invents its container as a target.
	if [[ -d $root/kubernetes/charts ]] && _hop_ls "$root" ':(glob)kubernetes/charts/**/Chart.yaml'; then
		for rel in "${reply[@]}"; do
			name=${${rel#kubernetes/charts/}%/Chart.yaml}
			_hop_row helm kubernetes/charts '-' '-' "$name" "$root/${rel:h}" "$root/$rel"
		done
	fi

	# kubernetes/services: the deployable unit is a FILE, so a few group dirs are many targets.
	# - `**` is required, because some apps live a level deeper inside their group.
	# - Do NOT filter on `kind: Application`: an ApplicationSet or a multi-document file is real too.
	if [[ -d $root/kubernetes/services ]] && _hop_ls "$root" ':(glob)kubernetes/services/**/*.yaml'; then
		for rel in "${reply[@]}"; do
			[[ $rel == */tests/* ]] && continue   # a tests dir holds a test suite, not an app
			name=${${rel#kubernetes/services/}%.yaml}
			_hop_row helm kubernetes/services '-' '-' "$name" "$root/${rel:h}" "$root/$rel"
		done
	fi

	# cluster-apps is one chart plus loose templates, not a directory family.
	# - A flat listing yields the dead-end row `charts`; what deploys is one template per app.
	local capps=cluster-apps/charts/cluster-apps/templates
	if [[ -d $root/$capps ]] && _hop_ls "$root" ":(glob)$capps/*.yaml"; then
		for rel in "${reply[@]}"; do
			name=${${rel:t}%.yaml}
			_hop_row helm cluster-apps '-' '-' "$name" "$root/$capps" "$root/$rel"
		done
	fi
}

# dir — the repo root plus every top-level tracked directory; this is what gets you back out.
_hop_provider_dir() {
	emulate -L zsh
	local root=$1
	local top dir REPLY
	_hop_preview_doc "$root"
	_hop_row dir '-' '-' '-' '<root>' "$root" "$REPLY"

	local -a reply
	_hop_ls "$root" || return 0
	local -a tops=(${(u)${(M)reply:#*/*}%%/*})
	for top in "${tops[@]}"; do
		(( ${_HOP_DIR_SKIP[(I)$top]} )) && continue
		dir="$root/$top"
		[[ -d $dir ]] || continue
		_hop_preview_doc "$dir"
		_hop_row dir '-' '-' '-' "$top" "$dir" "$REPLY"
	done
}

# repo — used only by the repo picker, never part of a normal kind list.
_hop_provider_repo() {
	emulate -L zsh
	local r REPLY
	for r in "$@"; do
		[[ -n $r && -d $r ]] || continue
		_hop_preview_doc "$r"
		_hop_row repo '-' '-' '-' "${r:t}" "$r" "$REPLY"
	done
}

# _hop_generate <root> <kind...>
# - A registered kind goes through the DSL engine; a bare _hop_provider_<kind> still works.
# - That function fallback is what lets an opt-in .hoprc add a kind without touching the registry.
_hop_generate() {
	emulate -L zsh
	local IFS=$' \t\n\0'
	local root=$1
	shift
	[[ -n $root ]] || return 1

	# A repo-root .hoprc may define extra kinds, and is OPT-IN.
	# - Sourcing it runs arbitrary code from whatever repo you happen to be standing in.
	# - Default-on meant `cd` into any clone plus one `hop` was a code-execution path.
	# - Set HOP_HOPRC=1 to enable it, and only in repos you would already `source` by hand.
	if [[ -n ${HOP_HOPRC:-} && -r $root/.hoprc ]]; then
		source "$root/.hoprc"
	fi

	local k
	for k in "$@"; do
		[[ -n $k ]] || continue
		if (( ${+_HOP_K_SHAPE[$k]} )); then
			_hop_dsl_emit "$root" "$k"
		elif (( ${+functions[_hop_provider_$k]} )); then
			"_hop_provider_$k" "$root"
		else
			print -ru2 -- "hop: unknown kind: $k"
		fi
	done
	return 0
}
