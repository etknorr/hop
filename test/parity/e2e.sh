#!/usr/bin/env bash
# e2e.sh: the Go hop against zsh hop end to end, through each one's shell function, over eval_real's query sets and two more.
# - HOP_PARITY_HOME (a zsh hop install, the oracle) and HOP_PARITY_REPO (the repo to sweep) are required; HOP_PARITY_ZSHCONFIG
#   is the oracle's config.zsh (default zsh hop's own path) and HOP_PARITY_CONFIG the Go side's TOML (default testdata/eric.toml).
# - The sets are built by that hop from its own rows (sets.zsh), so they are what its eval_real would sweep.
# - A verdict is jump (the function cd'd), pick (N matched), none (nothing matched) or rc<N>.
# - The target is the landing dir for a jump and the "best matches" line for a pick; agree means verdict and target match.
# - text counts agreeing queries whose rc, remembered dir or any byte of stderr still differ.
# - Both run headless: hop's _hop_tty_ok is stubbed, and every shard runs in a new session, so neither can open /dev/tty.
# - v03 and away are hand-written, for what hop 0.3.0 changed: v03 has kind words, paths and clipped names.
# - away is paths into other repos, typed from ~; its @REPO@ is HOP_PARITY_REPO written with ~.
# - Each run is repeated with the modal layer on and off (PARITY_VIM, default "1 0"), which the T4 hint in a report reads.
# - Exit status is the number of queries that disagree under auto, capped at 99.
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
jumps=${PARITY_JUMPS:-auto unique never}
vims=${PARITY_VIM:-1 0}
workers=${PARITY_WORKERS:-8}
sets="names pref3 scope+env name+env nonsense v03 away"
bin=${HOP_BIN:-}
out=$(mktemp -d "${TMPDIR:-/tmp}/hop-e2e.XXXXXX")
trap 'rm -rf "$out"' EXIT

if [ -z "$bin" ]; then
	mkdir -p "$out/bin"
	bin=$out/bin/hop
	(cd "$repo" && go build -o "$bin" .) || exit 99
fi

clean() {
	env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" "$@"
}

detached() {
	perl -MPOSIX -e 'if (my $p = fork) { waitpid($p, 0); exit($? >> 8) } POSIX::setsid(); exec @ARGV or die "exec: $!"' -- "$@"
}

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

clean HOP_HISTFILE=/dev/null HOP_CONFIG="$zshcfg" zsh -f "$here/sets.zsh" "$hophome" "$root" "$out" || exit 98
cp "$here/corpus/v03.q" "$out"/
TILDE=${root/#$HOME/\~} perl -pe 's/\@REPO\@/$ENV{TILDE}/g' "$here/corpus/away.q" >"$out/away.q"
for set in $sets; do
	from=
	[ "$set" = away ] && from=$HOME
	awk -v s="$set" -v from="$from" '{ print s "\t" $0 (from == "" ? "" : "\t" from) }' "$out/$set.q"
done >"$out/all.cases"
awk -v n="$workers" -v o="$out/shard." '{ printf "%s\n", $0 > (o sprintf("%02d", (NR - 1) % n)) }' "$out/all.cases"

# verdict and target per line of e2e_run.zsh's output: set, query, rc, landing, remembered, ms, stderr.
classify='
function verdict(rc, land, err) {
	if (land != "-") return "jump"
	if (err ~ /matched the query/ || err ~ /target matched/ || err ~ /targets matched/) return "pick"
	if (err ~ /nothing matched/) return "none"
	return "rc" rc
}
function target(v, land, err,   b) {
	if (v == "jump") return land
	if (v != "pick") return ""
	b = err
	if (!sub(/.*hop: best matches: /, "", b)) return ""
	sub(/\\n.*/, "", b)
	return b
}'

bad=0
: >"$out/diffs"
printf '%-3s %-7s %-10s %7s %7s %6s %6s %6s %6s %9s %9s\n' vim jump set queries agree diff text zsh-j go-j zsh-ms go-ms
for vim in $vims; do
for jump in $jumps; do
	d=$out/vim$vim/$jump
	mkdir -p "$d"
	t0=$(now)
	for s in "$out"/shard.*; do
		n=${s##*.}
		detached env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" HOP_JUMP="$jump" HOP_VIM="$vim" \
			HOP_CONFIG="$zshcfg" zsh -f "$here/e2e_run.zsh" zsh "$hophome" "$root" "$s" "$d/zsh.$n" &
		detached env -i HOME="$HOME" PATH="$PATH" LANG="${LANG:-en_US.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" HOP_JUMP="$jump" HOP_VIM="$vim" \
			HOP_CONFIG="$gocfg" zsh -f "$here/e2e_run.zsh" go "$bin" "$root" "$s" "$d/go.$n" &
	done
	wait
	echo "(vim $vim, $jump: $(echo "$(now) - $t0" | bc)s wall for $(wc -l <"$out/all.cases" | tr -d ' ') queries x 2, $workers shards each)" >&2
	cat "$d"/zsh.* >"$d/zsh.tsv"
	cat "$d"/go.* >"$d/go.tsv"
	for set in $sets; do
		awk -F'\t' -v OFS='\t' -v s="$set" -v j="$jump" -v vim="$vim" -v diffs="$out/diffs" "$classify"'
			function med(a, n,   i, k, t) {
				for (i = 2; i <= n; i++) { t = a[i]; for (k = i - 1; k >= 1 && a[k] > t; k--) a[k + 1] = a[k]; a[k + 1] = t }
				return n ? a[int((n + 1) / 2)] : 0
			}
			FNR == 1 { f++ }
			$1 != s { next }
			f == 1 { rc[$2] = $3; land[$2] = $4; mem[$2] = $5; err[$2] = $7; hz[++nz] = $6; next }
			{
				n++
				hx[++nx] = $6
				vz = verdict(rc[$2], land[$2], err[$2]); tz = target(vz, land[$2], err[$2])
				vx = verdict($3, $4, $7); tx = target(vx, $4, $7)
				if (vz == "jump") jz++
				if (vx == "jump") jx++
				if (vz == vx && tz == tx) {
					agree++
					if (rc[$2] != $3 || mem[$2] != $5 || err[$2] != $7) text++
				} else {
					print "vim" vim " " j, s, $2, vz, tz, vx, tx, err[$2], $7 >> diffs
				}
			}
			END {
				printf "%-3s %-7s %-10s %7d %7d %6d %6d %6d %6d %9.1f %9.1f\n", vim, j, s, n, agree, n - agree, text, jz, jx, med(hz, nz), med(hx, nx)
			}' "$d/zsh.tsv" "$d/go.tsv"
	done
done
done | tee "$out/table"
bad=$(awk '$2 == "auto" { s += $6 } END { print s + 0 }' "$out/table")

if [ -s "$out/diffs" ]; then
	echo
	echo "disagreements (jump set query: zsh verdict target | go verdict target):"
	awk -F'\t' '{ printf "%s %s %s: zsh %s %s | go %s %s\n", $1, $2, $3, $4, ($5 == "" ? "-" : $5), $6, ($7 == "" ? "-" : $7) }' "$out/diffs"
fi
if [ -n "${PARITY_KEEP:-}" ]; then
	mkdir -p "$PARITY_KEEP" && cp -R "$out"/. "$PARITY_KEEP"/
fi
[ "$bad" -gt 99 ] && bad=99
exit "$bad"
