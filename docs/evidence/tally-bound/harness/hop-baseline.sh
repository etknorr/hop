#!/bin/zsh
# Full-suite baseline on both trees, plus a tripwire on the marker counter used in the #59 proof.
#
# - The delta must be zero: with no bound kill there is no missing sentinel, so nothing is counted.
# - That is the check that parent-side counting does NOT fire on a normal run and double-count.

emulate -L zsh
setopt no_nomatch

OUTDIR=/private/tmp/hop-proof59-out
mkdir -p $OUTDIR

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

print -r -- '### tripwire: the counter must NOT always answer 15'
print -r -- 'empty file            -> '"$(count_markers /dev/null)"
printf '  \xe2\x9c\x93 one\n  \xe2\x9c\x93 two\n' > $OUTDIR/tw2.txt
print -r -- 'file with 2 passes    -> '"$(count_markers $OUTDIR/tw2.txt)"
printf '      \xe2\x9c\x93 indented six\n' > $OUTDIR/tw6.txt
print -r -- 'six-space detail line -> '"$(count_markers $OUTDIR/tw6.txt)"
print -r -- ''

print -r -- '### full suite, both trees, default bound'
for tree in /private/tmp/hop-wt-tally-base /private/tmp/hop-wt-tally-reap; do
  label=${tree:t}
  out=$OUTDIR/full.${label}.txt
  la_before=$(sysctl -n vm.loadavg)
  s=$EPOCHREALTIME
  HOP_T_REAP_HOURS=0 zsh $tree/tests/run > $out 2>&1
  st=$?
  e=$EPOCHREALTIME
  printf 'TREE=%s exit=%d wall=%.2fs\n' $label $st $(( e - s ))
  print -r -- "  loadavg before: ${la_before}   after: $(sysctl -n vm.loadavg)"
  print -r -- "  summary: $(perl -ne 'print if /passed,/' $out | tr -d '\n')"
  print -r -- "  visible markers: $(count_markers $out)"
  print -r -- ''
done

print -r -- '### tally lines differ only where expected'
diff <(perl -ne 'print if /passed,/' $OUTDIR/full.hop-wt-tally-base.txt) \
     <(perl -ne 'print if /passed,/' $OUTDIR/full.hop-wt-tally-reap.txt) \
  && print -r -- '  IDENTICAL summary lines'
