#!/usr/bin/env bash
# resolve.sh [ROOT]: hopx's resolver against zsh hop's on eval_real's five query sets, for HOP_JUMP auto, unique and never.
# - The last three sets are stress sets for the approximate tiers; the go/no-go bar reads only the first five.
# - core compares verdict, tier, rule and target rel; full compares the whole line: n, m, inj, every candidate, query, note, report.
# - The hop is the worktree's unless HOP_PARITY_HOME names another, such as ~/.local/share/hop; hopx's layout follows its VERSION.
# - Exit status is the number of core diffs on names, scope+env and name+env under auto, plus nonsense jumps, capped at 99.
set -u
here=$(cd "$(dirname "$0")" && pwd)
spike=$(dirname "$here")
hopdir=${HOP_PARITY_HOME:-$(dirname "$spike")}
# hop 0.3.0 fitted the columns to each list; against an older hop, hopx lays rows out the old way.
case $(cat "$hopdir/VERSION" 2>/dev/null) in
	0.1.* | 0.2.*) layout=fixed ;;
	*) layout=fit ;;
esac
root=${1:-${HOPX_PARITY_REPO:-$HOME/strava/configuration}}
hopcfg=${HOP_PARITY_CONFIG:-$HOME/.config/hop/config.zsh}
hopxcfg=${HOPX_PARITY_CONFIG:-$spike/hopx/testdata/eric.toml}
jumps=${PARITY_JUMPS:-auto unique never}
bin=${HOPX_BIN:-}
out=$(mktemp -d "${TMPDIR:-/tmp}/hopx-resolve.XXXXXX")
trap 'rm -rf "$out"' EXIT

if [ -z "$bin" ]; then
	bin=$out/hopx
	(cd "$spike/hopx" && go build -o "$bin" .) || exit 99
fi

clean() {
	env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" HOPX_LAYOUT="$layout" \
		HOP_HISTFILE=/dev/null HOPX_HISTFILE="$out/hist" XDG_CACHE_HOME="$out/cache" "$@"
}

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

bad=0
printf '%-7s %-10s %7s %7s %7s %7s %6s %8s %8s\n' jump set queries same core full jumps zsh-s hopx-s
for jump in $jumps; do
	d=$out/$jump
	mkdir -p "$d"
	t0=$(now)
	# hopx has no modal layer, so the hop it is held to is HOP_VIM=0; only the T4 hint reads it.
	clean HOP_CONFIG="$hopcfg" HOP_VIM=0 zsh -f "$here/resolve_dump.zsh" "$hopdir" "$root" "$d" "$jump" "$spike" || exit 98
	# hop 0.2's hint names esc whatever HOP_VIM says; hopx words it as hop 0.3 does with no modal layer.
	[ "$layout" = fixed ] && perl -pi -e 's/ \(esc clears\)\t/ (ctrl-u clears)\t/' "$d"/*.zsh
	tz=$(echo "$(now) - $t0" | bc)
	for set in names pref3 scope+env name+env nonsense corpus typo relaxed; do
		t1=$(now)
		(cd "$root" && clean HOPX_CONFIG="$hopxcfg" "$bin" __resolve-dump --full --jump "$jump" <"$d/$set.q" >"$d/$set.hopx")
		tx=$(echo "$(now) - $t1" | bc)
		n=$(wc -l <"$d/$set.q" | tr -d ' ')
		core=$(paste "$d/$set.zsh" "$d/$set.hopx" | awk -F'\t' -v n=18 '{ for (i = 6; i <= 11; i++) if (i != 9 && i != 10 && $i != $(i + n)) { c++; break } } END { print c + 0 }')
		full=$(paste -d'\n' "$d/$set.zsh" "$d/$set.hopx" | awk 'NR % 2 { z = $0; next } $0 != z { c++ } END { print c + 0 }')
		same=$((n - full))
		js=$(awk -F'\t' '$6 == "jump" { c++ } END { print c + 0 }' "$d/$set.hopx")
		printf '%-7s %-10s %7s %7s %7s %7s %6s %8.1f %8.1f\n' "$jump" "$set" "$n" "$same" "$core" "$full" "$js" "$tz" "$tx"
		if [ "$jump" = auto ]; then
			case $set in
				names | scope+env | name+env) bad=$((bad + core)) ;;
				nonsense) bad=$((bad + js)) ;;
			esac
		fi
		paste -d'\n' "$d/$set.zsh" "$d/$set.hopx" | awk -v s="$jump/$set" 'NR % 2 { z = $0; next } $0 != z { print s "\n  zsh  " z "\n  hopx " $0 }' >>"$out/diffs"
	done
	tz=0
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
