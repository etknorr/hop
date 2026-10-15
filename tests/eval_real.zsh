#!/usr/bin/env zsh
# eval_real: the resolver's regression and nonsense sweeps, run over a real checkout's own rows.
# usage: HOP_TEST_REPO=/path/to/checkout zsh tests/eval_real.zsh [set...]
#
# - Not a suite_*, so tests/run never picks it up: what it measures is a repo no fixture stands in for.
# - Sets: names, pref3, scope+env, name+env and nonsense; no argument runs all five.
# - Every query is decided twice: by the matcher hop 0.1.2 shipped, and by T0 then _hop_resolve as hop() runs them.
# - It fails on a jump that today's matcher makes and the resolver now picks for, or sends somewhere else.
# - Except a clipped one: today's single display hit is lost because another match's column was clipped, so it was a guess.
# - It also fails on any jump for a dictionary word the rows do not hold.
# - New jumps are listed, never failed, because adding them is what the resolver is for.
# - Read-only: hop() is never called, so nothing cds, opens a window or writes history.
# - HOP_CONFIG picks the kinds, as it does for hop; HOP_HISTFILE defaults to /dev/null so the input order is generate's.
# - HOP_EVAL_JUMP=unique or never re-runs the sweeps as that HOP_JUMP would decide them.

emulate -L zsh
setopt extended_glob
zmodload zsh/datetime

typeset -g EV_HOME=${0:A:h:h}
typeset -g EV_REPO=${HOP_TEST_REPO:-}
if [[ -z $EV_REPO ]]; then
	print -r -- 'eval_real: skipped; set HOP_TEST_REPO to a git checkout to run the sweeps'
	exit 0
fi
typeset -g EV_ROOT
if ! EV_ROOT=$(git -C "$EV_REPO" rev-parse --show-toplevel 2>/dev/null) || [[ -z $EV_ROOT ]]; then
	print -ru2 -- "eval_real: not a git checkout: ${EV_REPO}"
	exit 2
fi

typeset -ga EV_ALL_SETS=(names pref3 scope+env name+env nonsense)
typeset -ga EV_SETS=("${EV_ALL_SETS[@]}")
(( $# )) && EV_SETS=("$@")
typeset s
for s in "${EV_SETS[@]}"; do
	if (( ! ${EV_ALL_SETS[(Ie)$s]} )); then
		print -ru2 -- "eval_real: unknown set: ${s} (one of: ${EV_ALL_SETS[*]})"
		exit 2
	fi
done

typeset -g EV_JUMP=${HOP_EVAL_JUMP:-auto}
if [[ $EV_JUMP != (auto|unique|never) ]]; then
	print -ru2 -- "eval_real: HOP_EVAL_JUMP=${EV_JUMP} is not one of auto, unique, never"
	exit 2
fi

export HOP_HISTFILE=${HOP_HISTFILE:-/dev/null}
source "$EV_HOME/hop.zsh"
# T0 resolves a bare path against $PWD first, so the sweep stands where `hop` from the root would.
cd "$EV_ROOT" || exit 2

# The fields _hop_resolve writes by name; hop's pickers declare them local, and this script is their caller.
typeset -g _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
typeset -gi _hop_res_n _hop_res_m _hop_res_inj
typeset -ga _hop_res_rows

typeset -ga EV_KINDS=(${=${HOP_DEFAULT_KINDS//,/ }})
typeset -g EV_TARGETS
if ! EV_TARGETS=$(_hop_rows "$EV_ROOT" '' "${EV_KINDS[@]}") || [[ -z $EV_TARGETS ]]; then
	print -ru2 -- "eval_real: no rows in ${EV_ROOT} for kinds: ${EV_KINDS[*]}"
	exit 2
fi
typeset -ga EV_ROWS=("${(@f)EV_TARGETS}")
EV_ROWS=(${EV_ROWS:#})

# The matcher hop 0.1.2 shipped, restated on purpose: it is the baseline, so it must not follow _HOP_MATCHER_FLAGS.
# - The display column only, smart case, and begin,length; a query matching exactly one row jumped to its dir.
typeset -ga EV_TODAY_FLAGS=(--ansi --delimiter=$'\t' --with-nth=1 --exact --tiebreak=begin,length)

# ev_today <query> -> 0 with REPLY the dir today's matcher jumped to, 1 when it matched none or several.
ev_today() {
	emulate -L zsh
	local out
	out=$(print -r -- "$EV_TARGETS" | fzf --filter="$1" "${EV_TODAY_FLAGS[@]}")
	local -a m=("${(@f)out}")
	m=(${m:#})
	REPLY=''
	(( $#m == 1 )) || return 1
	local -a f=("${(@ps:\t:)m[1]}")
	REPLY=${f[2]}
}

# ev_now <query> -> EV_V (jump, pick or none), EV_WHY (tier and rule), EV_DIR, and EV_REL (the target, or the best pick).
# - T0 first, for a one-word query, exactly as hop() tries it before any rows are matched.
ev_now() {
	emulate -L zsh
	local q=$1
	local -a words=(${=q}) reply
	EV_DIR='' EV_REL=''
	if (( $#words == 1 )) && [[ $EV_JUMP != never ]] && _hop_literal_target "$q" "$EV_ROOT"; then
		EV_V=jump EV_WHY='T0 path' EV_DIR=${reply[1]} EV_REL=${reply[3]}
		return 0
	fi
	_hop_resolve "$q" "$EV_TARGETS" "$EV_ROOT" cd "$EV_JUMP" ''
	EV_V=$_hop_res_verdict
	EV_WHY="${_hop_res_tier:--} ${_hop_res_rule:--}"
	if [[ $EV_V == jump ]]; then
		local -a f=("${(@ps:\t:)_hop_res_target}")
		EV_DIR=${f[1]} EV_REL=${f[3]}
	elif (( $#_hop_res_rows )); then
		_hop_rels_of "${_hop_res_rows[1]}"
		EV_REL=${reply[1]}
	fi
}

# ev_clipped <dir> -> 0 when a candidate other than <dir> has a clipped display column, so today's one hit was a guess.
ev_clipped() {
	emulate -L zsh
	local r
	local -a f
	for r in "${_hop_res_rows[@]}"; do
		f=("${(@ps:\t:)r}")
		[[ ${f[2]:A} != "${1:A}" && ${f[1]} == *…* ]] && return 0
	done
	return 1
}

# ev_rel <dir> -> REPLY, the dir as a rel, so a report line reads like a row.
ev_rel() {
	emulate -L zsh
	if [[ ${1:A} == "${EV_ROOT:A}" ]]; then
		REPLY=./
	else
		REPLY=${1#"$EV_ROOT"/}/
	fi
}

typeset -g EV_V EV_WHY EV_DIR EV_REL
typeset -ga EV_TABLE EV_FAIL EV_NEW
typeset -gi EV_BAD=0

# ev_sweep <set> <query...> -> one table line in EV_TABLE, and a line per failure or new jump.
# - nonsense has no baseline: every one of its words is absent from the rows, so any jump is a failure.
ev_sweep() {
	emulate -L zsh
	local set=$1 q tdir
	shift
	local -i today=0 kept=0 lost=0 changed=0 clipped=0 new=0 pick=0 none=0
	local -F t0=$EPOCHREALTIME
	local REPLY
	for q in "$@"; do
		tdir=''
		if [[ $set != nonsense ]] && ev_today "$q"; then
			tdir=$REPLY
		fi
		ev_now "$q"
		case $EV_V in
			(pick) (( pick++ )) ;;
			(none) (( none++ )) ;;
		esac
		if [[ -n $tdir ]]; then
			(( today++ ))
			ev_rel "$tdir"
			if [[ $EV_V == jump && ${EV_DIR:A} == "${tdir:A}" ]]; then
				(( kept++ ))
			elif [[ $EV_V == jump ]]; then
				(( changed++ ))
				EV_FAIL+=("changed  ${set}  ${q}  today -> ${REPLY}  now -> ${EV_REL} (${EV_WHY})")
			elif [[ $EV_V == pick && $EV_JUMP != never ]] && ev_clipped "$tdir"; then
				(( clipped++ ))
				EV_NEW+=("clipped  ${set}  ${q}  today -> ${REPLY}  now pick ${EV_WHY}, since a clipped row matches too")
			else
				(( lost++ ))
				EV_FAIL+=("lost     ${set}  ${q}  today -> ${REPLY}  now ${EV_V} ${EV_WHY}, best ${EV_REL:--}")
			fi
		elif [[ $EV_V == jump ]]; then
			(( new++ ))
			if [[ $set == nonsense ]]; then
				EV_FAIL+=("jump     ${set}  ${q}  -> ${EV_REL} (${EV_WHY})")
			else
				EV_NEW+=("new      ${set}  ${q}  -> ${EV_REL} (${EV_WHY})")
			fi
		fi
	done
	local secs
	printf -v secs '%.1f' $(( EPOCHREALTIME - t0 ))
	(( EV_BAD += lost + changed ))
	[[ $set == nonsense ]] && (( EV_BAD += new ))
	EV_TABLE+=("$(printf '%-10s %7d %6d %5d %5d %8d %8d %4d %5d %5d %8s' \
		"$set" $# $today $kept $lost $changed $clipped $new $pick $none "$secs")")
}

# The query sets come from the rows' own display columns: name, kind, scope, env, region.
# - names is every distinct name, and pref3 every distinct 3-character prefix of one.
# - scope+env and name+env pair a row's scope or name with its env, wherever the row has an env.
typeset -ga EV_NAMES EV_PREF3 EV_SCOPEENV EV_NAMEENV EV_WORDS
typeset r n
typeset -a w
typeset IFS=$' \t\n'
for r in "${(@)EV_ROWS//$'\e'\[[0-9;]#m/}"; do
	w=(${=r%%$'\t'*})
	EV_NAMES+=("${w[1]}")
	[[ -n ${w[4]:-} && ${w[4]} != - ]] || continue
	EV_NAMEENV+=("${w[1]} ${w[4]}")
	[[ ${w[3]} != - ]] && EV_SCOPEENV+=("${w[3]} ${w[4]}")
done
EV_NAMES=("${(@ou)EV_NAMES}")
for n in "${EV_NAMES[@]}"; do
	EV_PREF3+=("${n[1,3]}")
done
EV_PREF3=("${(@ou)EV_PREF3}")
EV_SCOPEENV=("${(@ou)EV_SCOPEENV}")
EV_NAMEENV=("${(@ou)EV_NAMEENV}")

# A dictionary word the rows DO hold proves nothing about nonsense, so the resolver's own T1 drops it first.
typeset -i EV_PRESENT=0
if (( ${EV_SETS[(Ie)nonsense]} )); then
	typeset -a reply
	for n in "${(@f)$(<"$EV_HOME/tests/fixtures/dictionary.txt")}"; do
		[[ -n $n ]] || continue
		if _hop_match "$n" "$EV_TARGETS"; then
			(( EV_PRESENT++ ))
		else
			EV_WORDS+=("$n")
		fi
	done
fi

typeset fv
fv=$(fzf --version 2>/dev/null)
print -r -- "eval_real: ${EV_ROOT}  ${#EV_ROWS} rows  kinds ${(j:,:)EV_KINDS}  fzf ${fv%% *}  HOP_JUMP=${EV_JUMP}"
(( EV_PRESENT )) && print -r -- "eval_real: ${EV_PRESENT} dictionary words occur in the rows, so nonsense skips them"

for s in "${EV_SETS[@]}"; do
	case $s in
		(names) ev_sweep names "${EV_NAMES[@]}" ;;
		(pref3) ev_sweep pref3 "${EV_PREF3[@]}" ;;
		(scope+env) ev_sweep scope+env "${EV_SCOPEENV[@]}" ;;
		(name+env) ev_sweep name+env "${EV_NAMEENV[@]}" ;;
		(nonsense) ev_sweep nonsense "${EV_WORDS[@]}" ;;
	esac
done

print -r -- ''
printf '%-10s %7s %6s %5s %5s %8s %8s %4s %5s %5s %8s\n' set queries today kept lost changed clipped new pick none seconds
print -rl -- "${EV_TABLE[@]}"
if (( $#EV_NEW )); then
	print -r -- ''
	print -rl -- "${EV_NEW[@]}"
fi
if (( $#EV_FAIL )); then
	print -r -- ''
	print -rl -- "${EV_FAIL[@]}"
fi
print -r -- ''
if (( EV_BAD )); then
	print -r -- "eval_real: FAIL, ${EV_BAD} lost or changed jumps and nonsense jumps"
	exit 1
fi
print -r -- 'eval_real: ok, no lost or changed jump and no nonsense jump'
exit 0
