#!/usr/bin/env zsh
# hop's resolver: what a query names, decided before any picker opens.
# - A ladder of tiers, tried in order: a literal path (T0), exact (T1), a rewrite (T2), loose (T3), relaxed, nothing (T4).
# - "Clear enough to jump" is structural, never a score: fzf exposes no scores, and a margin made real false jumps.
# - Only T0, T1 and T2a (a rewrite of separators or case alone) may jump; every approximate tier opens the picker.
# - fzf stays the only matcher, through _hop_filter, so the picker and this file agree on every row.
# - A plain ${t} in a pattern is already literal here, so (b) belongs only where the text is re-parsed: subscripts and ${~...}.
# - Elsewhere (b) adds real backslashes, and a name holding [ * # or ? then never matched.

# Above this many rows T2 and T3 are skipped, because the vocabulary pass grows with the row count.
# - Measured: T2 took 177ms at 6041 rows, against a 100ms budget.
typeset -gi _HOP_APPROX_MAX=6000

# Env words people shorten in ways no typo rule reaches: stg is four letters short of staging.
# - Used only when no row holds the short form and some row holds the long one as a whole word, and never to jump.
typeset -gA _HOP_ENV_WORDS=(
	prd prod
	production prod
	stg staging
	stag staging
	stage staging
	devel dev
	develop dev
	development dev
)

# _hop_filter <query> [fzf-arg...]  <rows on stdin -> the matching rows on stdout, best first.
# - The ONLY fzf --filter call in hop, so every resolve matches exactly the way the picker will.
# - --no-sort never reaches it: on 0.60.3, --filter --no-sort with --with-nth=1,4 prints the TRANSFORMED line.
# - --accept-nth never reaches it either: 0.73.1 honours it under --filter while 0.60.3 and 0.67.0 ignore it.
# - So the rows always come back whole, and with --ansi fzf prints them with their SGR stripped.
# - fzf's stderr is NOT suppressed: --filter still parses every option, and a genuine complaint must reach the user.
# - The user's FZF_DEFAULT_OPTS never reach it: --no-sort there made 0.60.3 print the transformed line, so a jump cd'd to ''.
# - `command` keeps an `alias fzf=...` from being baked into this body when hop.zsh is sourced.
_hop_filter() {
	emulate -L zsh
	local q=$1
	shift
	FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= command fzf --filter="$q" "${_HOP_MATCHER_FLAGS[@]}" "$@"
}

# _hop_match <query> <rows-text> [fzf-arg...] -> reply is the matching rows, best first; 1 when there are none.
_hop_match() {
	emulate -L zsh
	local q=$1 rows=$2
	shift 2
	reply=()
	[[ -n $rows ]] || return 1
	local out
	out=$(print -r -- "$rows" | _hop_filter "$q" "$@")
	reply=("${(@f)out}")
	reply=(${reply:#})
	(( $#reply ))
}

# _hop_rels_of <row...> -> reply is each row's rel, its last field, with the dim stripped.
_hop_rels_of() {
	emulate -L zsh
	setopt local_options extended_glob
	reply=("${(@)${(@)argv##*$'\t'}//$'\e'\[[0-9;]#m/}")
}

# _hop_res_fields <row> -> reply is (dir preview rel), rel undimmed and an empty preview read as the dir.
_hop_res_fields() {
	emulate -L zsh
	setopt local_options extended_glob
	local -a f=("${(@ps:\t:)1}")
	local dir=${f[2]-} preview=${f[3]-} rel=${f[4]-}
	[[ -n $preview ]] || preview=$dir
	reply=("$dir" "$preview" "${rel//$'\e'\[[0-9;]#m/}")
}

# _hop_literal_target <word> <root> -> 0 with reply=(dir preview rel) when the word names a real path.
# - T0: a typed path is a filesystem fact, so it jumps before _hop_generate is ever paid for.
# - Only a word holding a / or starting with ~, or a bare . or .., qualifies, so a plain name always goes to the matcher.
# - A bare . had fuzzy-matched every rel holding a dot, and `hop -o .` is how you open the dir you are in.
# - ./x and ../x are $PWD-relative only; /x is the repo root first, as `hop /` is, then the absolute path.
# - Anything else tries $PWD first, then the root, which is what makes -c's subtree win.
# - The glob is case-insensitive and returns the on-disk spelling, so `Terraform/ACCT-x` cds to `terraform/acct-x`.
# - An exact-case hit wins outright; otherwise exactly one case-insensitive match is required, never a guess.
# - The anchor stays literal, so only the part the user typed is matched without case.
_hop_literal_target() {
	emulate -L zsh
	setopt local_options extended_glob null_glob
	zmodload zsh/parameter 2>/dev/null
	local w=$1 root=${2:-}
	reply=()
	[[ $w == */* || $w == '~'* || $w == (.|..) ]] || return 1
	local p=$w
	[[ $p == ?*/ ]] && p=${p%%/##}

	# Each candidate is an anchor (trusted, literal) and the rest (typed, matched without case).
	local -a anchors rests
	case $p in
		(.|..|./*|../*)
			anchors=("$PWD") rests=("$p")
			;;
		(/*)
			if [[ -n $root ]]; then
				anchors+=("$root") rests+=("${p#/}")
			fi
			anchors+=('/') rests+=("${p#/}")
			;;
		('~'*)
			local head=${p%%/*} tail='' home=''
			[[ $p == */* ]] && tail=${p#*/}
			if [[ $head == '~' ]]; then
				home=$HOME
			elif [[ $head == '~'[[:alnum:]_.-]## ]]; then
				home=${nameddirs[${head#\~}]:-${userdirs[${head#\~}]:-}}
			fi
			[[ -n $home ]] || return 1
			anchors=("$home") rests=("$tail")
			;;
		(*)
			anchors=("$PWD") rests=("$p")
			if [[ -n $root ]]; then
				anchors+=("$root") rests+=("$p")
			fi
			;;
	esac

	local -i i
	local REPLY hit=''
	for (( i = 1; i <= $#anchors; i++ )); do
		_hop_path_under "${anchors[i]}" "${rests[i]}" || continue
		hit=$REPLY
		break
	done
	[[ -n $hit ]] || return 1
	_hop_literal_fields "$hit" "$root"
}

# _hop_path_under <anchor> <rest> -> 0 with REPLY the path rest names under anchor, spelled as the disk spells it.
_hop_path_under() {
	emulate -L zsh
	setopt local_options extended_glob null_glob
	local a=${1:a} f base rest
	local -a g
	REPLY=''
	f="${a%/}/${2}"
	f=${f:a}
	# ../ can climb above the anchor, so the literal part is what the typed path still shares with it.
	base=$a
	while [[ $base != / && $f != "$base" && $f != "$base"/* ]]; do
		base=${base:h}
	done
	rest=${f#"$base"}
	rest=${rest#/}
	if [[ -z $rest ]]; then
		[[ -e $f ]] || return 1
		REPLY=$f
		return 0
	fi
	g=("${base%/}"/(#i)${rest}(N))
	if (( ${g[(Ie)$f]} )); then
		REPLY=$f
	elif (( $#g == 1 )); then
		REPLY=${g[1]}
	else
		return 1
	fi
}

# _hop_literal_fields <hit> <root> -> reply=(dir preview rel) for a path T0 found; a file target cds to its parent.
_hop_literal_fields() {
	emulate -L zsh
	local hit=$1 REPLY _hop_gen_root=${2:+${2:A}}
	if [[ -d $hit ]]; then
		_hop_rel "${hit:A}" "${hit:A}"
		reply=("$hit" "$hit" "$REPLY")
	else
		_hop_rel "${${hit:A}:h}" "${hit:A}" f
		reply=("${hit:h}" "$hit" "$REPLY")
	fi
	return 0
}

# _hop_elsewhere <word> <root> -> 1 when no other repo or workspace holds the path; else 0, with _hop_st the call's status.
# - T0 again, for a path typed outside the repo it lives in: `terraform/x` from ~, or `configuration/terraform/x`.
# - Every repo _hop_repos knows and every workspace root is an anchor, minus $PWD and root for the path as typed, which T0 already tried.
# - A path may start with a repo's own name, which works whether or not a workspace holds that repo.
# - Each anchor costs one case-insensitive glob, and no other repo's rows are ever enumerated.
# - One distinct target jumps, saying where it was found.
# - Several never jump: the same path in a repo and its retired copy is exactly when a guess is wrong.
# - They open a picker over just those, the one in the repo visited most recently first, then by path.
_hop_elsewhere() {
	emulate -L zsh
	setopt local_options extended_glob
	local w=$1 root=${2:+${2:A}}
	w=${w%%/##}
	[[ $w == */* && $w != (/|'~'|./|../)* && /$w/ != */(.|..)/* ]] || return 1
	local -F t0=0
	[[ -n ${HOP_DEBUG:-} ]] && zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null && t0=$EPOCHREALTIME

	# akinds says which anchors are workspace roots, whose repo is the path's first segment.
	local -a anchors rests names akinds reply
	local out a e first=${(L)w%%/*}
	if out=$(_hop_repos); then
		for a in "${(@f)out}"; do
			anchors+=("$a") rests+=("$w") names+=("${a:t}") akinds+=(repo)
			[[ ${(L)a:t} == "$first" ]] && anchors+=("$a") rests+=("${w#*/}") names+=("${a:t}") akinds+=(repo)
		done
	fi
	if _hop_ws_parse; then
		for e in "${reply[@]}"; do
			anchors+=("${e#*$'\t'}") rests+=("$w") names+=("${e%%$'\t'*}") akinds+=(workspace)
		done
	fi

	local -A seen
	local -a hits homes where hkinds
	local cwd=${PWD:A} k rest REPLY
	local -i i
	for (( i = 1; i <= $#anchors; i++ )); do
		a=${anchors[i]:A}
		[[ ${rests[i]} == "$w" && ( $a == "$cwd" || $a == "$root" ) ]] && continue
		_hop_path_under "$a" "${rests[i]}" || continue
		k=${REPLY:A}
		(( ${+seen[$k]} )) && continue
		seen[$k]=1
		hits+=("$REPLY") where+=("${names[i]}") hkinds+=("${akinds[i]}")
		if [[ ${akinds[i]} == workspace ]]; then
			rest=${REPLY#"$a"/}
			homes+=("$a/${rest%%/*}")
		else
			homes+=("$a")
		fi
	done
	(( $#hits )) || return 1

	local _hop_gen_root=''
	if (( $#hits == 1 )); then
		_hop_literal_fields "${hits[1]}" ''
		_hop_elsewhere_log jump 1 "${reply[3]}"
		[[ ${hkinds[1]} == workspace ]] && where[1]="workspace ${where[1]}"
		print -ru2 -- "hop: ${1} -> ${reply[3]} (found in ${where[1]})"
		_hop_dispatch '' "${reply[@]}"
		_hop_st=$?
		return 0
	fi

	# A repo ranks by its first appearance in the history, as the repo or anything inside it, then by path.
	local -a hist keys rows places
	[[ -r ${HOP_HISTFILE:-} ]] && hist=("${(@f)$(<"$HOP_HISTFILE")}")
	for (( i = 1; i <= $#hits; i++ )); do
		keys+=("${(l:6::0:)${hist[(i)${(b)homes[i]}(|/*)]}}${homes[i]}"$'\t'"${hits[i]}"$'\t'"$i")
	done
	_hop_sort_bytes "${keys[@]}"
	for k in "${reply[@]}"; do
		i=${k##*$'\t'}
		places+=("${(D)homes[i]}")
		_hop_literal_fields "${hits[i]}" ''
		if [[ -d ${hits[i]} ]]; then
			rows+=("$(_hop_row dir "${homes[i]:t}" - - "${hits[i]:t}" "${reply[1]}" "${reply[2]}")")
		else
			rows+=("$(_hop_row file "${homes[i]:t}" - - "${hits[i]:t}" "${reply[1]}" "${reply[2]}" f)")
		fi
	done
	_hop_elsewhere_log pick "$#rows"

	local _hop_res_verdict=pick _hop_res_tier=T0 _hop_res_rule=elsewhere _hop_res_query=$1 _hop_res_target=''
	local _hop_res_note="found in ${#rows} places: ${(j:, :)places}"
	local -i _hop_res_n=$#rows _hop_res_m=$#rows _hop_res_inj=0 _hop_res_ready=1
	local -a _hop_res_rows=("${(@)rows//$'\e'\[[0-9;]#m/}")
	_hop_run "paths  ${#rows} found" "$1" '' "${(F)rows}"
	_hop_st=$?
	return 0
}

# _hop_sort_bytes <string...> -> reply is the strings in byte order, so `configuration` sorts before `configuration.old`.
# - (o) collates by locale, and a glibc locale that skips punctuation puts the longer name first.
_hop_sort_bytes() {
	emulate -L zsh
	local LC_ALL=C
	reply=("${(@o)argv}")
}

# _hop_elsewhere_log <verdict> <n> [target] -> _hop_elsewhere's HOP_DEBUG line, timed from its own t0.
_hop_elsewhere_log() {
	emulate -L zsh
	[[ -n ${HOP_DEBUG:-} ]] || return 0
	local ms=-
	(( t0 > 0 )) && printf -v ms '%.1f' $(( (EPOCHREALTIME - t0) * 1000 ))
	_hop_dbg "resolve tier=T0 rule=elsewhere verdict=${1} n=${2} inj=0 q=${w} target=${3:--} ms=${ms}"
}

# _hop_vocab_build <rel...> -> _hop_vocab, _hop_vocab_set and _hop_segs, the words T2 and T3 may rewrite a query into.
# - All three are declared by _hop_resolve, so building them once serves every tier and every relaxed term.
# - _hop_vocab is every rel token split on / - _ . with 2-char tokens dropped, plus the kind names.
# - _hop_vocab_set holds the same words as keys, for the whole-word lookups of _hop_compound.
# - _hop_segs is every whole rel segment, extension stripped, 3 chars or more.
_hop_vocab_build() {
	emulate -L zsh
	setopt local_options extended_glob
	local IFS=' '
	local -a rels=("$@")
	_hop_vocab=(${(u)${(L)${=${(j: :)rels//[\/_.-]/ }}}})
	_hop_vocab=(${_hop_vocab:#?(|?)} "${_HOP_ALL_KINDS[@]}")
	local -a ones=("${(@)_hop_vocab//*/1}")
	_hop_vocab_set=("${(@)_hop_vocab:^ones}")
	_hop_segs=(${(u)${(L)${(s:/:)${(j:/:)rels}}}%.*})
	_hop_segs=(${_hop_segs:#(|?|??)})
}

# _hop_abbrevs <word> -> reply is every vocabulary word the word abbreviates to, letters in order: account -> acct.
# - From 6 chars, and the short form has to be at least half the word and not merely a prefix of it.
_hop_abbrevs() {
	emulate -L zsh
	setopt local_options extended_glob
	local w=$1 v pat
	reply=()
	(( ${#w} >= 6 )) || return 1
	for v in ${(M)_hop_vocab:#${w[1]}*}; do
		(( ${#v} >= 3 && ${#v} < ${#w} && ${#v} * 2 >= ${#w} )) || continue
		pat="${(j:*:)${(@b)${(s::)v}}}*"
		[[ $w == ${~pat} && $w != "$v"* ]] && reply+=("$v")
	done
	(( $#reply ))
}

# _hop_compound <token> -> 0 with reply the two or three vocabulary words, 3 chars or more each, the token runs together.
# - `externaldns` is external dns, and `securitytoolingprod` is security tooling prod.
# - The longest first word wins, and two words before three.
_hop_compound() {
	emulate -L zsh
	local t=$1 a b c
	local -i i j n=${#t}
	reply=()
	for (( i = n - 3; i >= 3; i-- )); do
		a=${t[1,i]} b=${t[i+1,n]}
		if (( ${+_hop_vocab_set[$a]} && ${+_hop_vocab_set[$b]} )); then
			reply=("$a" "$b")
			return 0
		fi
	done
	for (( i = n - 6; i >= 3; i-- )); do
		a=${t[1,i]}
		(( ${+_hop_vocab_set[$a]} )) || continue
		for (( j = n - 3; j >= i + 3; j-- )); do
			b=${t[i+1,j]} c=${t[j+1,n]}
			if (( ${+_hop_vocab_set[$b]} && ${+_hop_vocab_set[$c]} )); then
				reply=("$a" "$b" "$c")
				return 0
			fi
		done
	done
	return 1
}

# _hop_prune <alt...> -> reply is the alternatives that hold no other one, so an fzf OR group matches the same rows.
# - Under --exact a row holding github-actions-deploy-auth already holds github-actions, so the longer one only adds noise.
# - Unpruned, `githubactions` opened on a ten-way OR group that was the picker query and the header both.
_hop_prune() {
	emulate -L zsh
	local a b
	reply=()
	for a in "$@"; do
		for b in "$@"; do
			[[ $a != "$b" && $a == *"$b"* ]] && continue 2
		done
		reply+=("$a")
	done
}

# _hop_rewrite <query> [wide] -> 0 with reply=(approx effq), the query rewritten into fzf OR groups (T2).
# - Every token is split out on whitespace and / - _ . and kept as-is when some vocabulary word contains it.
# - A short env word no word contains reads as its long form before anything else; see _HOP_ENV_WORDS.
# - Any other token no word contains gets typo fixes: zsh's approximate glob, 1 error, or 2 from 8 chars, transposition counted once.
# - A token with neither is split into the words it runs together, else gets the words it abbreviates to.
# - The split comes first: `externaldns` had abbreviated to extras, and the external-dns rows were never offered.
# - Typo before abbreviation, and a word the token merely starts with is refused, fixed `rotuemaster`.
# - That had read as roster|raster, and `routemastr` as route.
# - Only wide abbreviates a token some word already contains, so `routemaster-prod` stays T2a instead of gaining raster.
# - wide abbreviates each typo fix too, so `acount` reaches acct through account.
# - _hop_resolve asks for wide only when the narrow rewrite matched nothing, which is what keeps `account -> acct`.
# - A token nothing explains fails the whole rewrite, so a nonsense word is never invented into a match.
# - approx is 0 when every token survived unchanged, which is T2a: a separator or case change only.
_hop_rewrite() {
	emulate -L zsh
	setopt local_options extended_glob
	local IFS=' '
	local q=${(L)1}
	local -i wide=${2:-0}
	local -a toks=(${=${q//[\/_.-]/ }}) groups alts typo
	local tok w
	local -i n approx=0 exact
	for tok in "${toks[@]}"; do
		if (( ${#tok} < 3 )); then
			groups+=("$tok")
			continue
		fi
		alts=() typo=() exact=0
		if (( ${_hop_vocab[(I)*${(b)tok}*]} )); then
			exact=1
			alts+=("$tok")
		elif [[ -n ${_HOP_ENV_WORDS[$tok]:-} ]] && (( ${+_hop_vocab_set[${_HOP_ENV_WORDS[$tok]}]} )); then
			groups+=("${_HOP_ENV_WORDS[$tok]}")
			approx=1
			continue
		elif (( ${#tok} >= 4 )); then
			n=$(( ${#tok} >= 8 ? 2 : 1 ))
			typo=(${(M)_hop_vocab:#(#a${n})${tok}})
			alts+=("${typo[@]}")
		fi
		# A run-together token becomes separate terms, so no OR group can hold it.
		if (( ! exact && ! $#typo && ${#tok} >= 6 )) && _hop_compound "$tok"; then
			groups+=("${reply[@]}")
			approx=1
			continue
		fi
		if (( ! $#typo && ( ! exact || wide ) )); then
			_hop_abbrevs "$tok" && alts+=("${reply[@]}")
		fi
		if (( wide )); then
			for w in "${typo[@]}"; do
				_hop_abbrevs "$w" && alts+=("${reply[@]}")
			done
		fi
		_hop_prune "${(@u)alts}"
		alts=("${reply[@]}")
		(( $#alts )) || return 1
		[[ ${(j: :)alts} == "$tok" ]] || approx=1
		groups+=("${(j: | :)alts}")
	done
	(( $#groups )) || return 1
	reply=("$approx" "${(j: :)groups}")
	[[ ${reply[2]} != "$q" ]]
}

# _hop_loose <query> -> 0 with REPLY the query rewritten into whole rel segments (T3), strictly.
# - A term inside some segment is kept; otherwise a segment must start with it as a subsequence.
# - And the segment's initials must start with the term, or the term must be at least a third of it.
# - That is what keeps it strict: measured 6 hits in 500 nonsense words, where a display-wide fuzzy pass hit 169.
_hop_loose() {
	emulate -L zsh
	setopt local_options extended_glob
	local IFS=$' \t'
	local q=${(L)1}
	local -a terms=(${=q}) groups hit
	local tok s pat ini
	local -i i
	for tok in "${terms[@]}"; do
		hit=()
		if (( ${_hop_segs[(I)*${(b)tok}*]} )); then
			hit=("$tok")
		elif (( ${#tok} >= 3 )); then
			pat=${(b)tok[1]}
			for (( i = 2; i <= ${#tok}; i++ )); do
				pat+="*${(b)tok[i]}"
			done
			for s in ${(M)_hop_segs:#${~pat}*}; do
				ini=${(j::)${(M)${(s:-:)${s//[_.]/-}}#?}}
				if [[ $ini == "$tok"* ]] || (( ${#tok} * 3 >= ${#s} )); then
					hit+=("$s")
				fi
			done
		fi
		(( $#hit )) || return 1
		_hop_prune "${hit[@]}"
		groups+=("${(j: | :)reply}")
	done
	(( $#groups )) || return 1
	REPLY="${(j: :)groups}"
	[[ $REPLY != "$q" ]]
}

# _hop_minimal <rel...> -> reply is the rels no other given rel is an ancestor of, sorted.
# - Ancestry is tested by walking each rel's own parents, never by sorting: (o) collates by locale.
# - Under a collation that ignores punctuation, `a-c/` and `a/b/` stop sorting where a prefix scan needs them.
_hop_minimal() {
	emulate -L zsh
	local -A have
	local r p
	for r in "$@"; do
		have[$r]=1
	done
	reply=()
	for r in "${(@k)have}"; do
		p=${r%/}
		while [[ $p == */* ]]; do
			p=${p%/*}
			(( ${+have[$p/]} )) && continue 2
		done
		reply+=("$r")
	done
	reply=("${(@o)reply}")
}

# _hop_ancestors <under-rel> <rel...> -> reply is every strict ancestor dir of the rels, minus dirs already among them.
# - The rels are repo-relative, so the walk stops at `.`; a `~` or absolute rel names no ancestor inside the repo.
# - under-rel is the -c subtree relative to the root, or empty; only ancestors strictly beneath it survive.
_hop_ancestors() {
	emulate -L zsh
	setopt local_options extended_glob
	local under=$1
	shift
	local -a have cur anc
	have=(${${(M)argv:#*/}%/})
	cur=(${(u)${${argv:#[/~]*}%/}:h})
	while (( $#cur )); do
		cur=(${cur:#(.|/)})
		anc+=("${cur[@]}")
		cur=(${(u)cur:h})
	done
	anc=(${(u)anc})
	anc=(${anc:|have})
	[[ -n $under ]] && anc=(${(M)anc:#${under}/*})
	reply=("${anc[@]}")
}

# _hop_aligned <dir-rel> <term...> -> 0 when every term names a whole token run of the dir, one of them its last segment.
# - This is J2's test: `kub` inside kubernetes/ and `curity-tooling-prod/env-pr` must not jump.
# - `security-tooling-prod` inside acct-security-tooling-prod/ and `infrastructure dev` may.
_hop_aligned() {
	emulate -L zsh
	setopt local_options extended_glob
	local x="/${(L)1}" t
	shift
	local -i last=0
	for t in "$@"; do
		t=${${t#/}%/}
		[[ $x == *[/_.-]${t}[/_.-]* ]] || return 1
		[[ $x == *[/_.-]${t}/ ]] && last=1
	done
	(( last ))
}

# _hop_coherence <query> <row...> -> reply is the rows, stably bucketed by how many query terms one rel segment holds.
# - It lifts `acct sec prod`'s acct-security-tooling-prod units above secor and secrets, which match one term per segment.
# - An OR group counts once and a negated term never counts; measured 0.3ms at 6 rows and 12ms at 669.
# - It orders the picker on open only: fzf's own ranking returns at the first keystroke.
_hop_coherence() {
	emulate -L zsh
	setopt local_options extended_glob
	local IFS=$' \t'
	local -a words=(${=${(L)1}}) pats
	shift
	local w
	local -i join=0
	for w in "${words[@]}"; do
		if [[ $w == '|' ]]; then
			join=1
			continue
		fi
		w=${${w#[\'^]}%\$}
		if (( join && $#pats )); then
			pats[-1]+="|${w}"
		else
			pats+=("$w")
		fi
		join=0
	done
	pats=(${pats:#\!*})
	reply=("$@")
	(( $#pats >= 2 && $# <= 500 )) || return 0

	local -a rels scores
	local -i i best c top=0 s
	local seg p a
	_hop_rels_of "$@"
	rels=("${reply[@]}")
	for (( i = 1; i <= $#; i++ )); do
		best=0
		for seg in "${(@s:/:)${(L)rels[i]}}"; do
			c=0
			for p in "${pats[@]}"; do
				for a in "${(@s:|:)p}"; do
					if [[ $seg == *${a}* ]]; then
						(( c++ ))
						break
					fi
				done
			done
			(( c > best )) && best=c
		done
		scores+=("$best")
		(( best > top )) && top=best
	done
	reply=()
	for (( s = top; s >= 0; s-- )); do
		for (( i = 1; i <= $#scores; i++ )); do
			(( scores[i] == s )) && reply+=("${argv[i]}")
		done
	done
}

# _hop_decide <tier> <query> <approx> <M-row...> -> the verdict for rows M, which matched <query>.
# - Writes the _hop_res_* fields _hop_resolve declared, and reads its q, root, action, jump, under and opq.
# - Intermediate dirs come in as synthetic rows, one per strict ancestor of a match that is not already a match.
# - They are filtered by the same query, so only an ancestor the query itself names is ever offered.
# - X is the prefix-minimal set of matched dir targets, and J2 may jump to X when it is the only one.
_hop_decide() {
	emulate -L zsh
	setopt local_options extended_glob
	local tier=$1 eq=$2
	local -i approx=$3
	shift 3
	local -a M=("$@") R S srels anc inj X cand
	_hop_rels_of "${M[@]}"
	R=("${reply[@]}")

	if (( ! opq )) && [[ -n $root ]]; then
		_hop_ancestors "${under:+${under#"$root"/}}" "${R[@]}"
		anc=("${reply[@]}")
	fi
	local -A synby
	if (( $#anc )); then
		local syn a
		local -i i
		local _hop_gen_root=$root
		syn=$(for a in "${anc[@]}"; do
			_hop_row dir "${${a:h}/#%./-}" - - "${a:t}" "$root/$a" "$root/$a"
		done)
		local -a synrows=("${(@f)syn}")
		_hop_rels_of "${synrows[@]}"
		for (( i = 1; i <= $#synrows; i++ )); do
			synby[${reply[i]}]=${synrows[i]}
		done
		_hop_match "$eq" "$syn" && S=("${reply[@]}")
	fi
	if (( $#S )); then
		_hop_rels_of "${S[@]}"
		srels=("${reply[@]}")
	fi
	_hop_minimal ${(M)srels:#*/} ${(M)R:#*/}
	X=("${reply[@]}")

	# Injected rows keep their colour, and preview a top-level README rather than the bare dir.
	local x r d
	local -a readme f
	for x in "${X[@]}"; do
		(( ${srels[(Ie)$x]} )) || continue
		r=${synby[$x]}
		d=$root/${x%/}
		readme=("$d"/(#i)README*(.N))
		if (( $#readme )); then
			f=("${(@ps:\t:)r}")
			f[3]=${readme[1]}
			r=${(pj:\t:)f}
		fi
		inj+=("$r")
	done
	cand=("${inj[@]}" "${M[@]}")
	_hop_res_tier=$tier _hop_res_query=$eq
	_hop_res_n=$#cand _hop_res_m=$#M _hop_res_inj=$#inj

	_hop_res_verdict=pick
	if (( ! approx )) && [[ $jump != never ]]; then
		_hop_decide_jump
	fi
	[[ $_hop_res_verdict == jump ]] && return 0
	_hop_coherence "$eq" "${M[@]}"
	_hop_res_rows=("${inj[@]}" "${reply[@]}")
	return 0
}

# _hop_decide_jump -> the J1, J1b, J3, J0 and J2 rules, in that order, over _hop_decide's own locals.
# - J3 runs before J2, which is what keeps every jump the display-only matcher made: 0 lost in four sweeps.
# - Without it `disaster-recovery prod` moved from its one leaf to the env dir above it.
_hop_decide_jump() {
	emulate -L zsh
	setopt local_options extended_glob
	if (( $#cand == 1 )); then
		_hop_res_fields "${cand[1]}"
		_hop_res_verdict=jump _hop_res_rule=single _hop_res_target=${(pj:\t:)reply}
		return 0
	fi
	# J1b: one identity across M; under cd that is the dir, so files sharing one dir collapse.
	if (( ! $#inj )); then
		local -a ident
		if [[ $action == cd ]]; then
			_hop_dirs_of "${M[@]}"
			ident=("${(@u)reply}")
		else
			ident=("${(@u)R}")
		fi
		if (( $#ident == 1 )); then
			_hop_res_fields "${M[1]}"
			[[ $action == cd && ${reply[3]} != */ ]] && reply[3]=${reply[3]:h}/
			_hop_res_verdict=jump _hop_res_rule=onedir _hop_res_target=${(pj:\t:)reply}
			return 0
		fi
	fi
	# J3: whatever the display-only matcher hop shipped with jumped to, it still jumps to.
	# - Unless another match has a clipped column: its display only hid the words, so one display hit is not one target.
	# - `security vpc` had jumped into the prod vpc, because the staging scope showed as …urity-tooling-staging.
	if _hop_match "$eq" "${(F)M}" --nth=1 && (( $#reply == 1 )); then
		local hit=${reply[1]} m
		local -i clipped=0
		for m in "${M[@]}"; do
			[[ $m != "$hit" && ${m%%$'\t'*} == *…* ]] && clipped=1
		done
		if (( ! clipped )); then
			_hop_res_fields "$hit"
			_hop_res_verdict=jump _hop_res_rule=display _hop_res_target=${(pj:\t:)reply}
			return 0
		fi
	fi
	[[ $jump == unique ]] && return 0

	# J0, the workspace and repo levels only: one row's name is the whole query, so `configuration` skips its retired copies.
	# - Never in a repo, where a helm release, a tg unit and a service file can all share one name.
	if [[ -z $root && $tier == T1 ]] && (( ! opq )) && [[ $eq != *[[:space:]]* ]]; then
		local -a named
		local row
		for row in "${M[@]}"; do
			[[ ${(L)${${=${row%%$'\t'*}}[1]}} == "${(L)eq}" ]] && named+=("$row")
		done
		if (( $#named == 1 )); then
			_hop_res_fields "${named[1]}"
			_hop_res_verdict=jump _hop_res_rule=name _hop_res_target=${(pj:\t:)reply}
			# Said aloud, because the rows it skipped are ones the user may have meant.
			if (( $#M == 2 )); then
				_hop_res_note="hop: ${q} -> ${reply[3]} (exact name; 1 other contains it)"
			else
				_hop_res_note="hop: ${q} -> ${reply[3]} (exact name; $(( $#M - 1 )) others contain it)"
			fi
			return 0
		fi
	fi

	# J2: every match lies under one dir the query names on token boundaries, and no term is a kind word.
	(( $#X == 1 && ! opq )) && [[ -n $root ]] || return 0
	# An intermediate array, because inside (( )) a nested ${...:#pat} is joined, so ${#...} counted characters.
	local -a outside=("${srels[@]}" "${R[@]}")
	outside=(${outside:#${X[1]}*})
	(( $#outside == 0 )) || return 0
	local IFS=$' \t'
	local -a terms=(${=${(L)eq}})
	local t
	for t in "${terms[@]}"; do
		(( ${_HOP_ALL_KINDS[(Ie)$t]} )) && return 0
	done
	_hop_aligned "${X[1]}" "${terms[@]}" || return 0
	local row
	if (( ${srels[(Ie)${X[1]}]} )); then
		row=${inj[1]}
	else
		row=${M[${R[(ie)${X[1]}]}]}
	fi
	_hop_res_fields "$row"
	_hop_res_verdict=jump _hop_res_rule=dir _hop_res_target=${(pj:\t:)reply}
	_hop_res_note="hop: ${q} -> ${X[1]} (all ${#M} matches are under it)"
	[[ $tier == T2a ]] && _hop_res_note+=" (read as: ${eq})"
	return 0
}

# _hop_resolve <query> <rows-text> <root> <action> <jump> [under] -> sets the caller's _hop_res_* fields.
# - The caller declares them local, as _hop_run does for _hop_parse_result's fields, and _hop_run lists them.
# - verdict is jump, pick, none or empty; target is dir<TAB>preview<TAB>rel; rows are the candidates, best first.
# - query is what the picker should open with, and note is its first header line.
# - root is '' for the workspace and repo pickers, which turns off synthetic rows and J2 there.
# - under is the -c subtree, so an ancestor outside it is never offered.
# - A query holding ' ^ $ ! or | is the user's own fzf syntax, so it gets T1 alone, never a rewrite.
_hop_resolve() {
	emulate -L zsh
	setopt local_options extended_glob
	local q=$1 rows=$2 root=${3:-} action=${4:-cd} jump=${5:-auto} under=${6:-}
	local -F t0=0
	if [[ -n ${HOP_DEBUG:-} ]] && zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null; then
		t0=$EPOCHREALTIME
	fi
	_hop_res_verdict=none _hop_res_tier='' _hop_res_rule='' _hop_res_query=$q _hop_res_note='' _hop_res_target=''
	_hop_res_n=0 _hop_res_m=0 _hop_res_inj=0
	_hop_res_rows=()
	local -a reply all
	local REPLY
	all=("${(@f)rows}")
	all=(${all:#})

	if [[ -z ${q//[[:space:]]/} ]]; then
		_hop_res_verdict=empty _hop_res_query='' _hop_res_n=$#all
		if (( $#all == 1 )); then
			_hop_res_fields "${all[1]}"
			_hop_res_target=${(pj:\t:)reply}
		fi
		_hop_resolve_log "$q" "$t0"
		return 0
	fi

	local -i opq=0
	[[ $q == *[\'\^\$\!\|]* ]] && opq=1
	local -a terms
	terms=(${(s: :)${q//$'\t'/ }})

	if _hop_match "$q" "$rows"; then
		_hop_decide T1 "$q" 0 "${reply[@]}"
		_hop_resolve_log "$q" "$t0"
		return 0
	fi
	if (( opq )); then
		_hop_resolve_none
		_hop_resolve_log "$q" "$t0"
		return 0
	fi
	if (( $#all > _HOP_APPROX_MAX )); then
		_hop_resolve_none
		_hop_res_note="typo matching skipped above ${_HOP_APPROX_MAX} rows"
		_hop_resolve_log "$q" "$t0"
		return 0
	fi

	local -a _hop_vocab _hop_segs
	local -A _hop_vocab_set
	_hop_rels_of "${all[@]}"
	local -a rels=("${reply[@]}")
	_hop_vocab_build "${rels[@]}"

	local eq tried=''
	local -i approx wide
	for wide in 0 1; do
		_hop_rewrite "$q" "$wide" || continue
		approx=${reply[1]} eq=${reply[2]}
		[[ $eq != "$tried" ]] || continue
		tried=$eq
		_hop_match "$eq" "$rows" || continue
		if (( approx )); then
			_hop_decide T2 "$eq" 1 "${reply[@]}"
			_hop_res_note="no exact match for: ${q} (showing: ${eq})"
		else
			# T2a reorders and spreads the words, so every outcome says how it read them; J2 already did.
			_hop_decide T2a "$eq" 0 "${reply[@]}"
			if [[ $_hop_res_verdict == pick ]]; then
				_hop_res_note="no exact match for: ${q} (read as: ${eq})"
			elif [[ $_hop_res_rule != dir ]]; then
				_hop_res_note="hop: ${q} -> ${_hop_res_target##*$'\t'} (read as: ${eq})"
			fi
		fi
		_hop_resolve_log "$q" "$t0"
		return 0
	done
	if _hop_loose "$q"; then
		eq=$REPLY
		if _hop_match "$eq" "$rows"; then
			_hop_decide T3 "$eq" 1 "${reply[@]}"
			_hop_res_note="no exact match for: ${q} (showing: ${eq})"
			_hop_resolve_log "$q" "$t0"
			return 0
		fi
	fi

	# Relaxed: each word resolves alone, through whichever tier reads it, and the words nothing reads are dropped.
	if (( $#terms >= 2 )); then
		local -a keep drop eqs
		local t _hop_text=''
		_hop_text_build
		for t in "${terms[@]}"; do
			if _hop_term_eq "$t" "$rows"; then
				keep+=("$t") eqs+=("$REPLY")
			else
				drop+=("$t")
			fi
		done
		# The readings join whatever tier each came from, so `kps zzqx` keeps kps, which only T3 reads.
		eq=${(j: :)eqs}
		if (( $#keep )) && [[ $eq != "$q" && $eq != "$tried" ]] && _hop_match "$eq" "$rows"; then
			if (( $#drop )); then
				_hop_decide relaxed "$eq" 1 "${reply[@]}"
				_hop_res_note="ignored: ${(j: :)drop}"
			else
				_hop_decide T3 "$eq" 1 "${reply[@]}"
				_hop_res_note="no exact match for: ${q} (showing: ${eq})"
			fi
			_hop_resolve_log "$q" "$t0"
			return 0
		fi
		if (( $#keep >= 2 )) && _hop_all_but_one; then
			_hop_res_note="ignored: ${drop:+${(j: :)drop}, and }one of: ${(j:, :)keep}"
			_hop_resolve_log "$q" "$t0"
			return 0
		fi
	fi

	_hop_resolve_none
	_hop_resolve_log "$q" "$t0"
	return 0
}

# _hop_text_build -> _hop_text, the fields 1 and 4 of _hop_resolve's rows lowercased, or '' when zsh cannot stand in for fzf.
# - That is exactly the text fzf matches under --with-nth=1,4 and -i, so _hop_hits can search it instead of forking.
# - fzf folds Latin diacritics and zsh does not, so text holding anything but ASCII and hop's own … clip marker is refused.
_hop_text_build() {
	emulate -L zsh
	setopt local_options extended_glob
	local -a f1=("${(@)all%%$'\t'*}")
	_hop_text=${(L)${(F)${(@)f1//$'\e'\[[0-9;]#m/}}}$'\n'${(L)${(F)rels}}
	[[ ${_hop_text//…/} != *[^$'\x01'-$'\x7f']* ]] || _hop_text=''
}

# _hop_hits <eq> <rows-text> -> 0 when some row matches eq, answered in zsh whenever that is provably fzf's answer.
# - For one OR group of plain ASCII words, an --exact match is a substring search of _hop_text.
# - Anything else forks fzf: an AND of groups needs one row holding them all, and ' ^ $ ! \ are fzf syntax.
# - Measured: the relaxed tier forked 5 to 8 fzf processes, and a 4-word query took 122ms against a 100ms budget.
_hop_hits() {
	emulate -L zsh
	local e=${(L)1} a
	if [[ -n ${_hop_text:-} && ${e// | /} != *' '* && $e != *[^$'\x20'-$'\x7e']* && $e != *[\'\^\$\!\\]* ]]; then
		for a in "${(@s: | :)e}"; do
			[[ $_hop_text == *"$a"* ]] && return 0
		done
		return 1
	fi
	local -a reply
	_hop_match "$e" "$2"
}

# _hop_term_eq <term> <rows-text> -> 0 with REPLY the term as the first tier that reads it does: T1, T2 narrow, T2 wide, T3.
_hop_term_eq() {
	emulate -L zsh
	local t=$1 rows=$2
	local -a reply
	local -i wide
	REPLY=$t
	_hop_hits "$t" "$rows" && return 0
	for wide in 0 1; do
		_hop_rewrite "$t" "$wide" || continue
		REPLY=${reply[2]}
		_hop_hits "$REPLY" "$rows" && return 0
	done
	_hop_loose "$t" && _hop_hits "$REPLY" "$rows" && return 0
	REPLY=''
	return 1
}

# _hop_all_but_one -> 0 when some rows match every kept word but one, and they are decided as a relaxed pick.
# - Each word matches alone and no row matches all of them, so one word at a time is left out.
# - The picker opens on every pair OR-ed, `a | b  a | c  b | c`, which is what keeps exactly the rows missing one word.
# - The smallest set comes first, since the word left out of it was the one the rest least agree with.
# - It reads _hop_resolve's keep, eqs and rows, and needs every reading to be one OR group for the pairs to say that.
_hop_all_but_one() {
	emulate -L zsh
	local e
	for e in "${eqs[@]}"; do
		[[ ${e// | /} != *' '* ]] || return 1
	done
	local -a got order out pairs rest
	local -A seen
	local -i i j
	local r k
	for (( i = 1; i <= $#eqs; i++ )); do
		rest=("${(@)eqs[1,i-1]}" "${(@)eqs[i+1,-1]}")
		_hop_match "${(j: :)rest}" "$rows" || continue
		got[i]=${(F)reply}
		order+=("${(l:8::0:)#reply}:$i")
	done
	(( $#order )) || return 1
	for k in "${(@o)order}"; do
		for r in "${(@f)got[${k#*:}]}"; do
			(( ${+seen[$r]} )) && continue
			seen[$r]=1
			out+=("$r")
		done
	done
	for (( i = 1; i < $#eqs; i++ )); do
		for (( j = i + 1; j <= $#eqs; j++ )); do
			pairs+=("${eqs[i]} | ${eqs[j]}")
		done
	done
	# No ancestor is injected: one that holds a single word, as every acct-*-prod/ does for prod, would bury the order above.
	local -i opq=1
	_hop_decide relaxed "${(j: :)pairs}" 1 "${out[@]}"
}

# _hop_res_rank -> REPLY ranks the resolve by how close it came: T1 5, T2a 4, T2 or T3 3, relaxed 2, nothing 1.
_hop_res_rank() {
	emulate -L zsh
	case $_hop_res_tier in
		(T0|T1) REPLY=5 ;;
		(T2a) REPLY=4 ;;
		(T2|T3) REPLY=3 ;;
		(relaxed) REPLY=2 ;;
		(*) REPLY=1 ;;
	esac
}

# _hop_resolve_none -> T4: nothing close, so the picker opens on the query as typed, editable, with zero rows.
_hop_resolve_none() {
	emulate -L zsh
	_hop_res_verdict=none _hop_res_tier=T4 _hop_res_query=$q
	_hop_res_note="nothing close to: ${q} (esc clears)"
}

# _hop_resolve_log <query> <start> -> the one HOP_DEBUG line every resolve writes.
_hop_resolve_log() {
	emulate -L zsh
	[[ -n ${HOP_DEBUG:-} ]] || return 0
	local -F t0=${2:-0}
	local ms=-
	(( t0 > 0 )) && printf -v ms '%.1f' $(( (EPOCHREALTIME - t0) * 1000 ))
	_hop_dbg "resolve tier=${_hop_res_tier:--} rule=${_hop_res_rule:--} verdict=${_hop_res_verdict} n=${_hop_res_n} inj=${_hop_res_inj} q=${1} target=${${_hop_res_target##*$'\t'}:--} ms=${ms}"
}

# _hop_res_input <rows-text> -> the picker's stdin: the candidates first, then every other row in MRU order.
# - fzf printed the candidates without their SGR, so each is mapped back to its original, coloured row.
# - The rest stay, so that backspacing in the picker widens the list instead of emptying it.
_hop_res_input() {
	emulate -L zsh
	setopt local_options extended_glob
	local -a all=("${(@f)1}") plain front
	all=(${all:#})
	plain=("${(@)all//$'\e'\[[0-9;]#m/}")
	local -A orig
	orig=("${(@)plain:^all}")
	local r
	for r in "${_hop_res_rows[@]}"; do
		front+=("${orig[$r]:-$r}")
	done
	print -rl -- "${front[@]}" "${(@)all:|front}"
}

# _hop_res_jump -> act on a JUMP verdict: the resolver's note, if any, then Enter on the target.
_hop_res_jump() {
	emulate -L zsh
	[[ -n $_hop_res_note ]] && print -ru2 -- "$_hop_res_note"
	local -a f=("${(@ps:\t:)_hop_res_target}")
	# An empty key is plain Enter, which applies the call's mode; see _hop_act_enter.
	_hop_dispatch '' "${f[1]}" "${f[2]}" "${f[3]}"
}

# _hop_headless_report <query> <label> -> with no terminal, act on a resolve that needs no human, or explain and fail.
# - fzf reads keys from /dev/tty, so with none the picker would block forever; see _hop_tty_ok.
# - An EMPTY query over exactly one row auto-accepts, which is what --select-1 does with a terminal.
# - Nothing matched and N matched get DIFFERENT messages, because the next move differs.
# - A typo wants correcting; a broad query wants narrowing, and one string cannot say both.
# - The count and the best rels are what end a bug hunt, so a pick names both.
_hop_headless_report() {
	emulate -L zsh
	local query=${1:-} label=${2:-}
	_hop_dbg "headless label=${label} rows=${_hop_res_n} query=${query}"
	if [[ $_hop_res_verdict == empty ]] && (( _hop_res_n == 1 )) && [[ ${_hop_jump:-${HOP_JUMP:-auto}} != never ]]; then
		_hop_res_note=''
		_hop_res_jump
		return $?
	fi
	if [[ $_hop_res_verdict == pick && $_hop_res_tier != (T0|T1) ]]; then
		if [[ $_hop_res_tier == relaxed ]]; then
			print -ru2 -- "hop: no exact match for: ${query} (${_hop_res_note})"
		else
			print -ru2 -- "hop: no exact match for: ${query} (read as: ${_hop_res_query})"
		fi
	fi
	print -ru2 -- 'hop: no terminal available, so the picker cannot run (/dev/tty could not be opened).'
	if [[ $_hop_res_verdict == none ]]; then
		print -ru2 -- "hop: nothing matched${query:+ the query: $query}, so there was nothing to jump to."
		# The row cap is the one reason a typo goes uncorrected, and the picker header is not there to say so.
		[[ -n $_hop_res_note && $_hop_res_note != 'nothing close to: '* ]] && print -ru2 -- "hop: ${_hop_res_note}, so a misspelt word is not corrected; -k narrows the kinds."
		return 1
	fi
	local unit=targets
	(( _hop_res_n == 1 )) && unit=target
	print -ru2 -- "hop: ${_hop_res_n} ${unit} matched${query:+ the query: $query}, and picking one needs a terminal."
	if (( $#_hop_res_rows )); then
		local -a reply
		_hop_rels_of "${(@)_hop_res_rows[1,3]}"
		print -ru2 -- "hop: best matches: ${(j:, :)reply}"
	fi
	# Narrowing is the advice only where a narrower query can jump.
	if [[ ${_hop_jump:-${HOP_JUMP:-auto}} == never ]]; then
		print -ru2 -- 'hop: -p and HOP_JUMP=never always open the picker, and the picker needs a terminal.'
	elif [[ $_hop_res_tier == relaxed ]]; then
		print -ru2 -- "hop: drop or fix: ${_hop_res_note#ignored: }"
	elif [[ $_hop_res_tier == (T2|T3) ]]; then
		print -ru2 -- 'hop: fix the spelling, since hop never jumps on a corrected query.'
	elif [[ $_hop_res_tier == T0 ]]; then
		print -ru2 -- 'hop: put the repo name in front of the path, or give the whole path from ~/, so it names one of them.'
	else
		print -ru2 -- 'hop: narrow the query until exactly one target matches and hop will jump straight to it.'
	fi
	return 1
}
