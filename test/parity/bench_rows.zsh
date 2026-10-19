#!/usr/bin/env zsh
# bench_rows.zsh [ROOT] [RUNS]: median wall ms for hopx rows against zsh hop, for the default set and `file`.
# - "hop cold" is a fresh zsh that sources hop.zsh and runs _hop_generate, which is what hopx's exec replaces.
# - "hop warm" is _hop_generate alone in an already-sourced shell, which is what an interactive hop pays.
emulate -L zsh
zmodload zsh/datetime
local here=${0:A:h}
local repo=${here:h:h} hopdir=${here:h:h}
local root=${1:-$HOME/strava/configuration}
local -i runs=${2:-15}
local tmp
tmp=$(mktemp -d) || return 1
local bin="$tmp/hopx"
(cd "$repo" && go build -o "$bin" .) || return 1
export HOP_HISTFILE=/dev/null HOPX_HISTFILE="$tmp/hist" XDG_CACHE_HOME="$tmp/cache"
export HOP_CONFIG="$HOME/.config/hop/config.zsh" HOPX_CONFIG="$repo/testdata/eric.toml"
unset HOP_DEFAULT_KINDS

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
		t0=$EPOCHREALTIME
		"$@" >/dev/null 2>&1
		ms+=("$(( (EPOCHREALTIME - t0) * 1000 ))")
	done
	printf '%.1f' "$(median "${ms[@]}")"
}

local warm='source "$1/hop.zsh"; zmodload zsh/datetime; local -F t0; local -a ms; local -i i
for (( i = 0; i < $3; i++ )); do t0=$EPOCHREALTIME; _hop_generate "$2" ${=4} >/dev/null 2>&1; ms+=("$(( (EPOCHREALTIME - t0) * 1000 ))"); done
ms=("${(@on)ms}"); printf "%.1f" "${ms[$(( ($#ms + 1) / 2 ))]}"'

printf '%-8s %10s %10s %10s %7s\n' set hopx hop-cold hop-warm rows
local set kinds x c w n
for set in default file; do
	if [[ $set == default ]]; then kinds='tg mod helm dir mesos'; else kinds=file; fi
	x=$(time_cmd "$bin" __rows "$root" ${=kinds})
	c=$(time_cmd zsh -f -c 'source "$1/hop.zsh"; _hop_generate "$2" ${=3}' zsh "$hopdir" "$root" "$kinds")
	w=$(zsh -f -c "$warm" zsh "$hopdir" "$root" "$runs" "$kinds")
	n=$("$bin" __rows "$root" ${=kinds} | wc -l)
	printf '%-8s %8sms %8sms %8sms %7s\n' "$set" "$x" "$c" "$w" "${n// /}"
done
rm -rf "$tmp"
