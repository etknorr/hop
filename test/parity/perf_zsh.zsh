#!/usr/bin/env zsh
# perf_zsh.zsh <hop-dir> <root> rows <runs> | resolve <jump> <query-file...>: zsh hop's side of perf.sh, timed inside one sourced shell.
# - rows prints the median ms of _hop_rows, as hop() lists targets, for the default kinds and for file.
# - resolve prints set, query, tier and ms per query: T0 first for one word, then _hop_resolve over one ranked list, as hop() runs it.
emulate -L zsh
setopt extended_glob
zmodload zsh/datetime
local hopdir=${1:A} root=${2:A} mode=$3
shift 3
export HOP_HISTFILE=/dev/null
source "$hopdir/hop.zsh" || exit 3
builtin cd -q -- "$root" || exit 2
local -a kinds=(${=${HOP_DEFAULT_KINDS//,/ }})

perf_median() {
	emulate -L zsh
	local -a s=("${(@on)argv}")
	print -r -- "${s[$(( ($#s + 1) / 2 ))]}"
}

if [[ $mode == rows ]]; then
	local -i runs=$1 i
	local -F t0
	local -a ms out
	local set
	for set in default file; do
		ms=()
		for (( i = 0; i < runs; i++ )); do
			t0=$EPOCHREALTIME
			if [[ $set == default ]]; then
				out=("${(@f)$(_hop_rows "$root" '' "${kinds[@]}")}")
			else
				out=("${(@f)$(_hop_rows "$root" '' file)}")
			fi
			ms+=("$(( (EPOCHREALTIME - t0) * 1000 ))")
		done
		printf '%s\t%d\t%.1f\n' "$set" "$#out" "$(perf_median "${ms[@]}")"
	done
	exit 0
fi

local jump=$1
shift
typeset -g _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
typeset -gi _hop_res_n _hop_res_m _hop_res_inj
typeset -ga _hop_res_rows
local targets f q tier
local -a reply w
local -F t0
targets=$(_hop_rows "$root" '' "${kinds[@]}") || exit 2
local _hop_row_like=${targets%%$'\n'*}
for f in "$@"; do
	for q in "${(@f)$(<"$f")}"; do
		[[ -n $q ]] || continue
		w=(${=q})
		t0=$EPOCHREALTIME
		if [[ $jump != never ]] && (( $#w == 1 )) && _hop_literal_target "$q" "$root"; then
			tier=T0
		else
			_hop_resolve "$q" "$targets" "$root" cd "$jump" ''
			tier=$_hop_res_tier
		fi
		printf '%s\t%s\t%s\t%.3f\n' "${f:t:r}" "$q" "${tier:--}" "$(( (EPOCHREALTIME - t0) * 1000 ))"
	done
done
