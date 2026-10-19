# cd.sh: sourced by zsh, bash 5 and bash 3.2 after `hop init`, with no terminal; one PASS or FAIL line per case.
R=$HOP_T/repo
check() {
	if [ "$PWD" = "$2" ]; then
		echo "PASS $1"
	else
		echo "FAIL $1: PWD=$PWD want=$2"
	fi
}
nl=$(printf 'nl\nx')
cd "$R"; hop ./plain; check t0-plain "$R/plain"
cd "$R"; hop './with space'; check t0-space "$R/with space"
cd "$R"; hop './trail-space-backslash\ '; check t0-trail-space-backslash "$R/trail-space-backslash\\ "
cd "$R"; hop ./café; check t0-unicode "$R/café"
cd "$R"; hop "./$nl"; check t0-newline "$R/$nl"
cd "$R"; hop './brack[1]'; check t0-bracket "$R/brack[1]"
cd "$R"; hop gamma; check resolve-jump "$R/beta/gamma"
cd "$R"; hop with space; check resolve-two-words "$R/with space"
cd "$R"; hop brack; check resolve-bracket "$R/brack[1]"
cd "$R/beta/gamma"; hop /; check slash "$R"
cd "$R"; hop alpha; hop - >/dev/null; check dash "$R"
cd "$R"; hop zzqx-nothing 2>/dev/null; rc=$?
if [ "$rc" = 1 ] && [ "$PWD" = "$R" ]; then echo "PASS no-match-rc1"; else echo "FAIL no-match-rc1 rc=$rc PWD=$PWD"; fi
cd "$R"; hop -Z 2>/dev/null; rc=$?
if [ "$rc" = 2 ]; then echo "PASS usage-rc2"; else echo "FAIL usage-rc2 rc=$rc"; fi
cd "$R"; HOP_CODE="$HOP_T/stub/code-fail" hop --action=cd+open alpha 2>/dev/null; rc=$?
if [ "$rc" = 3 ] && [ "$PWD" = "$R/alpha" ]; then echo "PASS cd-then-fail"; else echo "FAIL cd-then-fail rc=$rc PWD=$PWD"; fi
cd "$R"; d=$(command hop gamma)
if [ "$d" = "$R/beta/gamma" ] && [ "$PWD" = "$R" ]; then echo "PASS bare-binary-prints"; else echo "FAIL bare-binary-prints d=$d"; fi
n=$(hop -h | grep -c '^usage: hop')
if [ "$n" = 1 ]; then echo "PASS stdout-pipe"; else echo "FAIL stdout-pipe n=$n"; fi
left=$(ls "$TMPDIR" | grep -c '^hop\.')
if [ "$left" = 0 ]; then echo "PASS no-cmdfile-left"; else echo "FAIL no-cmdfile-left $left"; fi
if head -1 "$HOP_HISTFILE" | grep -q '/beta/gamma$' && grep -q '/alpha$' "$HOP_HISTFILE"; then echo "PASS mru"; else echo "FAIL mru"; fi
if [ -z "${HOP_CMDFILE:-}" ]; then echo "PASS env-clean"; else echo "FAIL env-clean HOP_CMDFILE leaked"; fi
