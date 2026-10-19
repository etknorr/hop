#!/usr/bin/env bash
# rows.sh [ROOT]: hopx rows against zsh hop's _hop_generate, per kind, for the default set, and for -w and -R.
# - Prints `kind rows-zsh rows-hopx IDENTICAL|DIFF first-diff-line set-diff`; set-diff counts ANSI-stripped rows in only one side.
# - The hop is the worktree's unless HOP_PARITY_HOME names another, such as ~/.local/share/hop; hopx's layout follows its VERSION.
# - Exit status is the number of DIFF lines, capped at 99.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
hopdir=${HOP_PARITY_HOME:-$repo}
# hop 0.3.0 fitted the columns to each list; against an older hop, hopx lays rows out the old way.
case $(cat "$hopdir/VERSION" 2>/dev/null) in
	0.1.* | 0.2.*) layout=fixed ;;
	*) layout=fit ;;
esac
root=${1:-${HOPX_PARITY_REPO:-$HOME/strava/configuration}}
hopcfg=${HOP_PARITY_CONFIG:-$HOME/.config/hop/config.zsh}
hopxcfg=${HOPX_PARITY_CONFIG:-$repo/testdata/eric.toml}
bin=${HOPX_BIN:-}
out=$(mktemp -d "${TMPDIR:-/tmp}/hopx-parity.XXXXXX")
trap 'rm -rf "$out"' EXIT

if [ -z "$bin" ]; then
	bin=$out/hopx
	(cd "$repo" && go build -o "$bin" .) || exit 99
fi

clean() {
	env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" HOPX_LAYOUT="$layout" \
		HOP_HISTFILE=/dev/null HOPX_HISTFILE="$out/hist" XDG_CACHE_HOME="$out/cache" "$@"
}

zhop() {
	clean HOP_CONFIG="$hopcfg" zsh -f -c '
		source "$1/hop.zsh" || exit 3
		shift
		case $1 in
			-w) _hop_provider_ws ;;
			-R) _hop_repo_targets; print -r -- "$REPLY" ;;
			-d) shift; _hop_generate "$1" ${=HOP_DEFAULT_KINDS} ;;
			*) _hop_generate "$@" ;;
		esac' hop "$hopdir" "$@"
}

xhop() {
	clean HOPX_CONFIG="$hopxcfg" "$bin" "$@"
}

strip() { sed $'s/\x1b\\[[0-9;]*m//g' "$1" | LC_ALL=C sort; }

diffs=0
check() {
	local name=$1 z=$out/$1.zsh x=$out/$1.hopx nz nx verdict first sd
	nz=$(wc -l <"$z" | tr -d ' ')
	nx=$(wc -l <"$x" | tr -d ' ')
	if cmp -s "$z" "$x"; then
		verdict=IDENTICAL first=-
	else
		verdict=DIFF
		diffs=$((diffs + 1))
		first=$(cmp "$z" "$x" 2>&1 | sed -n 's/.* line \([0-9]*\).*/\1/p')
		[ -n "$first" ] || first=eof
	fi
	sd=$(LC_ALL=C comm -3 <(strip "$z") <(strip "$x") | wc -l | tr -d ' ')
	printf '%-10s %6s %6s %-9s %-6s %s\n' "$name" "$nz" "$nx" "$verdict" "$first" "$sd"
}

printf '%-10s %6s %6s %-9s %-6s %s\n' kind zsh hopx verdict first set-diff
kinds=$(xhop kinds | cut -c3- | awk '{print $1}')
for k in $kinds; do
	zhop "$root" "$k" >"$out/$k.zsh" 2>"$out/$k.zsh.err"
	xhop __rows "$root" "$k" >"$out/$k.hopx" 2>"$out/$k.hopx.err"
	check "$k"
done
zhop -d "$root" >"$out/default.zsh" 2>/dev/null
xhop rows --root "$root" >"$out/default.hopx" 2>/dev/null
check default
zhop -w >"$out/ws.zsh" 2>/dev/null
xhop rows -w >"$out/ws.hopx" 2>/dev/null
check ws
zhop -R >"$out/repo.zsh" 2>/dev/null
xhop rows -R >"$out/repo.hopx" 2>/dev/null
check repo

if [ -n "${PARITY_KEEP:-}" ]; then
	mkdir -p "$PARITY_KEEP" && cp "$out"/*.zsh "$out"/*.hopx "$PARITY_KEEP"/
fi
[ "$diffs" -gt 99 ] && diffs=99
exit "$diffs"
