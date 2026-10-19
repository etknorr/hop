# cd.fish: cd.sh for fish, sourced after `hop init fish | source`, with no terminal.
set R $HOP_T/repo
function check
	if test "$PWD" = "$argv[2]"
		echo "PASS $argv[1]"
	else
		echo "FAIL $argv[1]: PWD=$PWD want=$argv[2]"
	end
end
cd $R; hop ./plain; check t0-plain "$R/plain"
cd $R; hop './with space'; check t0-space "$R/with space"
cd $R; hop './trail-space-backslash\ '; check t0-trail-space-backslash "$R/trail-space-backslash\\ "
cd $R; hop ./café; check t0-unicode "$R/café"
cd $R; hop ./nl\nx; check t0-newline $R/nl\nx
cd $R; hop './brack[1]'; check t0-bracket "$R/brack[1]"
cd $R; hop gamma; check resolve-jump "$R/beta/gamma"
cd $R; hop with space; check resolve-two-words "$R/with space"
cd $R; hop brack; check resolve-bracket "$R/brack[1]"
cd $R/beta/gamma; hop /; check slash "$R"
cd $R; hop alpha; hop - >/dev/null; check dash "$R"
cd $R; hop zzqx-nothing 2>/dev/null; set rc $status
if test $rc = 1 -a "$PWD" = "$R"; echo "PASS no-match-rc1"; else; echo "FAIL no-match-rc1 rc=$rc"; end
cd $R; hop -Z 2>/dev/null; set rc $status
if test $rc = 2; echo "PASS usage-rc2"; else; echo "FAIL usage-rc2 rc=$rc"; end
cd $R; HOP_CODE=$HOP_T/stub/code-fail hop --action=cd+open alpha 2>/dev/null; set rc $status
if test $rc = 3 -a "$PWD" = "$R/alpha"; echo "PASS cd-then-fail"; else; echo "FAIL cd-then-fail rc=$rc PWD=$PWD"; end
cd $R; set d (command hop gamma)
if test "$d" = "$R/beta/gamma" -a "$PWD" = "$R"; echo "PASS bare-binary-prints"; else; echo "FAIL bare-binary-prints d=$d"; end
set n (hop -h | grep -c '^usage: hop')
if test "$n" = 1; echo "PASS stdout-pipe"; else; echo "FAIL stdout-pipe n=$n"; end
set left (count $TMPDIR/hop.*)
if test $left = 0; echo "PASS no-cmdfile-left"; else; echo "FAIL no-cmdfile-left $left"; end
if head -1 $HOP_HISTFILE | grep -q '/beta/gamma$'; and grep -q '/alpha$' $HOP_HISTFILE; echo "PASS mru"; else; echo "FAIL mru"; end
if set -q HOP_CMDFILE; echo "FAIL env-clean HOP_CMDFILE leaked"; else; echo "PASS env-clean"; end
# cd - only works through fish's cd function, which is why the init never uses builtin cd.
cd $R; builtin cd $R/alpha; cd - 2>/dev/null
if test "$PWD" = "$R"; echo "INFO builtin cd keeps cd -: yes"; else; echo "INFO builtin cd keeps cd -: no"; end
