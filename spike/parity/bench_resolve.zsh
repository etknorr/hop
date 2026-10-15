#!/usr/bin/env zsh
# bench_resolve.zsh [ROOT] [RUNS]: median wall ms for `hopx [-p] <q>` against `hop [-p] <q>`, headless, on the four probe queries.
# - With no terminal both end at the headless report, which is where the picker's first draw would start.
# - "hop cold" is a fresh zsh sourcing hop.zsh first; "hop warm" is hop alone in an already-sourced shell.
# - Each run cds nowhere: a jump under hopx writes a cmdfile in the temp dir, and hop's runs are subshells.
emulate -L zsh
zmodload zsh/datetime
local here=${0:A:h}
local spike=${here:h} hopdir=${here:h:h}
local root=${1:-$HOME/strava/configuration}
local -i runs=${2:-15}
local tmp
tmp=$(mktemp -d) || return 1
local bin="$tmp/hopx"
(cd "$spike/hopx" && go build -o "$bin" .) || return 1
export HOP_HISTFILE=/dev/null HOPX_HISTFILE="$tmp/hist" XDG_CACHE_HOME="$tmp/cache"
export HOP_CONFIG="$HOME/.config/hop/config.zsh" HOPX_CONFIG="$spike/hopx/testdata/eric.toml"
unset HOP_DEFAULT_KINDS HOP_JUMP FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE
builtin cd -q -- "$root" || return 1

median() {
	emulate -L zsh
	local -a s=("${(@on)argv}")
	print -r -- "${s[$(( ($#s + 1) / 2 ))]}"
}

time_cmd() {
	emulate -L zsh
	local -a ms
	local -F t0
	local -i i
	for (( i = 0; i < runs; i++ )); do
		rm -f "$tmp/cmd"
		t0=$EPOCHREALTIME
		HOPX_CMDFILE="$tmp/cmd" "$@" >/dev/null 2>&1 </dev/null
		ms+=("$(( (EPOCHREALTIME - t0) * 1000 ))")
	done
	printf '%.1f' "$(median "${ms[@]}")"
}

local warm='source "$1/hop.zsh"; zmodload zsh/datetime; local -F t0; local -a ms; local -i i
for (( i = 0; i < $2; i++ )); do t0=$EPOCHREALTIME; (hop ${=3}) >/dev/null 2>&1 </dev/null; ms+=("$(( (EPOCHREALTIME - t0) * 1000 ))"); done
ms=("${(@on)ms}"); printf "%.1f" "${ms[$(( ($#ms + 1) / 2 ))]}"'

printf '%-26s %10s %10s %10s %s\n' query hopx hop-cold hop-warm verdict
local q x c w v
for q in '-p vpc' '-p vpc prod' '-p eks staging' '-p acct sec tooling prod' vpc 'eks security' securty-tooling-prod 'kps zzqx'; do
	x=$(time_cmd "$bin" ${=q})
	c=$(time_cmd zsh -f -c 'source "$1/hop.zsh"; hop ${=2}' zsh "$hopdir" "$q")
	w=$(zsh -f -c "$warm" zsh "$hopdir" "$runs" "$q")
	v=$(HOPX_CMDFILE="$tmp/v" "$bin" ${=q} 2>&1 </dev/null | sed -n 's/^hop: \([0-9]* targets*\) matched.*/\1/p;s/^hop: nothing matched.*/none/p')
	[[ -e $tmp/v ]] && v=jump
	rm -f "$tmp/v"
	printf '%-26s %8sms %8sms %8sms %s\n' "$q" "$x" "$c" "$w" "${v:-?}"
done
rm -rf "$tmp"
