#!/usr/bin/env bash
# rows.sh: the Go hop's rows against zsh hop's _hop_generate, per kind, for the default set, and for -w and -R.
# - HOP_PARITY_HOME (a zsh hop install, the oracle) and HOP_PARITY_REPO (the repo to sweep) are required; HOP_PARITY_ZSHCONFIG
#   is the oracle's config.zsh (default zsh hop's own path) and HOP_PARITY_CONFIG the Go side's TOML (default testdata/eric.toml).
# - Prints `kind rows-zsh rows-go IDENTICAL|DIFF first-diff-line set-diff`; set-diff counts ANSI-stripped rows in only one side.
# - Exit status is the number of DIFF lines, capped at 99.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
if [ -z "${HOP_PARITY_HOME:-}" ] || [ -z "${HOP_PARITY_REPO:-}" ]; then
	echo "usage: HOP_PARITY_HOME=<zsh hop dir> HOP_PARITY_REPO=<repo> [HOP_PARITY_ZSHCONFIG=<config.zsh>] [HOP_PARITY_CONFIG=<config.toml>] $0" >&2
	exit 2
fi
root=$HOP_PARITY_REPO
zshcfg=${HOP_PARITY_ZSHCONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hop/config.zsh}
gocfg=${HOP_PARITY_CONFIG:-$repo/testdata/eric.toml}
hopdir=$HOP_PARITY_HOME
bin=${HOP_BIN:-}
out=$(mktemp -d "${TMPDIR:-/tmp}/hop-parity.XXXXXX")
trap 'rm -rf "$out"' EXIT

if [ -z "$bin" ]; then
	bin=$out/hop
	(cd "$repo" && go build -o "$bin" .) || exit 99
fi

clean() {
	env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" XDG_CACHE_HOME="$out/cache" "$@"
}

# HOP_CONFIG and HOP_HISTFILE name different files to the two hops, so each side sets its own.
zclean() { clean HOP_HISTFILE=/dev/null HOP_CONFIG="$zshcfg" "$@"; }
gclean() { clean HOP_HISTFILE="$out/hist" HOP_CONFIG="$gocfg" "$@"; }

zhop() {
	zclean zsh -f -c '
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
	gclean "$bin" "$@"
}

strip() { sed $'s/\x1b\\[[0-9;]*m//g' "$1" | LC_ALL=C sort; }

diffs=0
check() {
	local name=$1 z=$out/$1.zsh x=$out/$1.go nz nx verdict first sd
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

printf '%-10s %6s %6s %-9s %-6s %s\n' kind zsh go verdict first set-diff
kinds=$(xhop __kinds | cut -c3- | awk '{print $1}')
for k in $kinds; do
	zhop "$root" "$k" >"$out/$k.zsh" 2>"$out/$k.zsh.err"
	xhop __rows "$root" "$k" >"$out/$k.go" 2>"$out/$k.go.err"
	check "$k"
done
zhop -d "$root" >"$out/default.zsh" 2>/dev/null
xhop __dump-rows --root "$root" >"$out/default.go" 2>/dev/null
check default
zhop -w >"$out/ws.zsh" 2>/dev/null
xhop __dump-rows -w >"$out/ws.go" 2>/dev/null
check ws
zhop -R >"$out/repo.zsh" 2>/dev/null
xhop __dump-rows -R >"$out/repo.go" 2>/dev/null
check repo

if [ -n "${PARITY_KEEP:-}" ]; then
	mkdir -p "$PARITY_KEEP" && cp "$out"/*.zsh "$out"/*.go "$PARITY_KEEP"/
fi
[ "$diffs" -gt 99 ] && diffs=99
exit "$diffs"
