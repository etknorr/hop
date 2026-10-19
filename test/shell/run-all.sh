#!/bin/zsh
# run-all.sh: builds hop, then runs the shell checks in zsh, bash 5, macOS /bin/bash 3.2 and fish.
# - Each shell gets a fresh fixture, a clean environment, and its own history and temp dir.
# - cd.* runs with no terminal; pick.* runs under script(1), which gives it one; the widget and completion run under expect.
# - fish runs on the host when it is on PATH, else in docker: `docker build -f test/docker/Dockerfile.fish -t hop-test-fish test/docker`.
#   NO_DOCKER=1 never uses docker, so fish is skipped unless the host has it; CI runs it that way on both OSes.
# - bash 3.2 is macOS's /bin/bash, so it only runs there; BASH5 names a bash 5 (default: brew's on macOS, /bin/bash on Linux).
# - Prints one PASS, FAIL or XFAIL line per case, then a count per shell; exits 1 on any FAIL, or a shell with no PASS.
emulate -L zsh
setopt pipe_fail
T=${0:A:h}
REPO=${T:h:h}
W=$(mktemp -d "${TMPDIR:-/tmp}/hop-shells.XXXXXX") || exit 1
# Physical, because git reports the repo root that way and macOS's /var is a symlink.
W=${W:A}
B=$W/bin
OS=$(uname -s)
go -C "$REPO" build -o "$B/host/hop" . || exit 1
if [[ $OS == Darwin ]]; then
	BASH5=${BASH5:-/opt/homebrew/bin/bash}
else
	BASH5=${BASH5:-/bin/bash}
fi
typeset -a docker_shells=()
if (( ! $+commands[fish] )) && [[ -z ${NO_DOCKER:-} ]]; then
	docker_shells=(fish)
	arch=$(uname -m)
	[[ $arch == x86_64 ]] && arch=amd64
	[[ $arch == aarch64 ]] && arch=arm64
	GOOS=linux GOARCH=$arch CGO_ENABLED=0 go -C "$REPO" build -o "$B/linux/hop" . || exit 1
	GOOS=linux GOARCH=$arch CGO_ENABLED=0 go -C "$REPO" test -c -o "$B/linux/hop.test" . || exit 1
fi

# ttyrun <argv...>: argv on a terminal from script(1), whose flags differ between BSD (macOS) and util-linux.
ttyrun() {
	if [[ $OS == Darwin ]]; then
		script -q /dev/null "$@"
	else
		script -qec "${(j: :)${(q)@}}" /dev/null
	fi
}

# fxenv <fixture>: reply is the scrubbed environment every host shell runs in.
fxenv() {
	local fx=$1
	reply=(env -i HOME="$fx/home" PATH="$B/host:$fx/stub:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" LANG=en_US.UTF-8
		TERM=xterm-256color TMPDIR="$fx/tmp/" HOP_T="$fx" HOP_CONFIG="$fx/config.toml" HOP_HISTFILE="$fx/tmp/hist" HOP_FZF_HEIGHT=
		ZDOTDIR="$T/rc")
}

# host <label> <init-shell> <interactive-argv> -- <argv...>: cd.sh bare, pick.sh under script(1), then the widget and completion under expect.
host() {
	local label=$1 init=$2 iargv=$3
	shift 4
	local fx=$W/$label
	sh "$T/fixture.sh" "$fx" || return 1
	local -a envv
	fxenv "$fx"
	envv=("${reply[@]}")
	local pre="eval \"\$(hop init $init)\";"
	"${envv[@]}" "$@" -c "$pre . '$T/cd.sh'" 2>&1
	ttyrun "${envv[@]}" "$@" -c "$pre . '$T/pick.sh'" </dev/null 2>&1 | tr -d '\r'
	local -a parse=("$@")
	[[ $init == zsh ]] && parse=(zsh)
	"${envv[@]}" "${parse[@]}" -n <("${envv[@]}" hop init "$init" 2>&1) && print -r -- 'PASS init-parses'
	"${envv[@]}" "${parse[@]}" -n <("${envv[@]}" hop init "$init" --cmd hop1 2>&1) && print -r -- 'PASS init-parses-cmd'
	local t
	for t in widget complete; do
		"${envv[@]}" expect "$T/$t.exp" "$label" ${=iargv} </dev/null 2>&1
	done
}

# hostfish: the same cases for a fish on the host.
hostfish() {
	local fx=$W/fish
	sh "$T/fixture.sh" "$fx" || return 1
	local -a envv
	fxenv "$fx"
	envv=("${reply[@]}")
	"${envv[@]}" fish -c "hop init fish | source; source $T/cd.fish" 2>&1
	ttyrun "${envv[@]}" fish -c "hop init fish | source; source $T/pick.fish" </dev/null 2>&1 | tr -d '\r'
	"${envv[@]}" fish -n <("${envv[@]}" hop init fish 2>&1) && print -r -- 'PASS init-parses'
	"${envv[@]}" fish -n <("${envv[@]}" hop init fish --cmd hop1 2>&1) && print -r -- 'PASS init-parses-cmd'
	local t
	for t in widget complete; do
		"${envv[@]}" expect "$T/$t.exp" fish fish -i -C "source $T/rc/fishrc" </dev/null 2>&1
	done
}

# box <image> <cmd...>: each command in a container, in a fresh fixture, with the repo read-only at /hop.
box() {
	local image=$1
	shift
	docker run --rm -v "$REPO:/hop:ro" -v "$B/linux:/hopbin:ro" "hop-test-$image" sh -c '
		sh /hop/test/shell/fixture.sh /fx >/dev/null || exit 1
		for c; do
			env -i HOME=/fx/home PATH=/hopbin:/fx/stub:/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 TERM=xterm-256color DISPLAY=:0 \
				TMPDIR=/fx/tmp/ HOP_T=/fx HOP_CONFIG=/fx/config.toml HOP_HISTFILE=/fx/tmp/hist HOP_FZF_HEIGHT= sh -c "$c" </dev/null
		done' box "$@" 2>&1 | tr -d '\r'
}

typeset -A pass fail
typeset -a shells
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
shells+=(zsh)
host bash5 bash "$BASH5 --noprofile --rcfile $T/rc/bashrc -i" -- "$BASH5" --norc --noprofile | tally bash5
shells+=(bash5)
if [[ $OS == Darwin ]]; then
	host bash3.2 bash "/bin/bash --noprofile --rcfile $T/rc/bashrc -i" -- /bin/bash --norc --noprofile | tally bash3.2
	shells+=(bash3.2)
fi
if (( $+commands[fish] )); then
	hostfish | tally fish
	shells+=(fish)
fi
X=/hop/test/shell
for s in $docker_shells; do
	box fish "fish -c 'hop init fish | source; source $X/cd.fish'" \
		"script -qec \"fish -c 'hop init fish | source; source $X/pick.fish'\" /dev/null" \
		"hop init fish | fish -n && echo 'PASS init-parses'" \
		"hop init fish --cmd hop1 | fish -n && echo 'PASS init-parses-cmd'" \
		"expect $X/widget.exp fish fish -i -C 'source $X/rc/fishrc'" \
		"expect $X/complete.exp fish fish -i -C 'source $X/rc/fishrc'" | tally fish
	shells+=(fish)
done

# G6: the Go pty test drives the real picker with $SHELL set to each shell, since every callback goes through `hop __sh`.
# - It needs the module at its own path, for testdata, so the worktree is mounted read-only where it lives.
g6() {
	local image=$1 shells=$2 out
	out=$(docker run --rm -v "$REPO:$REPO:ro" -v "$B/linux:/hopbin:ro" -w "$REPO" \
		-e HOP_TEST_BIN=/hopbin/hop -e HOP_TEST_SHELLS="$shells" "hop-test-$image" \
		/hopbin/hop.test -test.run 'TestPickerModal$' -test.v 2>&1)
	print -r -- "$out" | grep -E '^ +--- (PASS|FAIL)' | sed -E 's/^ +--- (PASS|FAIL): TestPickerModal\/([^ ]+).*/\1 g6-picker-callbacks SHELL=\2/'
	print -r -- "$out" | grep -E '^ +pty_test' | sed 's/^ */FAIL detail: /'
}
for s in $docker_shells; do
	g6 fish '/usr/bin/fish /bin/sh' | tally fish
done

print -r -- '== totals'
local -i bad=0
for s in $shells; do
	print -r -- "$s pass ${pass[$s]:-0} fail ${fail[$s]:-0}"
	(( bad += ${fail[$s]:-0} ))
	(( ${pass[$s]:-0} > 0 )) || bad+=1
done
(( $#shells == 4 )) || print -r -- "note: ran ${#shells} of zsh, bash 5, bash 3.2 and fish"
print -r -- "work dir: $W"
(( bad == 0 ))
