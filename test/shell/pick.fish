# pick.fish: pick.sh for fish, on a terminal from script(1).
set R $HOP_T/repo
function check
	if test "$PWD" = "$argv[2]"
		echo "PASS $argv[1]"
	else
		echo "FAIL $argv[1]: PWD=$PWD want=$argv[2]"
	end
end
cd $R; FZF_DEFAULT_OPTS='--bind=load:abort' hop -p alpha; set rc $status
if test $rc = 0 -a "$PWD" = "$R"; echo "PASS cancel-0"; else; echo "FAIL cancel-0 rc=$rc PWD=$PWD"; end
cd $R; FZF_DEFAULT_OPTS='--bind=load:accept' hop -p gamma; check picker-enter "$R/beta/gamma"
cd $R; FZF_DEFAULT_OPTS='--bind=load:accept' hop -p with space; check picker-space "$R/with space"
cd $R; FZF_DEFAULT_OPTS='--bind=load:accept' hop -p brack; check picker-bracket "$R/brack[1]"
cd $R; FZF_DEFAULT_OPTS="--bind='load:print(ctrl-y)+accept'" PATH=$HOP_T/stub:$PATH hop -p gamma >/dev/null
if test "$(cat $HOP_T/clip 2>/dev/null)" = "$R/beta/gamma" -a "$PWD" = "$R"; echo "PASS picker-copy"; else; echo "FAIL picker-copy PWD=$PWD"; end
