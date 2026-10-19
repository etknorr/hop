#!/usr/bin/env zsh
# bench_shells.zsh [ROOT] [RUNS]: what the shell function costs, per shell, against hop in zsh.
# - jump: one `<fn> eks security` through the shell function, cd included, as (T(15 jumps) - T(0 jumps)) / 15 in one shell.
# - init: `eval "$(hopx init <shell>)"` (or `source hop.zsh`) over a bare `<shell> -c :`, median of RUNS.
# - fish and pwsh run in the test/docker images with ROOT mounted read-only at /repo, so their numbers include
#   docker's bind-mount filesystem and are not comparable to the host rows.
# - /repo and not ROOT's own path: a ~/strava path mounted at itself shows up empty under Docker Desktop.
emulate -L zsh
zmodload zsh/datetime
local here=${0:A:h}
local repo=${here:h:h} hopdir=${here:h:h}
local root=${1:-$HOME/strava/configuration}
local -i runs=${2:-15} n=15
local tmp
tmp=$(mktemp -d) || return 1
mkdir -p "$tmp/darwin" "$tmp/linux"
(cd "$repo" && go build -o "$tmp/darwin/hopx" . && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o "$tmp/linux/hopx" .) || return 1
local cfg="$repo/testdata/eric.toml"
local -a envv=(env -i HOME="$tmp" PATH="$tmp/darwin:/usr/bin:/bin:/opt/homebrew/bin" LANG=en_US.UTF-8 TERM=xterm-256color TMPDIR="$tmp/"
	HOPX_CONFIG="$cfg" HOPX_HISTFILE="$tmp/hist" HOP_CONFIG="$HOME/.config/hop/config.zsh" HOP_HISTFILE=/dev/null XDG_CACHE_HOME="$tmp/cache")

median() {
	emulate -L zsh
	local -a s=("${(@on)argv}")
	print -r -- "${s[$(( ($#s + 1) / 2 ))]}"
}

# ms <reps> <argv...>: median wall ms of the command.
ms() {
	emulate -L zsh
	local -i reps=$1 i
	shift
	local -a t
	local -F t0
	for (( i = 0; i < reps; i++ )); do
		t0=$EPOCHREALTIME
		"${envv[@]}" "$@" >/dev/null 2>&1 </dev/null
		t+=("$(( (EPOCHREALTIME - t0) * 1000 ))")
	done
	median "${t[@]}"
}

# row <label> <argv-before-c> <init> <jump-loop with @N@>
row() {
	emulate -L zsh
	local label=$1 init=$3 loop=$4
	local -a sh=(${=2})
	local bare full j0 jn
	bare=$(ms $runs "${sh[@]}" -c ':')
	full=$(ms $runs "${sh[@]}" -c "$init")
	j0=$(ms 5 "${sh[@]}" -c "$init; cd '$root'; ${loop//@N@/0}")
	jn=$(ms 5 "${sh[@]}" -c "$init; cd '$root'; ${loop//@N@/$n}")
	printf '%s\t%.1f\t%.1f\n' "$label" "$(( (jn - j0) / n ))" "$(( full - bare ))"
}

local bashloop='i=0; while [ $i -lt @N@ ]; do hopx eks security; cd "'$root'"; i=$((i+1)); done'
print -r -- "shell	ms per jump	init ms"
row 'hop (zsh, sourced)' 'zsh -f' "source '$hopdir/hop.zsh'" 'repeat @N@ { hop eks security; cd "'$root'" }'
row 'hopx zsh' 'zsh -f' 'eval "$(hopx init zsh)"' 'repeat @N@ { hopx eks security; cd "'$root'" }'
row 'hopx bash 5.3' '/opt/homebrew/bin/bash --norc --noprofile' 'eval "$(hopx init bash)"' "$bashloop"
row 'hopx bash 3.2' '/bin/bash --norc --noprofile' 'eval "$(hopx init bash)"' "$bashloop"
row 'bare binary (no shell function)' 'zsh -f' ':' 'repeat @N@ { hopx eks security >/dev/null }'

# The containers time themselves with GNU date, since neither image has zsh.
local inner='
t() { s=$(date +%s%N); sh -c "$1" >/dev/null 2>&1 </dev/null; e=$(date +%s%N); echo $(( (e - s) / 1000 )); }
med() { sort -n | awk "{a[NR]=\$1} END {print a[int((NR+1)/2)]/1000}"; }
rep() { k=0; while [ $k -lt $1 ]; do t "$2"; k=$((k+1)); done | med; }
bare=$(rep '"$runs"' "$SH_BARE"); full=$(rep '"$runs"' "$SH_INIT")
j0=$(rep 5 "$SH_J0"); jn=$(rep 5 "$SH_JN")
awk -v l="$LABEL" -v b=$bare -v f=$full -v a=$j0 -v z=$jn -v n='"$n"' "BEGIN { printf \"%s\t%.1f\t%.1f\n\", l, (z - a) / n, f - b }"'
dock() {
	emulate -L zsh
	local image=$1
	shift
	docker run --rm -v "$root:/repo:ro" -v "$cfg:/cfg.toml:ro" -v "$tmp/linux:/hopxbin:ro" -w /repo \
		-e PATH=/hopxbin:/usr/local/bin:/usr/bin:/bin -e HOPX_CONFIG=/cfg.toml -e HOPX_HISTFILE=/tmp/hist -e TMPDIR=/tmp/ \
		"$@" "hopx-b3-$image" sh -c "$inner"
}
local fl='set i 0; while test $i -lt @N@; hopx eks security; cd /repo; set i (math $i + 1); end'
dock fish -e LABEL='hopx fish 3.7 (docker)' -e SH_BARE="fish -c :" -e SH_INIT="fish -c 'hopx init fish | source'" \
	-e SH_J0="fish -c 'hopx init fish | source; ${fl//@N@/0}'" -e SH_JN="fish -c 'hopx init fish | source; ${fl//@N@/$n}'"
local pl='for ($i = 0; $i -lt @N@; $i++) { hopx eks security; Set-Location /repo }'
local pi='Invoke-Expression (& hopx init pwsh | Out-String)'
dock pwsh -e LABEL='hopx pwsh 7.5 (docker)' -e SH_BARE="pwsh -NoProfile -Command 0" -e SH_INIT="pwsh -NoProfile -Command '$pi'" \
	-e SH_J0="pwsh -NoProfile -Command '$pi; ${pl//@N@/0}'" -e SH_JN="pwsh -NoProfile -Command '$pi; ${pl//@N@/$n}'"
local zl='i=0; while [ $i -lt @N@ ]; do hopx eks security >/dev/null; i=$((i+1)); done'
dock fish -e LABEL='bare binary (docker)' -e SH_BARE=":" -e SH_INIT=":" -e SH_J0="${zl//@N@/0}" -e SH_JN="${zl//@N@/$n}"
