#!/usr/bin/env zsh
# e2e_run.zsh <hop|hopx> <hop-dir|hopx-bin> <root> <cases> <out>: each query through the shell function, headless, from <root>.
# - hop is the zsh function from <hop-dir>/hop.zsh, with _hop_tty_ok stubbed to fail as a script or cron job would see it.
# - hopx is the function `hopx init zsh` prints, calling <hopx-bin>; the caller runs this with no controlling terminal.
# - A case is set<TAB>query, plus <TAB>dir to run it from somewhere other than <root>.
# - Out is set, query, rc, landing dir, remembered dir, wall ms and stderr with newlines as \n.
# - Dirs are root-relative, `./` for the root itself; the history file is emptied before every query, so one jump never ranks the next.
# - Each query runs in a subshell, so the function's cd lands there and the runner never moves.
emulate -L zsh
setopt extended_glob
zmodload zsh/datetime
local impl=$1 src=${2:A} root=${3:A} cases=${4:A} out=${5:A}
local tmp
tmp=$(mktemp -d "${TMPDIR:-/tmp}/hopx-e2e.XXXXXX") || exit 1
local hist=$tmp/hist err=$tmp/err res=$tmp/res
export HOP_HISTFILE=$hist HOPX_HISTFILE=$hist XDG_CACHE_HOME=$tmp/cache
case $impl in
	hop)
		source "$src/hop.zsh" || exit 3
		_hop_tty_ok() { return 1 }
		;;
	hopx)
		path=("${src:h}" "${path[@]}")
		[[ ${commands[hopx]} == "$src" ]] || { print -ru2 -- "e2e_run: $src is not the first hopx on PATH"; exit 3 }
		eval "$(command hopx init zsh)" || exit 3
		;;
	*)
		print -ru2 -- "e2e_run: unknown impl: $impl"
		exit 2
		;;
esac

e2e_rel() {
	emulate -L zsh
	if [[ -z $1 ]]; then
		REPLY=-
	elif [[ ${1:A} == "$root" ]]; then
		REPLY=./
	elif [[ ${1:A} == "$root"/* ]]; then
		REPLY=${${1:A}#"$root"/}/
	else
		REPLY=${1:A}
	fi
}

local line set q rc pwd mem e tab=$'\t' REPLY lrel
local -F t0 ms
local -a f
builtin cd -q -- "$root" || exit 2
: >| "$out"
for line in "${(@f)$(<"$cases")}"; do
	f=("${(@ps:\t:)line}")
	set=${f[1]} q=${f[2]}
	: >| "$hist"
	t0=$EPOCHREALTIME
	(
		[[ -n ${f[3]:-} ]] && builtin cd -q -- "${f[3]}"
		$impl ${=q} >/dev/null 2>"$err" </dev/null
		print -r -- "$?${tab}${PWD}"
	) >"$res"
	(( ms = (EPOCHREALTIME - t0) * 1000 ))
	IFS=$'\t' read -r rc pwd <"$res"
	mem=''
	[[ -s $hist ]] && IFS= read -r mem <"$hist"
	e=$(<"$err")
	e=${e//$'\n'/\\n}
	e2e_rel "$pwd"
	lrel=$REPLY
	[[ ${pwd:A} == "${${f[3]:-$root}:A}" && -z $mem ]] && lrel=-
	e2e_rel "$mem"
	printf '%s\t%s\t%s\t%s\t%s\t%.1f\t%s\n' "$set" "$q" "$rc" "$lrel" "$REPLY" "$ms" "$e" >>"$out"
done
rm -rf "$tmp"
