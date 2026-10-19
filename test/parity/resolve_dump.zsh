#!/usr/bin/env zsh
# resolve_dump.zsh <hop-dir> <root> <out-dir> <jump> [repo-dir]: eval_real.zsh's five query sets, resolved by zsh hop.
# - Writes <set>.q, one query per line, so the Go hop reads the identical list, and <set>.zsh, hx_runner's line per query.
# - The five sets are built exactly as tests/eval_real.zsh builds them; that file is copied from, never edited.
# - Three more stress the approximate tiers: corpus, typo (letters 2 and 3 of each name swapped), and relaxed (name plus nonsense).
emulate -L zsh
setopt extended_glob
local hopdir=$1 root=$2 out=$3 jump=$4 repo=${5:-$1}
export HOP_HISTFILE=/dev/null
source "$hopdir/hop.zsh" || exit 3
source "$repo/testdata/resolve_runner.zsh" || exit 3
builtin cd -q -- "$root" || exit 2

local -a kinds=(${=${HOP_DEFAULT_KINDS//,/ }}) all names pref3 scopeenv nameenv words w reply
local targets r n s tab=$'\t'
targets=$(_hop_rows "$root" '' "${kinds[@]}") || exit 2
all=("${(@f)targets}")
all=(${all:#})
local IFS=$' \t\n'
for r in "${(@)all//$'\e'\[[0-9;]#m/}"; do
	w=(${=r%%$'\t'*})
	names+=("${w[1]}")
	[[ -n ${w[4]:-} && ${w[4]} != - ]] || continue
	nameenv+=("${w[1]} ${w[4]}")
	[[ ${w[3]} != - ]] && scopeenv+=("${w[3]} ${w[4]}")
done
names=("${(@ou)names}")
for n in "${names[@]}"; do
	pref3+=("${n[1,3]}")
done
pref3=("${(@ou)pref3}")
scopeenv=("${(@ou)scopeenv}")
nameenv=("${(@ou)nameenv}")
for n in "${(@f)$(<"$hopdir/tests/fixtures/dictionary.txt")}"; do
	[[ -n $n ]] || continue
	_hop_match "$n" "$targets" || words+=("$n")
done

local -a corpus typo relaxed
corpus=("${(@f)$(<"$repo/test/parity/corpus/queries.txt")}")
corpus=(${corpus:#})
local -i i=0
for n in "${names[@]}"; do
	(( ${#n} >= 5 )) && typo+=("${n[1]}${n[3]}${n[2]}${n[4,-1]}")
	relaxed+=("${n} ${words[i++ % $#words + 1]}")
done

local -A sets=(names names pref3 pref3 scope+env scopeenv name+env nameenv nonsense words corpus corpus typo typo relaxed relaxed)
for s in names pref3 scope+env name+env nonsense corpus typo relaxed; do
	print -rl -- "${(@P)sets[$s]}" > "$out/$s.q"
	print -rl -- "${(@)${(@P)sets[$s]}/%/${tab}.${tab}cd${tab}${jump}${tab}-}" > "$out/$s.cases"
	hx_runner "$root" "$out/$s.cases" > "$out/$s.zsh"
done
