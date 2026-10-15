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
# - Only a word holding a / or starting with ~ qualifies, so a plain name always goes to the matcher.
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
	[[ $w == */* || $w == '~'* ]] || return 1
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
	local a f base rest hit=''
	local -a g
	for (( i = 1; i <= $#anchors; i++ )); do
		a=${anchors[i]:a}
		f="${a%/}/${rests[i]}"
		f=${f:a}
		# ../ can climb above the anchor, so the literal part is what the typed path still shares with it.
		base=$a
		while [[ $base != / && $f != "$base" && $f != "$base"/* ]]; do
			base=${base:h}
		done
		rest=${f#"$base"}
		rest=${rest#/}
		if [[ -z $rest ]]; then
			[[ -e $f ]] || continue
			hit=$f
			break
		fi
		g=("${base%/}"/(#i)${rest}(N))
		if (( ${g[(Ie)$f]} )); then
			hit=$f
		elif (( $#g == 1 )); then
			hit=${g[1]}
		else
			continue
		fi
		break
	done
	[[ -n $hit ]] || return 1

	local REPLY _hop_gen_root=${root:+${root:A}}
	if [[ -d $hit ]]; then
		_hop_rel "${hit:A}" "${hit:A}"
		reply=("$hit" "$hit" "$REPLY")
	else
		_hop_rel "${${hit:A}:h}" "${hit:A}" f
		reply=("${hit:h}" "$hit" "$REPLY")
	fi
	return 0
}

# _hop_vocab_build <rel...> -> _hop_vocab and _hop_segs, the words T2 and T3 may rewrite a query into.
# - Both are declared by _hop_resolve, so building them once serves every tier and every relaxed term.
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
# - A token no word contains gets typo fixes: zsh's approximate glob, 1 error, or 2 from 8 chars, transposition counted once.
# - A short env word with no row holding it reads as its long form first; see _HOP_ENV_WORDS.
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

# _hop_decide_jump -> the J1, J1b, J3 and J2 rules, in that order, over _hop_decide's own locals.
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
	if _hop_match "$eq" "${(F)M}" --nth=1 && (( $#reply == 1 )); then
		_hop_res_fields "${reply[1]}"
		_hop_res_verdict=jump _hop_res_rule=display _hop_res_target=${(pj:\t:)reply}
		return 0
	fi
	[[ $jump == unique ]] && return 0

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
	_hop_vocab_build "${reply[@]}"

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
			_hop_decide T2a "$eq" 0 "${reply[@]}"
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

	# Relaxed: drop the words that resolve to nothing, but only when some word survives.
	if (( $#terms >= 2 )); then
		local -a keep drop
		local t
		for t in "${terms[@]}"; do
			if _hop_match "$t" "$rows" \
				|| { _hop_rewrite "$t" && _hop_match "${reply[2]}" "$rows" } \
				|| { _hop_rewrite "$t" 1 && _hop_match "${reply[2]}" "$rows" } \
				|| { _hop_loose "$t" && _hop_match "$REPLY" "$rows" }; then
				keep+=("$t")
			else
				drop+=("$t")
			fi
		done
		if (( $#keep && $#drop )); then
			eq="${(j: :)keep}"
			if _hop_match "$eq" "$rows" \
				|| { _hop_rewrite "$eq" && eq=${reply[2]} && _hop_match "$eq" "$rows" } \
				|| { _hop_rewrite "${(j: :)keep}" 1 && eq=${reply[2]} && _hop_match "$eq" "$rows" }; then
				_hop_decide relaxed "$eq" 1 "${reply[@]}"
				_hop_res_note="ignored: ${(j: :)drop}"
				_hop_resolve_log "$q" "$t0"
				return 0
			fi
		fi
	fi

	_hop_resolve_none
	_hop_resolve_log "$q" "$t0"
	return 0
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

# _hop_res_jump -> act on a JUMP verdict: the J2 note, if any, then Enter on the target.
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
	if [[ $_hop_res_verdict == pick && $_hop_res_tier != T1 ]]; then
		if [[ $_hop_res_tier == relaxed ]]; then
			print -ru2 -- "hop: no exact match for: ${query} (${_hop_res_note})"
		else
			print -ru2 -- "hop: no exact match for: ${query} (read as: ${_hop_res_query})"
		fi
	fi
	print -ru2 -- 'hop: no terminal available, so the picker cannot run (/dev/tty could not be opened).'
	if [[ $_hop_res_verdict == none ]]; then
		print -ru2 -- "hop: nothing matched${query:+ the query: $query}, so there was nothing to jump to."
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
	print -ru2 -- 'hop: narrow the query until exactly one target matches and hop will jump straight to it.'
	return 1
}
