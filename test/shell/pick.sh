# pick.sh: sourced after `hop init` on a terminal (run-all.sh uses script(1)); FZF_DEFAULT_OPTS stands in for the keystrokes.
# - The binds fire on load, so the real picker, argv and result parse run with nobody typing.
R=$HOP_T/repo
check() {
	if [ "$PWD" = "$2" ]; then
		echo "PASS $1"
	else
		echo "FAIL $1: PWD=$PWD want=$2"
	fi
}
cd "$R"; FZF_DEFAULT_OPTS='--bind=load:abort' hop -p alpha; rc=$?
if [ "$rc" = 130 ] && [ "$PWD" = "$R" ]; then echo "PASS cancel-130"; else echo "FAIL cancel-130 rc=$rc PWD=$PWD"; fi
cd "$R"; FZF_DEFAULT_OPTS='--bind=load:accept' hop -p gamma; check picker-enter "$R/beta/gamma"
cd "$R"; FZF_DEFAULT_OPTS='--bind=load:accept' hop -p with space; check picker-space "$R/with space"
cd "$R"; FZF_DEFAULT_OPTS='--bind=load:accept' hop -p brack; check picker-bracket "$R/brack[1]"
cd "$R"; rm -f "$HOP_T/clip"; FZF_DEFAULT_OPTS="--bind='load:print(ctrl-y)+accept'" hop -p gamma >/dev/null
if [ "$(cat "$HOP_T/clip" 2>/dev/null)" = "$R/beta/gamma" ] && [ "$PWD" = "$R" ]; then echo "PASS picker-copy"; else echo "FAIL picker-copy PWD=$PWD"; fi
