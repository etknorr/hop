#!/bin/zsh
# run-all.sh: builds hopx for the host and linux, then runs the shell checks in zsh, bash 5, bash 3.2, fish and pwsh.
# - Each shell gets a fresh fixture, a clean environment, and its own history and temp dir.
# - cd.* runs with no terminal; pick.* runs under script(1), which gives it one.
# - fish and pwsh run in docker (spike/docker), since neither is on the host.
# - Prints one PASS, FAIL or XFAIL line per case, then a count per shell; exits 1 on any FAIL.
emulate -L zsh
setopt pipe_fail
T=${0:A:h}
SPIKE=${T:h:h}
W=$(mktemp -d "${TMPDIR:-/tmp}/hopx-shells.XXXXXX") || exit 1
# Physical, because git reports the repo root that way and macOS's /var is a symlink.
W=${W:A}
B=$W/bin
go -C "$SPIKE/hopx" build -o "$B/darwin/hopx" . || exit 1
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go -C "$SPIKE/hopx" build -o "$B/linux/hopx" . || exit 1
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go -C "$SPIKE/hopx" test -c -o "$B/linux/hopx.test" . || exit 1
BASH5=${BASH5:-/opt/homebrew/bin/bash}
typeset -a docker_shells=(fish pwsh)
[[ -n ${NO_DOCKER:-} ]] && docker_shells=()

# host <label> <init-shell> <interactive-argv> -- <argv...>: cd.sh bare, pick.sh under script(1), then the widget and completion under expect.
host() {
	local label=$1 init=$2 iargv=$3
	shift 4
	local fx=$W/$label
	sh "$T/fixture.sh" "$fx" || return 1
	local -a envv=(env -i HOME="$fx/home" PATH="$B/darwin:$fx/stub:/usr/bin:/bin:/opt/homebrew/bin" LANG=en_US.UTF-8
		TERM=xterm-256color TMPDIR="$fx/tmp/" HOPX_T="$fx" HOPX_CONFIG="$fx/config.toml" HOPX_HISTFILE="$fx/tmp/hist" HOP_FZF_HEIGHT=
		ZDOTDIR="$T/rc")
	local pre="eval \"\$(hopx init $init)\";"
	"${envv[@]}" "$@" -c "$pre . '$T/cd.sh'" 2>&1
	"${envv[@]}" script -q /dev/null "$@" -c "$pre . '$T/pick.sh'" </dev/null 2>&1 | tr -d '\r'
	local -a parse=("$@")
	[[ $init == zsh ]] && parse=(zsh)
	"${envv[@]}" "${parse[@]}" -n <("${envv[@]}" hopx init "$init" 2>&1) && print -r -- 'PASS init-parses'
	local t
	for t in widget complete; do
		"${envv[@]}" expect "$T/$t.exp" "$label" ${=iargv} </dev/null 2>&1
	done
}

# box <image> <cmd...>: each command in a container, in a fresh fixture, with the spike read-only at /spike.
box() {
	local image=$1
	shift
	docker run --rm -v "$SPIKE:/spike:ro" -v "$B/linux:/hopxbin:ro" "hopx-b3-$image" sh -c '
		sh /spike/shell/test/fixture.sh /fx >/dev/null || exit 1
		for c; do
			env -i HOME=/fx/home PATH=/hopxbin:/fx/stub:/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 TERM=xterm-256color \
				TMPDIR=/fx/tmp/ HOPX_T=/fx HOPX_CONFIG=/fx/config.toml HOPX_HISTFILE=/fx/tmp/hist HOP_FZF_HEIGHT= sh -c "$c" </dev/null
		done' box "$@" 2>&1 | tr -d '\r'
}

typeset -A pass fail
# The picker's screen reaches stdout through script(1), so a result line can follow its escape bytes.
tally() {
	local label=$1 line
	while IFS= read -r line; do
		[[ $line =~ '(PASS|FAIL|XFAIL) .*' ]] || continue
		line=$MATCH
		print -r -- "$label $line"
		case $line in
			PASS*) (( pass[$label]++ )) ;;
			FAIL*) (( fail[$label]++ )) ;;
		esac
	done
}

host zsh zsh 'zsh -i' -- zsh -f | tally zsh
host bash5 bash "$BASH5 --noprofile --rcfile $T/rc/bashrc -i" -- "$BASH5" --norc --noprofile | tally bash5
host bash3.2 bash "/bin/bash --noprofile --rcfile $T/rc/bashrc -i" -- /bin/bash --norc --noprofile | tally bash3.2
X=/spike/shell/test
for s in $docker_shells; do
	case $s in
		fish)
			box fish "fish -c 'hopx init fish | source; source $X/cd.fish'" \
				"script -qec \"fish -c 'hopx init fish | source; source $X/pick.fish'\" /dev/null" \
				"hopx init fish | fish -n && echo 'PASS init-parses'" \
				"expect $X/widget.exp fish fish -i -C 'source $X/rc/fishrc'" \
				"expect $X/complete.exp fish fish -i -C 'source $X/rc/fishrc'" | tally fish
			;;
		pwsh)
			box pwsh "pwsh -NoLogo -NoProfile -File $X/cd.ps1" \
				"script -qec 'pwsh -NoLogo -NoProfile -File $X/pick.ps1' /dev/null" \
				"pwsh -NoLogo -NoProfile -Command '\$null = [scriptblock]::Create((& hopx init pwsh | Out-String)); \"PASS init-parses\"'" \
				"expect $X/widget.exp pwsh pwsh -NoLogo -NoProfile -NoExit -Command '. $X/rc/pwshrc.ps1'" \
				"expect $X/complete.exp pwsh pwsh -NoLogo -NoProfile -NoExit -Command '. $X/rc/pwshrc.ps1'" | tally pwsh
			;;
	esac
done

# G6: the Go pty test drives the real picker with $SHELL set to each shell, since every callback goes through `hopx __sh`.
# - It needs the module at its own path, for testdata, so the worktree is mounted read-only where it lives.
g6() {
	local image=$1 shells=$2 out
	out=$(docker run --rm -v "${SPIKE:h}:${SPIKE:h}:ro" -v "$B/linux:/hopxbin:ro" -w "$SPIKE/hopx" \
		-e HOPX_TEST_BIN=/hopxbin/hopx -e HOPX_TEST_SHELLS="$shells" "hopx-b3-$image" \
		/hopxbin/hopx.test -test.run 'TestPicker$' -test.v 2>&1)
	print -r -- "$out" | grep -E '^ +--- (PASS|FAIL)' | sed -E 's/^ +--- (PASS|FAIL): TestPicker\/([^ ]+).*/\1 g6-picker-callbacks SHELL=\2/'
	print -r -- "$out" | grep -E '^ +pty_test' | sed 's/^ */FAIL detail: /'
}
for s in $docker_shells; do
	case $s in
		fish) g6 fish '/usr/bin/fish /bin/sh' | tally fish ;;
		pwsh) g6 pwsh '/usr/local/bin/pwsh /bin/sh' | tally pwsh ;;
	esac
done

print -r -- '== totals'
local -i bad=0
for s in zsh bash5 bash3.2 $docker_shells; do
	print -r -- "$s pass ${pass[$s]:-0} fail ${fail[$s]:-0}"
	(( bad += ${fail[$s]:-0} ))
	(( ${pass[$s]:-0} > 0 )) || bad+=1
done
print -r -- "work dir: $W"
(( bad == 0 ))
