#!/bin/zsh
# Prove #59: a bound-killed suite's already-printed markers survive into the tally.
#
# - Runs one suite under a tiny bound, per tree and per colour mode.
# - Counts the output's marker lines INDEPENDENTLY of the runner's own tally, then compares.
# - Colour-on needs a real pty, because the runner derives HOP_T_COLOR from [[ -t 1 ]].

emulate -L zsh
setopt no_nomatch

SUITE=${SUITE:-suite_core}
BOUND=${BOUND:-5}
OUTDIR=/private/tmp/hop-proof59-out
mkdir -p $OUTDIR

# count_markers <file> -> prints "pass fail skip", tolerating a colour prefix on the glyph.
count_markers() {
  perl -CSD -ne '
    s/\r$//;
    next unless s/^  //;
    s/^(?:\e\[[0-9;]*m)+//;
    $p++ if /^\x{2713}/;
    $f++ if /^\x{2717}/;
    $s++ if /^-/;
    END { printf "%d %d %d\n", $p||0, $f||0, $s||0 }
  ' "$1"
}

# reported <file> -> prints "pass fail" as the runner's own summary line stated it.
reported() {
  perl -ne 's/\r$//; if (/(\d+) passed, (\d+) failed/) { print "$1 $2\n"; exit }' "$1"
}

for tree in /private/tmp/hop-wt-tally-base /private/tmp/hop-wt-tally-reap; do
  label=${tree:t}
  for mode in nocolor color; do
    out=$OUTDIR/${label}.${mode}.txt
    if [[ $mode == color ]]; then
      HOP_T_TIMEOUT=$BOUND HOP_T_REAP_HOURS=0 \
        script -q /dev/null zsh $tree/tests/run $SUITE > $out 2>&1
    else
      HOP_T_TIMEOUT=$BOUND HOP_T_REAP_HOURS=0 \
        zsh $tree/tests/run $SUITE > $out 2>&1
    fi
    st=$?
    esc=$(perl -ne 'BEGIN{$n=0} $n++ while /\e\[/g; END{print $n+0}' $out)
    print -r -- "TREE=${label} MODE=${mode} exit=${st} escapes_in_output=${esc}"
    print -r -- "  visible markers (counted by this script): $(count_markers $out)"
    print -r -- "  runner reported (pass fail)             : $(reported $out)"
    print -r -- "  summary line: $(perl -ne 's/\r$//; print if /passed,/' $out | tr -d '\n')"
    print -r -- ''
  done
done
print -r -- "loadavg now: $(sysctl -n vm.loadavg)"
