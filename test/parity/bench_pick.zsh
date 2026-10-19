#!/usr/bin/env zsh
# bench_pick.zsh [ROOT] [RUNS]: median wall ms for the picker callbacks against hop's standalone scripts.
# - __preview against bin/hop-preview, on one unit's preview file and on its dir.
# - __rows (the reload, ranked, from a session) against `bin/hop-kinds rows`, on the default kinds.
# - __menu against `bin/hop-kinds menu`, whose counts come from a cache that is warm after the first run.
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
		t0=$EPOCHREALTIME
		"$@" >/dev/null 2>&1 </dev/null
		ms+=("$(( (EPOCHREALTIME - t0) * 1000 ))")
	done
	printf '%.1f' "$(median "${ms[@]}")"
}

local -a f
f=("${(@ps:\t:)$("$bin" rows -k tg | sed -n 1p)}")
local dir=${f[2]} file=${f[3]}
local -a kinds=(tg mod helm dir mesos)
print -r -- "{\"root\":\"$root\",\"kinds\":[\"${(j:",":)kinds}\"]}" >"$tmp/session.json"
export HOPX_SESSION=$tmp/session.json

print -r -- "callback	hopx ms	hop ms	target"
print -r -- "preview file	$(time_cmd "$bin" __preview "$dir" "$file")	$(time_cmd "$hopdir/bin/hop-preview" "$dir" "$file")	${file#$root/}"
print -r -- "preview dir	$(time_cmd "$bin" __preview "$dir" "$dir")	$(time_cmd "$hopdir/bin/hop-preview" "$dir" "$dir")	${dir#$root/}/"
print -r -- "rows (reload)	$(time_cmd "$bin" __rows)	$(time_cmd "$hopdir/bin/hop-kinds" rows "$root" "${kinds[@]}")	${(j:,:)kinds}, $("$bin" __rows | wc -l | tr -d ' ') rows"
"$hopdir/bin/hop-kinds" menu "$root" >/dev/null 2>&1
sleep 3
print -r -- "menu	$(time_cmd "$bin" __menu)	$(time_cmd "$hopdir/bin/hop-kinds" menu "$root")	hop's counts cached"
