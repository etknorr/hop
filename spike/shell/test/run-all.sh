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
BASH5=${BASH5:-/opt/homebrew/bin/bash}
typeset -a docker_shells=(fish pwsh)
[[ -n ${NO_DOCKER:-} ]] && docker_shells=()

# host <label> <init-shell> <argv...>: runs cd.sh bare and pick.sh under script(1) in a fresh fixture.
host() {
	local label=$1 init=$2
	shift 2
	local fx=$W/$label
	sh "$T/fixture.sh" "$fx" || return 1
	local -a envv=(env -i HOME="$fx/home" PATH="$B/darwin:$fx/stub:/usr/bin:/bin:/opt/homebrew/bin" LANG=en_US.UTF-8
		TERM=xterm-256color TMPDIR="$fx/tmp/" HOPX_T="$fx" HOPX_CONFIG="$fx/config.toml" HOPX_HISTFILE="$fx/tmp/hist" HOP_FZF_HEIGHT=)
	local pre="eval \"\$(hopx init $init)\";"
	"${envv[@]}" "$@" -c "$pre . '$T/cd.sh'" 2>&1
	"${envv[@]}" script -q /dev/null "$@" -c "$pre . '$T/pick.sh'" </dev/null 2>&1 | tr -d '\r'
}

# box <label> <image> <cd-cmd> <pick-cmd>: the same in a container, with the spike read-only at /spike.
box() {
	local label=$1 image=$2 cdcmd=$3 pickcmd=$4
	docker run --rm -v "$SPIKE:/spike:ro" -v "$B/linux:/hopxbin:ro" "hopx-b3-$image" sh -c '
		sh /spike/shell/test/fixture.sh /fx >/dev/null || exit 1
		exec env -i HOME=/fx/home PATH=/hopxbin:/fx/stub:/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 TERM=xterm-256color \
			TMPDIR=/fx/tmp/ HOPX_T=/fx HOPX_CONFIG=/fx/config.toml HOPX_HISTFILE=/fx/tmp/hist HOP_FZF_HEIGHT= sh -c "$0; script -qec \"$1\" /dev/null </dev/null" ' \
		"$cdcmd" "$pickcmd" 2>&1 | tr -d '\r'
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

host zsh zsh zsh -f | tally zsh
host bash5 bash "$BASH5" --norc --noprofile | tally bash5
host bash3.2 bash /bin/bash --norc --noprofile | tally bash3.2
for s in $docker_shells; do
	case $s in
		fish) box fish fish 'fish -c "hopx init fish | source; source /spike/shell/test/cd.fish"' 'fish -c \"hopx init fish | source; source /spike/shell/test/pick.fish\"' | tally fish ;;
		pwsh) box pwsh pwsh 'pwsh -NoLogo -NoProfile -File /spike/shell/test/cd.ps1' 'pwsh -NoLogo -NoProfile -File /spike/shell/test/pick.ps1' | tally pwsh ;;
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
