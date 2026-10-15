#!/usr/bin/env zsh
# suite_match: the resolver in lib/match.zsh, driven over match_fixture with the real fzf in --filter mode only.
# - The table runs inside ONE probe child, which prints one TSV line per case, so 60 cases cost one shell.
# - A picker is never drawn: the picker cases use stub_fzf_select, and every --filter goes to the real fzf.
# - The floor CI legs run this whole file on fzf 0.60.3 and 0.67.0, with the same expectations.

stub_bin

# mt_slurp <file> -> its contents, or nothing when unreadable; `zsh -n` evaluates a top-level $(<file).
mt_slurp() {
	emulate -L zsh
	[[ -r $1 ]] && print -r -- "$(<"$1")"
	return 0
}

if [[ -z $IT_REAL_FZF ]]; then
	skip_cap 'the resolver against the real fzf' 'fzf is not installed'
	return 0
fi

typeset -g MT_REPO MT_WORK MT_CFG
match_fixture || return 1
MT_REPO=$REPLY
MT_CFG=$HOP_FIX_CONFIG
fixture_tmpdir matchwork || return 1
MT_WORK=$REPLY

# ---------------------------------------------------------------------------
# The table runner, sourced inside the probe child.
# ---------------------------------------------------------------------------
# A case is five TAB fields: query, cwd relative to the repo, action, jump mode, and `c` for -c or `-`.
# - Each output line is the case followed by verdict, tier, rule, target dir, preview and rel, the count,
#   the injected count, the first four candidate rels, the picker query, the note, and parity.
# - T0 runs first exactly as hop() runs it: one word, and never under jump=never.
# - Parity is the claim that a pick's matches are exactly what `fzf --filter <picker query>` keeps, as sets.
cat > "$MT_WORK/runner.zsh" <<'EOF'
mt_runner() {
	emulate -L zsh
	setopt local_options extended_glob
	local root=$1 cases=$2 rowsout=$3 tab=$'\t'
	builtin cd -q -- "$root" || return 96
	local -a kinds=(${=${HOP_DEFAULT_KINDS//,/ }})
	local all
	all=$(_hop_generate "$root" "${kinds[@]}")
	all=$(_hop_rank "$all")
	print -r -- "$all" > "$rowsout"
	local _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
	local -i _hop_res_n _hop_res_m _hop_res_inj
	local -a _hop_res_rows reply f w rels mset fset
	local line q cwd action jump under rows udir parity tdir tprev trel
	for line in "${(@f)$(<"$cases")}"; do
		f=("${(@ps:\t:)line}")
		q=${f[1]} cwd=${f[2]} action=${f[3]} jump=${f[4]} under=${f[5]}
		if ! builtin cd -q -- "$root/$cwd"; then
			print -r -- "${line}${tab}cd-failed"
			continue
		fi
		rows=$all udir=''
		if [[ $under == c ]]; then
			udir=${PWD:A}
			_hop_filter_under "$udir" "${(@f)all}"
			rows=${(F)reply}
		fi
		w=(${=q})
		if [[ $jump != never ]] && (( $#w == 1 )) && _hop_literal_target "$q" "$root"; then
			print -r -- "${line}${tab}jump${tab}T0${tab}path${tab}${reply[1]}${tab}${reply[2]}${tab}${reply[3]}${tab}1${tab}0${tab}${tab}${tab}${tab}-"
			continue
		fi
		_hop_resolve "$q" "$rows" "$root" "$action" "$jump" "$udir"
		tdir='' tprev='' trel=''
		if [[ -n $_hop_res_target ]]; then
			f=("${(@ps:\t:)_hop_res_target}")
			tdir=${f[1]} tprev=${f[2]} trel=${f[3]}
		fi
		rels=()
		if (( $#_hop_res_rows )); then
			_hop_rels_of "${(@)_hop_res_rows[1,4]}"
			rels=("${reply[@]}")
		fi
		parity=-
		if [[ $_hop_res_verdict == pick ]]; then
			mset=("${(@o)${(@)_hop_res_rows[_hop_res_inj+1,-1]}}")
			fset=("${(@f)$(print -r -- "$rows" | fzf --filter="$_hop_res_query" "${_HOP_MATCHER_FLAGS[@]}")}")
			fset=(${fset:#})
			fset=("${(@o)fset}")
			parity=bad
			[[ "${(F)mset}" == "${(F)fset}" ]] && parity=ok
		fi
		print -r -- "${line}${tab}${_hop_res_verdict}${tab}${_hop_res_tier}${tab}${_hop_res_rule}${tab}${tdir}${tab}${tprev}${tab}${trel}${tab}${_hop_res_n}${tab}${_hop_res_inj}${tab}${(j:,:)rels}${tab}${_hop_res_query}${tab}${_hop_res_note}${tab}${parity}"
	done
}
EOF

typeset -a MT_CASES=()
# mt_case <query> [cwd] [action] [jump] [c] -> add one case to the table, defaults filled in.
mt_case() {
	emulate -L zsh
	MT_CASES+=("${1}"$'\t'"${2:-.}"$'\t'"${3:-cd}"$'\t'"${4:-auto}"$'\t'"${5:--}")
}

typeset -a MT_NONSENSE=("${(@f)$(mt_slurp "$HOP_HOME/tests/fixtures/nonsense.txt")}")
MT_NONSENSE=(${MT_NONSENSE:#})

typeset q
for q in \
	terraform/acct-security-tooling-prod Terraform/ACCT-Security-Tooling-Prod \
	terraform/acct-security-tooling-prod/env-prod/us-east-1/vpc kubernetes/services/monitoring/grafana.yaml \
	./sandbox/abg terraform/nope/x acct-security-tooling-prod/env-prod curity-tooling-prod/env-pr \
	security-tooling-prod Security-Tooling-Prod security_tooling_prod 'acct sec prod' terraform/account-security terraform/acount-security \
	securty-tooling-prod secuirty-tooling-prod routemaxter rotuemaster routemastr routemaster-prod externaldns securitytoolingprod kps kpstack kubeprom \
	vpc Vpc 'TG vpc' tg mesos helm kub kubernetes values 'eks security' 'vpc security !staging' '^vpc' \
	'acct sec prd' stg 'trust prod' 'data prod' 'active infrastructure' monitoring/grafana abg zzqx zzzz 'vpc zzqx' thanos \
	'kps zzqx' 'routemaxter kps zzqx' 'routemaster dev' \
	"${MT_NONSENSE[@]}"; do
	mt_case "$q"
done
mt_case ../abg sandbox/alpha-beta-gamma
mt_case /mesos terraform
mt_case modules/ terraform
mt_case mesos/services terraform
mt_case monitoring/grafana . open
mt_case security-tooling-prod . cd unique
mt_case 'eks security' . cd unique
mt_case 'eks security' . cd never
mt_case terraform/acct-security-tooling-prod . cd never
mt_case vpc terraform/acct-infrastructure cd auto c
mt_case infrastructure terraform/acct-infrastructure/env-prod cd auto c
mt_case infrastructure terraform/acct-infrastructure/env-prod
mt_case 'acct-l[a]b*#/env-prod'
mt_case env-prod 'terraform/acct-l[a]b*#' cd auto c

print -rl -- "${MT_CASES[@]}" > "$MT_WORK/cases"
export MT_REPO MT_WORK
typeset MT_OUT
MT_OUT=$(hop_probe "source \"\$MT_WORK/runner.zsh\"
mt_runner \"\$MT_REPO\" \"\$MT_WORK/cases\" \"\$MT_WORK/rows\"" 2>"$MT_WORK/err")

typeset -A MT_RES
typeset line
for line in "${(@f)MT_OUT}"; do
	[[ -n $line ]] || continue
	MT_RES[${(pj:\t:)${(@)${(@ps:\t:)line}[1,5]}}]=$line
done

t 'the table runner answered every case, silently'
assert_eq ${#MT_CASES} ${#MT_RES} "the probe printed $(( ${#MT_RES} )) of ${#MT_CASES} cases; stderr: $(mt_slurp "$MT_WORK/err")"
assert_empty "$(mt_slurp "$MT_WORK/err")" 'a resolve wrote to stderr'

# mt_get <query> [cwd] [action] [jump] [c] -> reply is that case's output fields; 1 when it never ran.
# - Fields: 6 verdict, 7 tier, 8 rule, 9 dir, 10 preview, 11 rel, 12 n, 13 inj, 14 rels, 15 query, 16 note, 17 parity.
mt_get() {
	emulate -L zsh
	local key="${1}"$'\t'"${2:-.}"$'\t'"${3:-cd}"$'\t'"${4:-auto}"$'\t'"${5:--}"
	reply=("${(@ps:\t:)${MT_RES[$key]:-}}")
	[[ -n ${MT_RES[$key]:-} ]]
}

# mt_name <query> [cwd] [action] [jump] [c] -> REPLY is the case's test name, naming only what differs from the default.
mt_name() {
	emulate -L zsh
	REPLY="resolve: ${1}"
	[[ -n ${2:-} && $2 != . ]] && REPLY+=" from ${2}"
	[[ -n ${3:-} && $3 != cd ]] && REPLY+=" as ${3}"
	[[ -n ${4:-} && $4 != auto ]] && REPLY+=" with HOP_JUMP=${4}"
	[[ ${5:-} == c ]] && REPLY+=' with -c'
	return 0
}

# mt_jump <verdict-tier-rule> <rel> <query> [cwd] [action] [jump] [c] -> the case jumped by that rule to that rel.
mt_jump() {
	emulate -L zsh
	local want=$1 rel=$2
	shift 2
	local REPLY
	mt_name "$@"
	t "$REPLY"
	local -a reply
	if ! mt_get "$@"; then
		assert_eq 'ran' 'missing' 'the table runner never printed this case'
		return 0
	fi
	assert_eq "$want" "${reply[6]} ${reply[7]} ${reply[8]}"
	assert_eq "$rel" "${reply[11]}" 'the jump landed somewhere else'
}

# mt_pick <tier> <n|-> <first-rel|-> <query> [cwd] [action] [jump] [c] -> the case opened the picker.
mt_pick() {
	emulate -L zsh
	local tier=$1 n=$2 first=$3
	shift 3
	local REPLY
	mt_name "$@"
	t "$REPLY"
	local -a reply
	if ! mt_get "$@"; then
		assert_eq 'ran' 'missing' 'the table runner never printed this case'
		return 0
	fi
	assert_eq "pick ${tier}" "${reply[6]} ${reply[7]}"
	[[ $n == - ]] || assert_eq "$n" "${reply[12]}" 'the candidate count changed'
	[[ $first == - ]] || assert_eq "$first" "${${reply[14]}%%,*}" 'the best row changed'
	assert_eq ok "${reply[17]}" "the candidates are not exactly fzf's own rows for: ${reply[15]}"
}

typeset SP=terraform/acct-security-tooling-prod
typeset IP=terraform/acct-infrastructure/env-prod/us-east-1

# ---------------------------------------------------------------------------
# T0: a literal path, before any matching.
# ---------------------------------------------------------------------------
mt_jump 'jump T0 path' "$SP/" terraform/acct-security-tooling-prod
mt_jump 'jump T0 path' "$SP/" Terraform/ACCT-Security-Tooling-Prod
mt_get Terraform/ACCT-Security-Tooling-Prod
assert_eq "$MT_REPO/$SP" "${reply[9]}" 'the cd target must be spelled the way the disk spells it'
mt_jump 'jump T0 path' "$SP/env-prod/us-east-1/vpc/" terraform/acct-security-tooling-prod/env-prod/us-east-1/vpc
mt_jump 'jump T0 path' kubernetes/services/monitoring/grafana.yaml kubernetes/services/monitoring/grafana.yaml
mt_get kubernetes/services/monitoring/grafana.yaml
assert_eq "$MT_REPO/kubernetes/services/monitoring" "${reply[9]}" 'a file target cds to its parent'
assert_eq "$MT_REPO/kubernetes/services/monitoring/grafana.yaml" "${reply[10]}" 'and previews the file itself'
mt_jump 'jump T0 path' sandbox/abg/ ./sandbox/abg
mt_jump 'jump T0 path' sandbox/abg/ ../abg sandbox/alpha-beta-gamma
mt_jump 'jump T0 path' mesos/ /mesos terraform
mt_jump 'jump T0 path' terraform/modules/ modules/ terraform
mt_get modules/ terraform
assert_eq "$MT_REPO/terraform/modules" "${reply[9]}" '$PWD comes first, so the subtree beats the root-level modules/'
mt_jump 'jump T0 path' mesos/services/ mesos/services terraform

t 'resolve: terraform/nope/x falls through to the matcher'
mt_get terraform/nope/x
assert_ne T0 "${reply[7]}" 'a path that does not exist is not a literal target'
assert_eq none "${reply[6]}"

t 'resolve: a literal path under HOP_JUMP=never opens the picker instead'
mt_get terraform/acct-security-tooling-prod . cd never
assert_eq pick "${reply[6]}" 'never means never, even for a path'

# ---------------------------------------------------------------------------
# T1, and the jump rules.
# ---------------------------------------------------------------------------
mt_jump 'jump T1 dir' "$SP/env-prod/" acct-security-tooling-prod/env-prod
mt_pick T1 - "$SP/env-prod/" curity-tooling-prod/env-pr
mt_jump 'jump T1 dir' "$SP/" security-tooling-prod
mt_get security-tooling-prod
assert_eq "hop: security-tooling-prod -> $SP/ (all 3 matches are under it)" "${reply[16]}" 'J2 announces itself on stderr'
mt_jump 'jump T1 dir' "$SP/" Security-Tooling-Prod
mt_jump 'jump T2a dir' "$SP/" security_tooling_prod
mt_get security_tooling_prod
assert_contains "${reply[16]}" '(read as: security tooling prod)' 'a rewritten jump says what it read'

mt_pick T1 7 "$SP/" 'acct sec prod'
t 'resolve: acct sec prod puts the account dir first, then its own units'
mt_get 'acct sec prod'
assert_eq 1 "${reply[13]}" 'the account dir is the one injected ancestor'
typeset -a MT_TOP=("${(@s:,:)reply[14]}")
assert_eq 4 ${#MT_TOP} 'the runner reports the first four rows'
assert_eq 0 ${#${(@)MT_TOP[2,4]:#$SP/*}} "rows 2-4 must be under the account dir: ${(j:, :)MT_TOP}"

mt_pick T2 7 "$SP/" terraform/account-security
mt_get terraform/account-security
assert_eq 'terraform account | acct security' "${reply[15]}" 'the picker opens on the rewrite, which is what the rows matched'
assert_eq 'terraform/acct-security-tooling-staging/' "${${reply[14]#*,}%%,*}" 'row 2 is the staging account dir'
assert_contains "${reply[16]}" 'no exact match for: terraform/account-security' 'the header says the query was rewritten'
mt_pick T2 7 "$SP/" terraform/acount-security
mt_get terraform/acount-security
assert_eq 'terraform account | acct security' "${reply[15]}" 'a typo fix is abbreviated too, so acount reaches acct through account'

typeset w
for w in securty-tooling-prod secuirty-tooling-prod; do
	mt_pick T2 4 "$SP/" "$w"
	mt_get "$w"
	assert_eq 'security tooling prod' "${reply[15]}"
done
for w in routemaxter rotuemaster routemastr; do
	mt_pick T2 2 - "$w"
	mt_get "$w"
	assert_eq routemaster "${reply[15]}" 'typo first, abbreviation only when there is no typo fix'
done
mt_jump 'jump T2a single' "$IP/routemaster/" routemaster-prod
mt_get routemaster-prod
assert_eq 'routemaster prod' "${reply[15]}" 'a word the rows already hold is never abbreviated, so raster-catalogue is not offered'
# A token run together from vocabulary words is read as those words, and still only offered.
mt_pick T2 2 kubernetes/values/external-dns/ externaldns
mt_get externaldns
assert_eq 'external dns' "${reply[15]}"
mt_pick T2 4 "$SP/" securitytoolingprod
mt_get securitytoolingprod
assert_eq 'security tooling prod' "${reply[15]}" 'three words run together split into three terms'
# An env word shortened past what a typo fix reaches reads as its long form, and only opens the picker.
mt_pick T2 7 "$SP/" 'acct sec prd'
mt_get 'acct sec prd'
assert_eq 'acct sec prod' "${reply[15]}"
mt_pick T2 - - stg
mt_get stg
assert_eq staging "${reply[15]}" 'stg is four letters short of staging, so only the env word map reaches it'
for w in kps kpstack kubeprom; do
	mt_pick T3 2 kubernetes/values/kube-prometheus-stack/ "$w"
done

mt_pick T1 5 - vpc
mt_pick T1 5 - Vpc
mt_pick T1 5 - 'TG vpc'
for w in tg mesos helm; do
	mt_pick T1 - - "$w"
done
mt_pick T1 - - kub
mt_jump 'jump T1 dir' kubernetes/ kubernetes
mt_jump 'jump T1 dir' kubernetes/values/ values
mt_jump 'jump T1 single' "$SP/env-prod/us-east-1/eks/" 'eks security'
mt_jump 'jump T1 single' "$SP/env-prod/us-east-1/vpc/" 'vpc security !staging'
mt_pick T1 5 - '^vpc'
mt_get '^vpc'
assert_eq 0 "${reply[13]}" 'an operator query is the user'"'"'s own fzf syntax, so nothing is synthesised'
mt_jump 'jump T1 display' "$IP/trust/" 'trust prod'
mt_pick T1 - - 'data prod'
mt_pick T1 2 - 'active infrastructure'
mt_jump 'jump T1 onedir' kubernetes/services/monitoring/ monitoring/grafana
mt_pick T1 2 - monitoring/grafana . open
mt_jump 'jump T1 single' sandbox/abg/ abg

t 'resolve: abg is exact-unique, and only because of --exact'
typeset -a MT_MF=("${(@f)$(hop_probe 'print -rl -- "${_HOP_MATCHER_FLAGS[@]}"')}")
typeset -i MT_FUZZY
MT_FUZZY=$("$IT_REAL_FZF" --filter=abg "${MT_MF[@]}" --no-exact < "$MT_WORK/rows" | grep -c .)
assert_eq 1 $(( MT_FUZZY > 1 )) "fuzzy must match more than the one exact row, got ${MT_FUZZY}"

for w in zzqx zzzz; do
	t "resolve: ${w}"
	mt_get "$w"
	assert_eq 'none T4' "${reply[6]} ${reply[7]}"
	assert_eq "nothing close to: ${w} (esc clears)" "${reply[16]}"
done
mt_pick relaxed 5 - 'vpc zzqx'
mt_get 'vpc zzqx'
assert_eq 'ignored: zzqx' "${reply[16]}"
# A kept word is read by whichever tier reads it alone, so a T3-only word survives the relaxed rerun.
mt_pick relaxed 2 kubernetes/values/kube-prometheus-stack/ 'kps zzqx'
mt_get 'kps zzqx'
assert_eq 'ignored: zzqx' "${reply[16]}"
assert_eq kube-prometheus-stack "${reply[15]}"
# Words read by different tiers that no row holds together keep every row that holds all of them but one.
mt_pick relaxed 4 - 'routemaxter kps zzqx'
mt_get 'routemaxter kps zzqx'
assert_eq 'ignored: zzqx, and one of: routemaxter, kps' "${reply[16]}"
assert_eq 'routemaster | kube-prometheus-stack' "${reply[15]}"
mt_pick relaxed 3 "terraform/acct-infrastructure/env-dev/us-east-1/vpc/" 'routemaster dev'
mt_get 'routemaster dev'
assert_eq 'ignored: one of: routemaster, dev' "${reply[16]}" 'every word matches alone, so dropping one is what finds the rows'
assert_eq 0 "${reply[13]}" 'an ancestor holding one word alone is never injected'


# ---------------------------------------------------------------------------
# HOP_JUMP, and -c.
# ---------------------------------------------------------------------------
mt_pick T1 - "$SP/" security-tooling-prod . cd unique
mt_jump 'jump T1 single' "$SP/env-prod/us-east-1/eks/" 'eks security' . cd unique
mt_pick T1 1 - 'eks security' . cd never

mt_pick T1 2 - vpc terraform/acct-infrastructure cd auto c
# Without the -c filter, acct-infrastructure/ above $PWD would be injected, and J2 would jump OUT of the subtree.
mt_pick T1 8 terraform/acct-infrastructure/env-prod/us-east-1/ infrastructure terraform/acct-infrastructure/env-prod cd auto c
t 'resolve: -c keeps every candidate and every injected ancestor inside $PWD'
typeset -a MT_C=() MT_OUT_C=()
for w in 'vpc	terraform/acct-infrastructure' 'infrastructure	terraform/acct-infrastructure/env-prod'; do
	mt_get "${w%%$'\t'*}" "${w#*$'\t'}" cd auto c
	MT_C=("${(@s:,:)reply[14]}")
	MT_C=(${MT_C:#})
	assert_ne 0 ${#MT_C} "no candidates for ${w%%$'\t'*}, so the check below is vacuous"
	MT_OUT_C=(${MT_C:#${w#*$'\t'}/*})
	assert_eq 0 ${#MT_OUT_C} "a row escaped the -c subtree: ${(j:, :)MT_C}"
done
mt_get infrastructure terraform/acct-infrastructure/env-prod
MT_C=("${(@s:,:)reply[14]}")
assert_ne 0 ${MT_C[(Ie)terraform/acct-infrastructure/]} "the control: without -c the account dir above \$PWD is offered: ${(j:, :)MT_C}"

# A typed term holding [ ] * # is still literal text, both in the J2 tests and in the -c ancestor filter.
mt_jump 'jump T1 dir' 'terraform/acct-l[a]b*#/env-prod/' 'acct-l[a]b*#/env-prod'
mt_jump 'jump T1 dir' 'terraform/acct-l[a]b*#/env-prod/' env-prod 'terraform/acct-l[a]b*#' cd auto c
mt_get env-prod 'terraform/acct-l[a]b*#' cd auto c
assert_eq 1 "${reply[13]}" 'the env dir under a -c dir named with [ ] * # is the injected ancestor'

t '_hop_ancestors walks every strict ancestor, drops dirs already matched, and honours the -c subtree'
assert_eq 'k t/a|t/a' "$(hop_probe '
_hop_ancestors "" t/a/x/ t/a/y/ t/ k/f.yaml "~/elsewhere/"
print -rn -- "${(j: :)${(@o)reply}}|"
_hop_ancestors t t/a/x/ t/a/y/ t/ k/f.yaml
print -rn -- "${(j: :)reply}"')" 't/ is itself a match, a file contributes its parent, and a ~ rel names nothing in the repo'

t 'resolve: an OR group drops every alternative that holds a shorter one, which matches no extra row'
assert_eq 'github_actions | github-actions' "$(hop_probe '
typeset -a _hop_segs=(github_actions github_actions_self_hosted github-actions-deploy-auth github-actions github-actions-runners)
_hop_loose gthbactions
print -r -- "$REPLY"')" 'githubactions had opened on a ten-way OR group'

# The kind-word guard decides only when every match sits under one dir, so it gets rows where that holds.
# - In the full fixture `mesos` also matches a terraform unit, which would keep it a pick with no guard at all.
typeset MT_KIND
MT_KIND=$(hop_probe "
builtin cd -q -- ${(q)MT_REPO} || exit 96
typeset _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
typeset -i _hop_res_n _hop_res_m _hop_res_inj
typeset -a _hop_res_rows reply
_hop_resolve mesos \"\$(_hop_generate \$PWD dir mesos)\" \$PWD cd auto
_hop_rels_of \"\${_hop_res_rows[@]}\"
print -r -- \"\$_hop_res_verdict \${(j:,:)reply}\"")
t 'resolve: a kind word never J2-jumps, even when every match sits under one dir'
assert_eq 'pick mesos/,mesos/services/routemaster/' "$MT_KIND" '`mesos` names the kind, so it is not a request for the mesos/ dir'

# ---------------------------------------------------------------------------
# Properties over the whole table.
# ---------------------------------------------------------------------------
t 'resolve: no nonsense word jumps, and none of them occurs in the fixture'
typeset -a MT_BAD=() MT_HIT=()
typeset MT_ROWS_TEXT=${(L)"$(mt_slurp "$MT_WORK/rows")"}
for w in "${MT_NONSENSE[@]}"; do
	mt_get "$w"
	[[ ${reply[6]} == (pick|none) ]] || MT_BAD+=("${w}=${reply[6]}")
	[[ $MT_ROWS_TEXT == *"$w"* ]] && MT_HIT+=("$w")
done
assert_eq 50 ${#MT_NONSENSE} 'tests/fixtures/nonsense.txt holds the 50 words'
assert_empty "${(j:, :)MT_BAD}" 'a word that names nothing in the repo must never move the shell'
assert_empty "${(j:, :)MT_HIT}" 'these words do occur in the fixture, so they prove nothing about nonsense'

t 'resolve: every pick in the table is exactly fzf'"'"'s own row set for its picker query'
MT_BAD=()
typeset k
for k in "${(@k)MT_RES}"; do
	reply=("${(@ps:\t:)MT_RES[$k]}")
	[[ ${reply[6]} == pick && ${reply[17]} != ok ]] && MT_BAD+=("${reply[1]}")
done
assert_empty "${(j:, :)MT_BAD}" 'a candidate list the picker would not show is a lie on open'

t 'the one --filter call site hands fzf neither --no-sort nor --accept-nth'
typeset MT_FN
MT_FN=$(hop_probe 'functions _hop_filter')
assert_contains "$MT_FN" '_HOP_MATCHER_FLAGS'
assert_not_contains "$MT_FN" 'no-sort' 'on 0.60.3 --filter --no-sort prints the transformed line'
assert_not_contains "$MT_FN" 'accept-nth' '--filter honours it on some versions and not others'

t 'a 4-field row comes back from _hop_filter whole, on the installed fzf'
typeset MT_ROW4=$'\e[1mvpc\e[0m\t/r/vpc\t/r/vpc/main.tf\t\e[2mterraform/vpc/\e[0m'
assert_eq $'vpc\t/r/vpc\t/r/vpc/main.tf\tterraform/vpc/' \
	"$(hop_probe "print -r -- ${(q)MT_ROW4} | _hop_filter vpc")" 'every field, in order, SGR stripped by --ansi'

# ---------------------------------------------------------------------------
# MRU and legacy rows, each in a probe of its own.
# ---------------------------------------------------------------------------
fixture_histfile "$MT_REPO/$IP/vpc" "$MT_REPO/kubernetes/values/thanos-legacy"
typeset MT_MRU
MT_MRU=$(hop_probe "
builtin cd -q -- ${(q)MT_REPO} || exit 96
typeset _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
typeset -i _hop_res_n _hop_res_m _hop_res_inj
typeset -a _hop_res_rows reply
typeset rows q
rows=\$(_hop_rank \"\$(_hop_generate \$PWD \${=HOP_DEFAULT_KINDS//,/ })\")
for q in vpc thanos; do
	_hop_resolve \$q \"\$rows\" \$PWD cd auto
	_hop_rels_of \"\${_hop_res_rows[1]}\"
	print -r -- \"\$q \$_hop_res_verdict \${reply[1]}\"
done")
export HOP_HISTFILE=/dev/null

t 'resolve: a visited vpc is the first picker row, and the verdict is still pick'
assert_contains "$MT_MRU" "vpc pick $IP/vpc/" 'the MRU decides same-name ties, and never turns a pick into a jump'

t 'resolve: the exact name thanos still outranks a visited thanos-legacy'
assert_contains "$MT_MRU" 'thanos pick kubernetes/values/thanos/' 'begin,chunk keeps the exact-name preference over the MRU'

typeset MT_LEG
MT_LEG=$(hop_probe "
builtin cd -q -- ${(q)MT_REPO} || exit 96
_hop_provider_legacy() {
	print -r -- vpc\$'\\t'\$1/legacy/vpc\$'\\t'\$1/legacy/vpc
	print -r -- eks\$'\\t'\$1/legacy/eks\$'\\t'\$1/legacy/eks
}
hop_kind legacy --fn _hop_provider_legacy --desc 'a 3-field provider'
typeset _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
typeset -i _hop_res_n _hop_res_m _hop_res_inj
typeset -a _hop_res_rows
_hop_resolve vpc \"\$(_hop_generate \$PWD legacy)\" \$PWD cd auto
print -r -- \"\$_hop_res_verdict \$_hop_res_rule \${_hop_res_target##*\$'\\t'}\"")

t 'resolve: a legacy 3-field --fn provider still resolves, by its derived rel'
assert_eq 'jump single legacy/vpc/' "$MT_LEG"

# helm and dir are --fn kinds too, and they print 4 fields, so naming legacy alone is the claim.
MT_LEG=$(hop_probe "
builtin cd -q -- ${(q)MT_REPO} || exit 96
_hop_provider_legacy() {
	print -r -- vpc\$'\\t'\$1/legacy/vpc\$'\\t'\$1/legacy/vpc
	print -r -- eks\$'\\t'\$1/legacy/eks\$'\\t'\$1/legacy/eks
}
hop_kind legacy --fn _hop_provider_legacy --desc 'a 3-field provider'
hop --doctor")

typeset -a MT_DOC=("${(@f)MT_LEG}")
typeset MT_LEGROW="${(F)${(@M)MT_DOC:#*legacy*a 3-field provider}}"

t 'hop --doctor names the kind that printed legacy 3-field rows, and no other'
assert_eq '  3-field rows, given a derived rel: legacy (2 rows)' "${(F)${(@M)MT_DOC:#*3-field rows*}}"
assert_nonempty "$MT_LEGROW" 'control: the legacy kind has to be in the doctor kinds table at all'
assert_eq '2' "${${(z)MT_LEGROW}[2]}" 'the upgraded rows still count as rows'

# ---------------------------------------------------------------------------
# The picker's argv and stdin, with a stub that selects instead of drawing.
# ---------------------------------------------------------------------------
# mt_pickrun <stubdir> <hop-code> [VAR=value...] -> run hop with a terminal assumed and the selecting stub as fzf.
# - _hop_tty_ok is forced true, so the resolver's PICK really reaches the picker.
# - Prints the shell's $PWD afterwards, so a selection's cd is observable.
mt_pickrun() {
	emulate -L zsh
	local stub=$1 code=$2
	shift 2
	hop_bound 30 zsh -f -c "$(fixture_pins "$@")
export PATH=${(q)stub}:\$PATH
source ${(q)HOP_HOME}/hop.zsh || exit 97
_hop_tty_ok() { return 0 }
builtin cd -q -- ${(q)MT_REPO} || exit 96
${code}
print -r -- \"PWD=\$PWD\"" 2>&1
}

# mt_argv <stubdir> -> reply is the picker argv the stub recorded, one line per element.
mt_argv() {
	emulate -L zsh
	reply=()
	[[ -r $1/argv ]] && reply=("${(@f)$(<"$1/argv")}")
	return 0
}

typeset MT_STUB MT_RUN MT_ARGS
typeset -a MT_IN
stub_fzf_select '' 2
MT_STUB=$REPLY
MT_RUN=$(mt_pickrun "$MT_STUB" 'hop vpc')
mt_argv "$MT_STUB"
MT_ARGS=${(F)reply}
MT_IN=("${(@f)$(mt_slurp "$MT_STUB/stdin")}")

t 'picker: an ambiguous vpc opens on --query=vpc in ordered mode, without --select-1'
assert_eq 1 ${#${(M)reply:#--query=vpc}} 'the picker must open on the query as typed'
assert_eq 1 ${#${(M)reply:#--no-sort}} 'exactly one --no-sort, or fzf ranks the input before showing it'
assert_eq 1 ${#${(M)reply:#--bind=change:toggle-sort+unbind\(change\)}} 'the first keystroke must hand ranking back to fzf'
assert_eq 0 ${#${(M)reply:#--select-1}} 'a resolver pick never auto-accepts'
assert_eq 1 ${#${(M)reply:#--accept-nth=2,3,4}} 'Enter has to hand back dir, preview and rel'

t 'picker: the vpc rows are the first rows of its stdin'
typeset -a MT_HEAD=("${(@)MT_IN[1,5]}")
assert_eq 5 ${#${(M)MT_HEAD:#*/vpc$'\t'*}} "rows 1-5 must be the five vpc units: ${(F)MT_HEAD}"
assert_ne 5 ${#MT_IN} 'the rest of the rows follow, so backspacing widens the list'

t 'picker: Enter on row 2 cds to row 2'"'"'s dir'
typeset -a MT_R2=("${(@ps:\t:)MT_IN[2]}")
assert_contains "$MT_RUN" "PWD=${MT_R2[2]}" "the selection did not reach the cd: ${MT_RUN}"

stub_fzf_select '' 1
MT_STUB=$REPLY
mt_pickrun "$MT_STUB" 'hop acct sec prod' >/dev/null
MT_IN=("${(@f)$(mt_slurp "$MT_STUB/stdin")}")
t 'picker: acct sec prod opens with the synthetic account row first, still coloured'
assert_contains "${MT_IN[1]}" $'\t'"$MT_REPO/$SP"$'\t' 'row 1 is the injected account dir'
assert_contains "${MT_IN[1]}" $'\e[2m'"$SP/"$'\e[0m' 'an injected row is a real row, dim rel and all'

stub_fzf_select '' 1
MT_STUB=$REPLY
mt_pickrun "$MT_STUB" 'hop securty-tooling-prod' >/dev/null
mt_argv "$MT_STUB"
t 'picker: a T2 pick opens on the rewrite, with a header saying so'
assert_eq 1 ${#${(M)reply:#--query=security tooling prod}} 'the picker query must be what the rows matched'
assert_contains "${(F)reply}" 'no exact match for: securty-tooling-prod (showing: security tooling prod)'

stub_fzf_select '' 1
MT_STUB=$REPLY
mt_pickrun "$MT_STUB" 'hop zzqx' >/dev/null
mt_argv "$MT_STUB"
t 'picker: nothing close opens on the query as typed, with a header saying so'
assert_eq 1 ${#${(M)reply:#--query=zzqx}}
assert_contains "${(F)reply}" 'nothing close to: zzqx (esc clears)'
assert_eq 0 ${#${(M)reply:#--no-sort}} 'there is nothing to order, so ordered mode stays off'

stub_fzf_select '' 1
MT_STUB=$REPLY
mt_pickrun "$MT_STUB" 'hop' >/dev/null
mt_argv "$MT_STUB"
t 'picker: an empty query keeps --select-1, which is the one-row auto-accept'
assert_eq 1 ${#${(M)reply:#--select-1}}
mt_pickrun "$MT_STUB" 'hop' HOP_JUMP=never >/dev/null
mt_argv "$MT_STUB"
assert_eq 0 ${#${(M)reply:#--select-1}} 'HOP_JUMP=never drops it, so even one row waits for Enter'
assert_ne 0 ${#reply} 'the picker never ran, so the absence above means nothing'

stub_fzf_select '' 1
MT_STUB=$REPLY
mt_pickrun "$MT_STUB" 'hop -p eks security' >/dev/null
mt_argv "$MT_STUB"
t 'picker: -p opens the picker despite a unique match'
assert_eq 1 ${#${(M)reply:#--query=eks security}} 'the unique match jumped, so -p did nothing'
assert_eq 0 ${#${(M)reply:#--select-1}} 'with --select-1 the one row would accept itself and -p would be a no-op'

stub_fzf_select '' 1
MT_STUB=$REPLY
mt_pickrun "$MT_STUB" 'hop security-tooling-prod' HOP_JUMP=unique >/dev/null
mt_argv "$MT_STUB"
t 'picker: HOP_JUMP=unique opens the picker where J2 would have jumped'
assert_eq 1 ${#${(M)reply:#--query=security-tooling-prod}}

t 'picker: an invalid HOP_JUMP warns once and behaves as auto'
stub_fzf_select '' 1
MT_STUB=$REPLY
MT_RUN=$(mt_pickrun "$MT_STUB" 'hop eks security' HOP_JUMP=bogus)
assert_contains "$MT_RUN" 'hop: HOP_JUMP=bogus is not one of auto, unique, never; using auto'
assert_contains "$MT_RUN" "PWD=$MT_REPO/$SP/env-prod/us-east-1/eks" 'auto still jumps on the unique match'

for w in 0.67.0 0.60.3; do
	stub_fzf_select '' 1
	MT_STUB=$REPLY
	mt_pickrun "$MT_STUB" 'hop vpc' "HOP_FZF_STUB_VER=$w" >/dev/null
	mt_argv "$MT_STUB"
	t "picker: --freeze-left=1 follows the fzf version, here ${w}"
	if [[ $w == 0.67.0 ]]; then
		assert_eq 1 ${#${(M)reply:#--freeze-left=1}} 'fzf 0.67.0 and later keep the name column in view'
	else
		assert_eq 0 ${#${(M)reply:#--freeze-left=1}} 'fzf 0.60.3 exits 2 on --freeze-left'
	fi
done

# ---------------------------------------------------------------------------
# The workspace and repo levels: the same resolver, with no root.
# ---------------------------------------------------------------------------
# Built under the probe's $HOME, so every rel is the ~ form a real user sees.
typeset MT_WSH=$HOP_FIX_HOME
for w in strava/configuration strava/hop personal/notes; do
	mkdir -p -- "$MT_WSH/$w"
	_hop_fix_git -C "$MT_WSH/$w" init -q -b main
done
typeset MT_WS="strava-ws=${MT_WSH}/strava:personal-ws=${MT_WSH}/personal"

# mt_headless <cwd> <hop-code> [VAR=value...] -> run hop with NO terminal, stderr and the final $PWD both printed.
mt_headless() {
	emulate -L zsh
	local cwd=$1 code=$2
	shift 2
	hop_bound 30 zsh -f -c "$(fixture_pins "$@")
source ${(q)HOP_HOME}/hop.zsh || exit 97
_hop_tty_ok() { return 1 }
builtin cd -q -- ${(q)cwd} || exit 96
${code}
print -r -- \"st=\$? PWD=\$PWD\"" 2>&1
}

t 'workspaces: hop -w with a unique name jumps there'
MT_RUN=$(mt_headless "$MT_REPO" 'hop -w strava' "HOP_WORKSPACES=$MT_WS")
assert_contains "$MT_RUN" "st=0 PWD=$MT_WSH/strava"

t 'workspaces: hop -w matching two workspaces names the count'
MT_RUN=$(mt_headless "$MT_REPO" 'hop -w ws' "HOP_WORKSPACES=$MT_WS")
assert_contains "$MT_RUN" '2 targets matched the query: ws'
assert_contains "$MT_RUN" "st=1 PWD=$MT_REPO"

t 'workspaces: outside a repo, a name no workspace answers falls back to the repos'
MT_RUN=$(mt_headless "$MT_WSH" 'hop configuration' "HOP_WORKSPACES=$MT_WS")
assert_contains "$MT_RUN" "st=0 PWD=$MT_WSH/strava/configuration" 'hop configuration from ~ has to land on the repo'

t 'workspaces: and a name neither level answers still says nothing matched'
MT_RUN=$(mt_headless "$MT_WSH" 'hop zzqx' "HOP_WORKSPACES=$MT_WS")
assert_contains "$MT_RUN" 'nothing matched the query: zzqx'
assert_contains "$MT_RUN" "st=1 PWD=$MT_WSH"

t 'repos: hop -R matches by the ~ rel'
MT_RUN=$(mt_headless "$MT_REPO" 'hop -R strava/conf' "HOP_WORKSPACES=$MT_WS")
assert_contains "$MT_RUN" "st=0 PWD=$MT_WSH/strava/configuration"

# ---------------------------------------------------------------------------
# A user's own fzf defaults, which every other run here pins empty.
# ---------------------------------------------------------------------------
# mt_hostile <alias> <hop-code> -> mt_headless's run, with hostile FZF_DEFAULT_OPTS and an fzf alias defined before hop.zsh is sourced.
mt_hostile() {
	emulate -L zsh
	hop_bound 30 zsh -f -c "$(fixture_pins 'FZF_DEFAULT_OPTS=--no-sort --tac --nth=1 --accept-nth=1 --scheme=path')
${1}
source ${(q)HOP_HOME}/hop.zsh || exit 97
_hop_tty_ok() { return 1 }
builtin cd -q -- ${(q)MT_REPO} || exit 96
${2}
print -r -- \"st=\$? PWD=\$PWD\"" 2>&1
}

typeset MT_QS="for q in acct-security-tooling-prod/env-prod vpc 'trust prod' 'eks security' securty-tooling-prod; do (hop \${=q}; print -r -- \"st=\$? PWD=\$PWD\"); done"
typeset MT_CLEAN
MT_CLEAN=$(mt_headless "$MT_REPO" "$MT_QS")
t 'resolve: hostile FZF_DEFAULT_OPTS and an fzf alias change no resolve'
MT_RUN=$(mt_hostile "alias fzf='fzf --read0'" "$MT_QS")
assert_eq "$MT_CLEAN" "$MT_RUN" 'a user default leaked into the resolver'"'"'s fzf --filter'
assert_contains "$MT_RUN" "st=0 PWD=$MT_REPO/$SP/env-prod" 'control: the J2 jump has to be among the runs compared'

# ---------------------------------------------------------------------------
# tests/eval_real.zsh, the real-repo sweep harness, driven over the fixture.
# ---------------------------------------------------------------------------
# tests/run never runs the harness, so these are what keep it from rotting between real-repo runs.
# - nonsense is left out: its 500 words cost a resolve each, and the nonsense property above already covers the rule.

# mt_eval [VAR=value...] -- [set...] -> run the harness over the fixture repo, then print its status.
mt_eval() {
	emulate -L zsh
	local -a pins
	while (( $# )) && [[ $1 != -- ]]; do
		pins+=("$1")
		shift
	done
	shift
	hop_bound 120 zsh -f -c "$(fixture_pins "HOP_TEST_REPO=$MT_REPO" "${pins[@]}")
zsh -f ${(q)HOP_HOME}/tests/eval_real.zsh ${(j: :)${(@q)argv}}
print -r -- \"st=\$?\"" 2>&1
}

# mt_eval_cols <output> <set> -> reply is that set's table columns: set queries today kept lost changed new pick none seconds.
mt_eval_cols() {
	emulate -L zsh
	local line=${(M)${(@f)1}:#${(b)2} *}
	reply=(${=line})
}

t 'eval_real: without HOP_TEST_REPO it skips, and succeeds'
MT_RUN=$(hop_bound 30 zsh -f -c "$(fixture_pins HOP_TEST_REPO=)
zsh -f ${(q)HOP_HOME}/tests/eval_real.zsh
print -r -- \"st=\$?\"" 2>&1)
assert_contains "$MT_RUN" 'eval_real: skipped'
assert_contains "$MT_RUN" 'st=0'

t 'eval_real: an unknown set is refused with status 2'
MT_RUN=$(mt_eval -- names bogus)
assert_contains "$MT_RUN" 'eval_real: unknown set: bogus'
assert_contains "$MT_RUN" 'st=2'

MT_RUN=$(mt_eval -- names pref3 scope+env name+env)

t 'eval_real: over the fixture, every jump today is kept and the run succeeds'
mt_eval_cols "$MT_RUN" names
assert_eq 10 $#reply "no names line in: ${MT_RUN}"
assert_eq '0 0' "${reply[5]} ${reply[6]}" 'names: lost and changed'
assert_eq "${reply[3]}" "${reply[4]}" 'names: every jump today is kept'
assert_eq 1 $(( ${reply[3]:-0} > 0 )) 'control: with no jump today, kept equalling today proves nothing'
assert_contains "$MT_RUN" 'eval_real: ok'
assert_contains "$MT_RUN" 'st=0'

t 'eval_real: the four query sets are all derived and swept'
typeset MT_SET
typeset -a MT_EMPTY=()
for MT_SET in names pref3 scope+env name+env; do
	mt_eval_cols "$MT_RUN" "$MT_SET"
	(( ${reply[2]:-0} > 0 )) || MT_EMPTY+=("$MT_SET")
done
assert_empty "${(j:, :)MT_EMPTY}" 'a set with no queries would pass vacuously'

t 'eval_real: the fixture'"'"'s scope+env pairs jump to the account dirs as new jumps'
assert_contains "$MT_RUN" 'new      scope+env  security-tooling-prod prod  -> terraform/acct-security-tooling-prod/ (T1 dir)'

t 'eval_real: HOP_EVAL_JUMP=never loses every jump today, and the run fails naming them'
MT_RUN=$(mt_eval HOP_EVAL_JUMP=never -- names)
mt_eval_cols "$MT_RUN" names
assert_eq "${reply[3]}" "${reply[5]}" 'under never, every jump today is lost'
assert_contains "$MT_RUN" 'lost     names  abg  today -> sandbox/abg/  now pick T1 -'
assert_contains "$MT_RUN" 'eval_real: FAIL'
assert_contains "$MT_RUN" 'st=1'
