#!/usr/bin/env bash
# perf.sh: the Go hop against zsh hop for speed: enumeration, resolve per tier, and end to end through the shell function.
# - HOP_PARITY_HOME (a zsh hop install, the oracle) and HOP_PARITY_REPO (the repo to sweep) are required; HOP_PARITY_ZSHCONFIG
#   is the oracle's config.zsh (default zsh hop's own path) and HOP_PARITY_CONFIG the Go side's TOML (default testdata/eric.toml).
# - Enumeration: go is a whole `hop rows` process; zsh is _hop_rows in an already-sourced shell, which is what hop() pays.
# - Resolve: per query, T0 first, enumeration excluded; zsh's in one sourced shell, go's from __resolve-dump --ms.
# - End to end: every PERF_EVERY-th query of each set, plus e2e.sh's v03 and away, serially and headless through both functions.
# - The Go hop's layout follows the oracle's VERSION, as in e2e.sh.
# - Medians and p90s; the machine is shared, so read the ratios rather than the absolute times.
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
hophome=$HOP_PARITY_HOME
runs=${PERF_RUNS:-15}
every=${PERF_EVERY:-10}
case $(cat "$hophome/VERSION" 2>/dev/null) in
	0.1.* | 0.2.*) layout=fixed ;;
	*) layout=fit ;;
esac
sets="names pref3 scope+env name+env nonsense corpus typo relaxed"
out=$(mktemp -d "${TMPDIR:-/tmp}/hop-perf.XXXXXX")
trap 'rm -rf "$out"' EXIT
bin=${HOP_BIN:-}
if [ -z "$bin" ]; then
	mkdir -p "$out/bin"
	bin=$out/bin/hop
	(cd "$repo" && go build -o "$bin" .) || exit 99
fi

clean() {
	env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" XDG_CACHE_HOME="$out/cache" "$@"
}

# HOP_CONFIG and HOP_HISTFILE name different files to the two hops, so each side sets its own.
zclean() { clean HOP_HISTFILE=/dev/null HOP_CONFIG="$zshcfg" "$@"; }
gclean() { clean HOP_HISTFILE="$out/hist" HOP_CONFIG="$gocfg" HOP_LAYOUT="$layout" "$@"; }

detached() {
	perl -MPOSIX -e 'if (my $p = fork) { waitpid($p, 0); exit($? >> 8) } POSIX::setsid(); exec @ARGV or die "exec: $!"' -- "$@"
}

now_ms() { perl -MTime::HiRes=time -e 'printf "%.3f", time * 1000'; }

# stats <col>: count, median and p90 of a numeric column on stdin.
stats() {
	sort -n | awk '{ v[NR] = $1 } END { if (!NR) { print "0 - -"; exit } printf "%d %.1f %.1f\n", NR, v[int((NR + 1) / 2)], v[int(NR * 0.9 + 0.999)] }'
}

zclean zsh -f "$here/sets.zsh" "$hophome" "$root" "$out" stress || exit 98

echo "== enumeration (median of $runs, ms)"
printf '%-8s %6s %9s %9s %9s\n' set rows go zsh zsh-fresh
zclean zsh -f "$here/perf_zsh.zsh" "$hophome" "$root" rows "$runs" >"$out/rows.zsh" || exit 97
for set in default file; do
	k=()
	[ "$set" = file ] && k=(-k file)
	: >"$out/x" && : >"$out/f"
	for _ in $(seq "$runs"); do
		t0=$(now_ms)
		gclean "$bin" rows "${k[@]}" --root "$root" >/dev/null 2>&1
		echo "$(now_ms) - $t0" | bc >>"$out/x"
		t0=$(now_ms)
		if [ "$set" = file ]; then
			zclean zsh -f -c 'source "$1/hop.zsh"; _hop_rows "$2" "" file' zsh "$hophome" "$root" >/dev/null 2>&1
		else
			zclean zsh -f -c 'source "$1/hop.zsh"; _hop_rows "$2" "" ${=HOP_DEFAULT_KINDS//,/ }' zsh "$hophome" "$root" >/dev/null 2>&1
		fi
		echo "$(now_ms) - $t0" | bc >>"$out/f"
	done
	read -r _ xm _ < <(stats <"$out/x")
	read -r _ fm _ < <(stats <"$out/f")
	read -r _ zn zm < <(awk -v s="$set" '$1 == s' "$out/rows.zsh")
	printf '%-8s %6s %9s %9s %9s\n' "$set" "$zn" "$xm" "$zm" "$fm"
done

echo
echo "== resolve per tier, auto (ms per query, enumeration excluded)"
qfiles=()
for set in $sets; do qfiles+=("$out/$set.q"); done
zclean HOP_VIM=0 zsh -f "$here/perf_zsh.zsh" "$hophome" "$root" resolve auto "${qfiles[@]}" >"$out/res.zsh" || exit 96
for set in $sets; do
	(cd "$root" && gclean "$bin" __resolve-dump --ms --jump auto <"$out/$set.q") |
		awk -F'\t' -v OFS='\t' -v s="$set" '{ print s, $1, ($3 == "" ? "-" : $3), $7 }'
done >"$out/res.go"
printf '%-8s %6s %9s %9s %9s %9s %7s\n' tier queries go-med go-p90 zsh-med zsh-p90 ratio
for tier in $(cut -f3 "$out/res.zsh" "$out/res.go" | sort -u) all; do
	if [ "$tier" = all ]; then
		read -r n xm xp < <(cut -f4 "$out/res.go" | stats)
		read -r _ zm zp < <(cut -f4 "$out/res.zsh" | stats)
	else
		read -r n xm xp < <(awk -F'\t' -v t="$tier" '$3 == t { print $4 }' "$out/res.go" | stats)
		read -r _ zm zp < <(awk -F'\t' -v t="$tier" '$3 == t { print $4 }' "$out/res.zsh" | stats)
	fi
	ratio=$(awk -v z="$zm" -v x="$xm" 'BEGIN { if (x + 0 > 0 && z + 0 > 0) printf "%.1fx", z / x; else print "-" }')
	printf '%-8s %6s %9s %9s %9s %9s %7s\n' "$tier" "$n" "$xm" "$xp" "$zm" "$zp" "$ratio"
done
tiers=$(paste <(cut -f1-3 "$out/res.zsh") <(cut -f1-3 "$out/res.go") | awk -F'\t' '$3 != $6 { c++ } END { print c + 0 }')
echo "(tier differs between zsh and go on $tiers of $(wc -l <"$out/res.go" | tr -d ' ') queries)"

echo
echo "== end to end through the shell function, auto, every ${every}th query (wall ms per call)"
{
	for set in $sets; do
		awk -v s="$set" -v n="$every" 'NR % n == 1 { print s "\t" $0 }' "$out/$set.q"
	done
	awk '{ print "v03\t" $0 }' "$here/corpus/v03.q"
	awk -v h="$HOME" '{ print "away\t" $0 "\t" h }' "$here/corpus/away.q"
} >"$out/e2e.cases"
detached env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" HOP_JUMP=auto \
	HOP_CONFIG="$zshcfg" zsh -f "$here/e2e_run.zsh" zsh "$hophome" "$root" "$out/e2e.cases" "$out/e2e.zsh"
detached env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" HOP_JUMP=auto \
	HOP_LAYOUT="$layout" HOP_CONFIG="$gocfg" zsh -f "$here/e2e_run.zsh" go "$bin" "$root" "$out/e2e.cases" "$out/e2e.go"
printf '%-10s %6s %9s %9s %9s %9s %7s\n' group calls go-med go-p90 zsh-med zsh-p90 ratio
row() {
	local name=$1 filter=$2 n xm xp zm zp ratio
	read -r n xm xp < <(awk -F'\t' "$filter { print \$6 }" "$out/e2e.go" | stats)
	read -r _ zm zp < <(awk -F'\t' "$filter { print \$6 }" "$out/e2e.zsh" | stats)
	ratio=$(awk -v z="$zm" -v x="$xm" 'BEGIN { if (x + 0 > 0 && z + 0 > 0) printf "%.1fx", z / x; else print "-" }')
	printf '%-10s %6s %9s %9s %9s %9s %7s\n' "$name" "$n" "$xm" "$xp" "$zm" "$zp" "$ratio"
}
for set in $sets v03 away; do row "$set" "\$1 == \"$set\""; done
row jump '$4 != "-"'
row no-jump '$4 == "-"'
row all 1
if [ -n "${PARITY_KEEP:-}" ]; then
	mkdir -p "$PARITY_KEEP" && cp -R "$out"/. "$PARITY_KEEP"/
fi
