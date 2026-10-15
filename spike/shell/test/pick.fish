# pick.fish: pick.sh for fish, on a terminal from script(1).
set R $HOPX_T/repo
function check
	if test "$PWD" = "$argv[2]"
		echo "PASS $argv[1]"
	else
		echo "FAIL $argv[1]: PWD=$PWD want=$argv[2]"
	end
end
cd $R; FZF_DEFAULT_OPTS='--bind=load:abort' hopx -p alpha; set rc $status
if test $rc = 130 -a "$PWD" = "$R"; echo "PASS cancel-130"; else; echo "FAIL cancel-130 rc=$rc PWD=$PWD"; end
cd $R; FZF_DEFAULT_OPTS='--bind=load:accept' hopx -p gamma; check picker-enter "$R/beta/gamma"
cd $R; FZF_DEFAULT_OPTS='--bind=load:accept' hopx -p with space; check picker-space "$R/with space"
cd $R; FZF_DEFAULT_OPTS='--bind=load:accept' hopx -p brack; check picker-bracket "$R/brack[1]"
cd $R; FZF_DEFAULT_OPTS="--bind='load:print(ctrl-y)+accept'" PATH=$HOPX_T/stub:$PATH hopx -p gamma >/dev/null
if test "$(cat $HOPX_T/clip 2>/dev/null)" = "$R/beta/gamma" -a "$PWD" = "$R"; echo "PASS picker-copy"; else; echo "FAIL picker-copy PWD=$PWD"; end
