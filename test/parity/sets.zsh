#!/usr/bin/env zsh
# sets.zsh <hop-dir> <root> <out-dir> [stress]: eval_real.zsh's five query sets, built by the hop under test from its own rows.
# - Writes <set>.q, one query per line, for names, pref3, scope+env, name+env and nonsense.
# - Built as <hop-dir>/tests/eval_real.zsh builds them, copied from it, never edited.
# - The sets depend on the hop: 0.3.0 widened the name column, so fewer names arrive clipped with `…`.
# - stress adds resolve_dump.zsh's three: corpus, typo (letters 2 and 3 of each name swapped), and relaxed (name plus nonsense).
emulate -L zsh
setopt extended_glob
local hopdir=${1:A} root=$2 out=${3:A} stress=${4:-} here=${0:A:h}
export HOP_HISTFILE=/dev/null
source "$hopdir/hop.zsh" || exit 3
builtin cd -q -- "$root" || exit 2

local -a kinds=(${=${HOP_DEFAULT_KINDS//,/ }}) all names pref3 scopeenv nameenv words w reply
local targets r n
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

print -rl -- "${names[@]}" >"$out/names.q"
print -rl -- "${pref3[@]}" >"$out/pref3.q"
print -rl -- "${scopeenv[@]}" >"$out/scope+env.q"
print -rl -- "${nameenv[@]}" >"$out/name+env.q"
print -rl -- "${words[@]}" >"$out/nonsense.q"
[[ $stress == stress ]] || exit 0
local -a typo relaxed
local -i i=0
for n in "${names[@]}"; do
	(( ${#n} >= 5 )) && typo+=("${n[1]}${n[3]}${n[2]}${n[4,-1]}")
	relaxed+=("${n} ${words[i++ % $#words + 1]}")
done
cp "$here/corpus/queries.txt" "$out/corpus.q"
print -rl -- "${typo[@]}" >"$out/typo.q"
print -rl -- "${relaxed[@]}" >"$out/relaxed.q"
