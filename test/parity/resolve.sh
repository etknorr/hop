#!/usr/bin/env bash
# resolve.sh: the Go hop's resolver against zsh hop's on eval_real's five query sets, for HOP_JUMP auto, unique and never.
# - HOP_PARITY_HOME (a zsh hop install, the oracle) and HOP_PARITY_REPO (the repo to sweep) are required; HOP_PARITY_ZSHCONFIG
#   is the oracle's config.zsh (default zsh hop's own path) and HOP_PARITY_CONFIG the Go side's TOML (default testdata/eric.toml).
# - The last three sets are stress sets for the approximate tiers; the go/no-go bar reads only the first five.
# - core compares verdict, tier, rule and target rel; full compares the whole line: n, m, inj, every candidate, query, note, report.
# - The Go hop's layout follows the oracle's VERSION.
# - Each run is repeated with the modal layer on and off (PARITY_VIM, default "1 0"), since the T4 hint reads HOP_VIM.
# - Exit status is the number of core diffs on names, scope+env and name+env under auto, plus nonsense jumps, capped at 99.
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
# hop 0.3.0 fitted the columns to each list; against an older hop, the Go hop lays rows out the old way.
case $(cat "$hopdir/VERSION" 2>/dev/null) in
	0.1.* | 0.2.*) layout=fixed ;;
	*) layout=fit ;;
esac
jumps=${PARITY_JUMPS:-auto unique never}
vims=${PARITY_VIM:-1 0}
bin=${HOP_BIN:-}
out=$(mktemp -d "${TMPDIR:-/tmp}/hop-resolve.XXXXXX")
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
gclean() { clean HOP_HISTFILE="$out/hist" HOP_CONFIG="$gocfg" HOP_LAYOUT="$layout" "$@"; }

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

bad=0
printf '%-3s %-7s %-10s %7s %7s %7s %7s %6s %8s %8s\n' vim jump set queries same core full jumps zsh-s go-s
for vim in $vims; do
for jump in $jumps; do
	d=$out/vim$vim/$jump
	mkdir -p "$d"
	t0=$(now)
	zclean HOP_VIM="$vim" zsh -f "$here/resolve_dump.zsh" "$hopdir" "$root" "$d" "$jump" "$repo" || exit 98
	# hop 0.2's hint names esc whatever HOP_VIM says; the Go hop words it as hop 0.3 does.
	[ "$layout" = fixed ] && [ "$vim" = 0 ] && perl -pi -e 's/ \(esc clears\)\t/ (ctrl-u clears)\t/' "$d"/*.zsh
	[ "$layout" = fixed ] && [ "$vim" = 1 ] && perl -pi -e 's/ \(esc clears\)\t/ (esc twice clears)\t/' "$d"/*.zsh
	tz=$(echo "$(now) - $t0" | bc)
	for set in names pref3 scope+env name+env nonsense corpus typo relaxed; do
		t1=$(now)
		(cd "$root" && gclean HOP_VIM="$vim" "$bin" __resolve-dump --full --jump "$jump" <"$d/$set.q" >"$d/$set.go")
		tx=$(echo "$(now) - $t1" | bc)
		n=$(wc -l <"$d/$set.q" | tr -d ' ')
		core=$(paste "$d/$set.zsh" "$d/$set.go" | awk -F'\t' -v n=18 '{ for (i = 6; i <= 11; i++) if (i != 9 && i != 10 && $i != $(i + n)) { c++; break } } END { print c + 0 }')
		full=$(paste -d'\n' "$d/$set.zsh" "$d/$set.go" | awk 'NR % 2 { z = $0; next } $0 != z { c++ } END { print c + 0 }')
		same=$((n - full))
		js=$(awk -F'\t' '$6 == "jump" { c++ } END { print c + 0 }' "$d/$set.go")
		printf '%-3s %-7s %-10s %7s %7s %7s %7s %6s %8.1f %8.1f\n' "$vim" "$jump" "$set" "$n" "$same" "$core" "$full" "$js" "$tz" "$tx"
		if [ "$jump" = auto ]; then
			case $set in
				names | scope+env | name+env) bad=$((bad + core)) ;;
				nonsense) bad=$((bad + js)) ;;
			esac
		fi
		paste -d'\n' "$d/$set.zsh" "$d/$set.go" | awk -v s="vim$vim/$jump/$set" 'NR % 2 { z = $0; next } $0 != z { print s "\n  zsh  " z "\n  go   " $0 }' >>"$out/diffs"
	done
	tz=0
done
done
if [ -s "$out/diffs" ]; then
	echo
	echo "first diffs:"
	head -60 "$out/diffs"
fi
if [ -n "${PARITY_KEEP:-}" ]; then
	mkdir -p "$PARITY_KEEP" && cp -R "$out"/. "$PARITY_KEEP"/
fi
[ "$bad" -gt 99 ] && bad=99
exit "$bad"
