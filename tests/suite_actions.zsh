#!/usr/bin/env zsh
# suite_actions: what Enter and the code verbs run, for every HOP_ACTION mode, target shape and VS Code state.
# - `code` is a recording stub, so every assertion reads the exact argv a real VS Code would get.
# - `code -r <dir>` reloads the last-focused window onto that folder, so a directory must get `-n`.
# - A file keeps `-r`, which opens it in the window already there instead of spawning a new one.
# - Each table runs inside ONE probe child that prints a TSV line per case, so 140 cases cost one shell.

stub_bin

# ac_slurp <file> -> its contents, or nothing when unreadable; `zsh -n` evaluates a top-level $(<file).
ac_slurp() {
	emulate -L zsh
	[[ -r $1 ]] && print -r -- "$(<"$1")"
	return 0
}

typeset -g AC_DIR AC_FILE
fixture_tmpdir actions
AC_DIR=$REPLY
AC_FILE="$AC_DIR/terragrunt.hcl"
print -r -- 'include {}' > "$AC_FILE"

# ---------------------------------------------------------------------------
# ctrl-o / o: open the preview, which is a file on most rows and the dir itself on the rest.
# ---------------------------------------------------------------------------
t 'ctrl-o on a file preview opens it with code -r'
stub_reset
hop_probe "_hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_FILE}"
assert_eq "code	-r	${AC_FILE}" "$(stub_calls code)"

# A dir preview is what _hop_preview_doc falls back to when a dir has no README, README.md or CLAUDE.md.
t 'ctrl-o on a dir preview opens a new window with code -n, never code -r'
stub_reset
hop_probe "_hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_DIR}"
assert_eq "code	-n	${AC_DIR}" "$(stub_calls code)" 'code -r on a dir replaces the focused window'"'"'s folder'

# ---------------------------------------------------------------------------
# ctrl-t / O: the row's dir as a folder, in its own window.
# ---------------------------------------------------------------------------
t 'ctrl-t opens the dir with code -n'
stub_reset
hop_probe "_hop_dispatch ctrl-t ${(q)AC_DIR} ${(q)AC_FILE}"
assert_eq "code	-n	${AC_DIR}" "$(stub_calls code)" 'a bare code <dir> replaces the workspace under openFoldersInNewWindow=off'

# The invariant both fixes serve, checked over every call this suite made rather than one at a time.
t 'no verb ever hands code -r a directory'
stub_reset
hop_probe "_hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_FILE}
_hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_DIR}
_hop_dispatch ctrl-t ${(q)AC_DIR} ${(q)AC_FILE}
_hop_dispatch ctrl-t ${(q)AC_DIR} ${(q)AC_DIR}"
typeset -a AC_CALLS=("${(@f)$(stub_calls code)}")
typeset AC_BAD='' AC_CALL
typeset -a AC_ARGV
for AC_CALL in "${AC_CALLS[@]}"; do
	AC_ARGV=("${(@ps:\t:)AC_CALL}")
	[[ ${AC_ARGV[2]} == -r && -d ${AC_ARGV[3]} ]] && AC_BAD+="${AC_CALL} "
done
assert_eq 4 "${#AC_CALLS}" 'every dispatch above must have reached code, or the scan below proves nothing'
assert_empty "$AC_BAD" 'code -r with a directory reloads the focused window onto it'

# HOP_CODE is word-split like HOP_CLIPBOARD, so a launcher can carry its own flags.
t 'HOP_CODE names the launcher, word-split, and its flags come before -r'
stub_reset
hop_probe "HOP_CODE='code --profile hop'; _hop_dispatch ctrl-o ${(q)AC_DIR} ${(q)AC_FILE}"
assert_eq "code	--profile	hop	-r	${AC_FILE}" "$(stub_calls code)"

# ---------------------------------------------------------------------------
# The matrix: every mode, over every target shape, in every VS Code state.
# ---------------------------------------------------------------------------
# The tree sits under names with a space, so a quoting slip anywhere in the action path shows up as a miss.
typeset -g AC_R AC_W AC_START AC_BASE AC_WORK
fixture_tmpdir 'act ions'
AC_R="$REPLY/re po"
AC_W="$REPLY/home"
AC_START="$REPLY/start"
mkdir -p -- "$AC_R/k/services" "$AC_R/tf/unit" "$AC_R/tf/readme" "$AC_R/k/values/x" "$AC_R/tf/acct/env-prod" \
	"$AC_W/ws" "$AC_W/repo" "$AC_START"
print -r -- 'kind: Application' > "$AC_R/k/services/grafana.yaml"
print -r -- 'resource {}' > "$AC_R/tf/unit/main.tf"
print -r -- 'include {}' > "$AC_R/tf/unit/terragrunt.hcl"
# a.hcl sorts before README.md, so a README chosen anyway proves README wins over name order.
print -r -- '# readme' > "$AC_R/tf/readme/README.md"
print -r -- 'locals {}' > "$AC_R/tf/readme/a.hcl"
print -r -- 'image: x' > "$AC_R/k/values/x/values.yaml"
print -r -- 'locals {}' > "$AC_R/tf/acct/terragrunt_aws_account.hcl"
print -r -- 'locals {}' > "$AC_R/tf/acct/zz.hcl"
print -r -- '# repo' > "$AC_W/repo/README.md"
fixture_tmpdir actwork
AC_WORK=$REPLY
# A PATH holding zsh alone, so `code` is genuinely absent rather than merely misnamed, as suite_clipboard does it.
fixture_tmpdir actbase
AC_BASE=$REPLY
ln -sf -- "${commands[zsh]}" "$AC_BASE/zsh"

# Each target: name, dir, preview, rel, and 1 when it is a workspace or repo row.
# - dirreadme and synth both preview the dir itself, as 21 of 1041 real rows and every synthetic row do.
# - dirempty holds only a subdir at its top, which is the kubernetes/values case with nothing to reveal.
typeset -ga AC_TARGETS=(
	"file"$'\t'"$AC_R/k/services"$'\t'"$AC_R/k/services/grafana.yaml"$'\t'"k/services/grafana.yaml"$'\t'0
	"dirfile"$'\t'"$AC_R/tf/unit"$'\t'"$AC_R/tf/unit/main.tf"$'\t'"tf/unit/"$'\t'0
	"dirreadme"$'\t'"$AC_R/tf/readme"$'\t'"$AC_R/tf/readme"$'\t'"tf/readme/"$'\t'0
	"dirempty"$'\t'"$AC_R/k/values"$'\t'"$AC_R/k/values"$'\t'"k/values/"$'\t'0
	"synth"$'\t'"$AC_R/tf/acct"$'\t'"$AC_R/tf/acct"$'\t'"tf/acct/"$'\t'0
	"ws"$'\t'"$AC_W/ws"$'\t'"$AC_W/ws"$'\t'"~/ws/"$'\t'1
	"repo"$'\t'"$AC_W/repo"$'\t'"$AC_W/repo/README.md"$'\t'"~/repo/"$'\t'1
)
typeset -ga AC_MODES=(cd open reveal cd+open cd+reveal)
typeset -ga AC_STATES=(usable absent ssh ipc)

typeset AC_CASES="$AC_WORK/cases" ac_m ac_s ac_t
: > "$AC_CASES"
for ac_m in "${AC_MODES[@]}"; do
	for ac_s in "${AC_STATES[@]}"; do
		for ac_t in "${AC_TARGETS[@]}"; do
			print -r -- "${ac_m}"$'\t'"${ac_s}"$'\t'"${ac_t}" >> "$AC_CASES"
		done
	done
done

# Runs inside the probe child: one subshell per case, so a state's exports and the cd never leak to the next.
# - Each output line is the case, then the status, the final $PWD, the code and editor calls, and stderr.
# - A call's own TABs become spaces, and stderr's newlines become ` / `, so the line stays one TSV record.
cat > "$AC_WORK/matrix.zsh" <<'EOF'
_hop_tty_ok() { return 0 }
ac_matrix() {
	emulate -L zsh
	local cases=$1 start=$2 base=$3 errf=$4 tab=$'\t'
	local -a f calls
	local line st
	for line in "${(@f)$(<"$cases")}"; do
		f=("${(@ps:\t:)line}")
		: > "$HOP_FIX_LOG"
		builtin cd -q -- "$start"
		(
			case ${f[2]} in
				absent) path=("$base") ;;
				ssh) export SSH_CONNECTION='192.0.2.1 50000 192.0.2.2 22' ;;
				ipc) export VSCODE_IPC_HOOK_CLI=/nonexistent/vscode-ipc.sock ;;
			esac
			_hop_mode=${f[1]} _hop_folder_rows=${f[7]}
			_hop_dispatch '' "${f[4]}" "${f[5]}" "${f[6]}" 2>"$errf"
			st=$?
			calls=("${(@f)$(<"$HOP_FIX_LOG")}")
			calls=(${(M)calls:#(code|editor)$'\t'*})
			calls=("${(@)calls//$'\t'/ }")
			print -r -- "${line}${tab}${st}${tab}${PWD}${tab}${(j:|:)calls}${tab}${(j: / :)${(f)"$(<"$errf")"}}"
		)
	done
}
EOF

typeset AC_OUT
AC_OUT=$(hop_probe "source ${(q)AC_WORK}/matrix.zsh; ac_matrix ${(q)AC_CASES} ${(q)AC_START} ${(q)AC_BASE} ${(q)AC_WORK}/err")
typeset -a AC_LINES=("${(@f)AC_OUT}")
AC_LINES=(${AC_LINES:#})

# ac_expect <mode> <state> <target> <dir> <preview> <rel> <whole> -> AC_X_ST, AC_X_PWD, AC_X_CALLS, AC_X_ERR.
# - The spec's command table written out once more, independently of lib/actions.zsh, so the two can disagree.
ac_expect() {
	emulate -L zsh
	local mode=$1 state=$2 tgt=$3 d=$4 p=$5 rel=$6
	local -i whole=$7 cd=0
	[[ $mode == cd* ]] && cd=1
	local verb=${${mode#cd}#+}
	AC_X_ST=0 AC_X_CALLS='' AC_X_ERR=''
	AC_X_PWD=$AC_START
	(( cd )) && AC_X_PWD=$d
	[[ -n $verb ]] || return 0
	if [[ $state == usable ]]; then
		if (( whole )); then
			AC_X_CALLS="code -n ${d}"
		elif [[ $tgt == file ]]; then
			AC_X_CALLS="code -r ${p}"
		elif [[ $verb == open ]]; then
			AC_X_CALLS="code -n ${d}"
		else
			case $tgt in
				dirfile) AC_X_CALLS="code -r ${p}" ;;
				dirreadme) AC_X_CALLS="code -r ${d}/README.md" ;;
				synth) AC_X_CALLS="code -r ${d}/terragrunt_aws_account.hcl" ;;
				dirempty)
					AC_X_ERR="hop: nothing to reveal at the top of ${rel}; use -o to open it as a folder"
					(( cd )) || AC_X_ST=1
					;;
			esac
		fi
		return 0
	fi
	if (( cd )); then
		AC_X_ERR='so this was a cd only'
	elif (( whole )); then
		AC_X_CALLS="editor ${d}" AC_X_ERR='using the terminal editor instead'
	elif [[ $tgt == file ]]; then
		AC_X_CALLS="editor ${p}" AC_X_ERR='using the terminal editor instead'
	elif [[ $verb == open ]]; then
		AC_X_CALLS="editor ${d}" AC_X_ERR='using the terminal editor instead'
	else
		AC_X_ST=1 AC_X_ERR='and only VS Code can reveal'
	fi
	return 0
}

typeset -g AC_X_ST AC_X_PWD AC_X_CALLS AC_X_ERR
t 'matrix: the probe ran every case'
assert_eq $(( ${#AC_MODES} * ${#AC_STATES} * ${#AC_TARGETS} )) "${#AC_LINES}" 'a case went missing, so the matrix below proves less than it says'

typeset ac_line
typeset -a ac_f
for ac_line in "${AC_LINES[@]}"; do
	ac_f=("${(@ps:\t:)ac_line}")
	ac_expect "${ac_f[1]}" "${ac_f[2]}" "${ac_f[3]}" "${ac_f[4]}" "${ac_f[5]}" "${ac_f[6]}" "${ac_f[7]}"
	t "matrix: ${ac_f[1]} on ${ac_f[3]}, code ${ac_f[2]}"
	assert_eq "$AC_X_CALLS" "${ac_f[10]-}" 'the code and editor calls'
	assert_eq "$AC_X_ST" "${ac_f[8]}" "the status; stderr: ${ac_f[11]-}"
	assert_eq "$AC_X_PWD" "${ac_f[9]}" 'the shell'"'"'s directory afterwards'
	[[ -n $AC_X_ERR ]] && assert_contains "${ac_f[11]-}" "$AC_X_ERR" 'the notice'
done

# The invariant the whole table serves, checked over every call it recorded rather than case by case.
t 'matrix: code -r never received a directory, across every mode, target and state'
AC_BAD=''
for ac_line in "${AC_LINES[@]}"; do
	ac_f=("${(@ps:\t:)ac_line}")
	for AC_CALL in "${(@s:|:)${ac_f[10]-}}"; do
		[[ $AC_CALL == 'code -r '* && -d ${AC_CALL#code -r } ]] && AC_BAD+="${AC_CALL} "
	done
done
assert_empty "$AC_BAD"
assert_contains "$AC_OUT" 'code -r ' 'the table made no -r call at all, so the scan above proves nothing'

# ---------------------------------------------------------------------------
# The invariants the table cannot show by itself.
# ---------------------------------------------------------------------------
typeset AC_FAIL="$AC_WORK/failcode" AC_RUN
print -rl -- '#!/bin/sh' 'printf "failcode\t%s\t%s\n" "$1" "$2" >> "$HOP_FIX_LOG"' 'exit 3' > "$AC_FAIL"
chmod +x "$AC_FAIL"

t 'a code call that fails after the cd keeps the cd and returns code'"'"'s status'
stub_reset
AC_RUN=$(hop_probe "builtin cd -q -- ${(q)AC_START}
HOP_CODE=${(q)AC_FAIL}
_hop_mode=cd+open _hop_dispatch '' ${(q)AC_R}/tf/unit ${(q)AC_R}/tf/unit/main.tf tf/unit/
print -r -- \"st=\$? PWD=\$PWD\"")
assert_eq "st=3 PWD=$AC_R/tf/unit" "$AC_RUN"
assert_eq "failcode	-n	$AC_R/tf/unit" "$(stub_calls failcode)"

# No terminal means no editor can own the tty, and `code` was absent, so the path is all there is to give.
t 'headless open of a file with code absent launches no editor, prints the path, and fails'
stub_reset
AC_RUN=$(hop_probe "_hop_tty_ok() { return 1 }
path=(${(q)AC_BASE})
_hop_mode=open _hop_dispatch '' ${(q)AC_R}/k/services ${(q)AC_R}/k/services/grafana.yaml k/services/grafana.yaml
print -r -- \"st=\$?\"" 2>&1)
assert_contains "$AC_RUN" 'st=1'
assert_contains "$AC_RUN" "hop: no terminal for an editor; target: $AC_R/k/services/grafana.yaml"
assert_empty "$(stub_calls editor)" 'an editor started with no terminal to run in'

typeset AC_HIST="$AC_WORK/history"
t 'Enter under open still teaches the MRU the dir'
stub_reset
: > "$AC_HIST"
hop_probe "HOP_HISTFILE=${(q)AC_HIST}; _hop_mode=open _hop_dispatch '' ${(q)AC_R}/tf/unit ${(q)AC_R}/tf/unit/main.tf tf/unit/"
assert_eq "$AC_R/tf/unit" "$(ac_slurp "$AC_HIST")"
assert_eq "code	-n	$AC_R/tf/unit" "$(stub_calls code)"

t 'ctrl-o and ctrl-t teach the MRU the row'"'"'s dir as well'
: > "$AC_HIST"
hop_probe "HOP_HISTFILE=${(q)AC_HIST}; _hop_dispatch ctrl-o ${(q)AC_R}/tf/unit ${(q)AC_R}/tf/unit/main.tf; _hop_dispatch ctrl-t ${(q)AC_R}/k/values ${(q)AC_R}/k/values"
assert_eq "$AC_R/k/values"$'\n'"$AC_R/tf/unit" "$(ac_slurp "$AC_HIST")"

t 'alt-enter cds whatever the mode, and calls no code'
stub_reset
AC_RUN=$(hop_probe "builtin cd -q -- ${(q)AC_START}; _hop_mode=open _hop_dispatch alt-enter ${(q)AC_R}/tf/unit ${(q)AC_R}/tf/unit/main.tf tf/unit/; print -r -- \"PWD=\$PWD\"")
assert_eq "PWD=$AC_R/tf/unit" "$AC_RUN"
assert_empty "$(stub_calls code)"

t 'ctrl-o with VS Code unreachable says why and falls back to the editor'
stub_reset
AC_RUN=$(hop_probe "SSH_CONNECTION=x; _hop_tty_ok() { return 0 }; _hop_dispatch ctrl-o ${(q)AC_R}/tf/unit ${(q)AC_R}/tf/unit/main.tf" 2>&1)
assert_contains "$AC_RUN" 'SSH session'
assert_eq "editor	$AC_R/tf/unit/main.tf" "$(stub_calls editor)"
assert_empty "$(stub_calls code)"

# ---------------------------------------------------------------------------
# _hop_code_usable: one case per reason, plus the states that must count as usable.
# ---------------------------------------------------------------------------
# The live socket is made by zsocket, so the -S test sees a real one and not a file pretending.
typeset AC_SOCK="$AC_WORK/ipc.sock"
cat > "$AC_WORK/usable.zsh" <<'EOF'
ac_usable() {
	emulate -L zsh
	local label=$1
	shift
	(
		local a
		for a in "$@"; do
			typeset -g "${a%%=*}"="${a#*=}"
		done
		_hop_code_usable
		print -r -- "${label}"$'\t'"$?"$'\t'"${REPLY}"
	)
}
EOF
AC_RUN=$(hop_probe "source ${(q)AC_WORK}/usable.zsh
zmodload zsh/net/socket && zsocket -l ${(q)AC_SOCK}
ac_usable default
ac_usable missing HOP_CODE=hop-no-such-launcher
ac_usable nopath HOP_CODE=/nonexistent/code
ac_usable stale VSCODE_IPC_HOOK_CLI=/nonexistent/vscode-ipc.sock
ac_usable live VSCODE_IPC_HOOK_CLI=${(q)AC_SOCK} SSH_CONNECTION=x OSTYPE=linux-gnu DISPLAY=
ac_usable sshconn SSH_CONNECTION=x
ac_usable sshtty SSH_TTY=/dev/ttys009
ac_usable linux OSTYPE=linux-gnu DISPLAY= WAYLAND_DISPLAY=
ac_usable wayland OSTYPE=linux-gnu DISPLAY= WAYLAND_DISPLAY=wayland-0
ac_usable x11 OSTYPE=linux-gnu DISPLAY=:0
ac_usable mac OSTYPE=darwin24.0 DISPLAY= WAYLAND_DISPLAY=")
typeset -A AC_U
for ac_line in "${(@f)AC_RUN}"; do
	ac_f=("${(@ps:\t:)ac_line}")
	AC_U[${ac_f[1]}]="${ac_f[2]}"$'\t'"${ac_f[3]-}"
done

t '_hop_code_usable: the pinned test environment can reach the stub'
assert_eq 0 "${${AC_U[default]-x}%%$'\t'*}" "${AC_U[default]-no result}"

t '_hop_code_usable: a launcher that is not installed, or does not exist, is unusable with _hop_need'"'"'s reason'
assert_eq $'1\thop-no-such-launcher is not installed, cannot open VS Code' "${AC_U[missing]-}"
assert_eq $'1\t/nonexistent/code does not exist, cannot open VS Code' "${AC_U[nopath]-}"

t '_hop_code_usable: a stale VSCODE_IPC_HOOK_CLI is unusable'
assert_eq 1 "${${AC_U[stale]-x}%%$'\t'*}"
assert_contains "${AC_U[stale]-}" 'no live VS Code socket'

t '_hop_code_usable: a live IPC socket is usable even over SSH on a Linux host with no DISPLAY'
assert_eq 0 "${${AC_U[live]-x}%%$'\t'*}" "${AC_U[live]-no result}"

t '_hop_code_usable: an SSH session with no IPC hook is unusable, by SSH_CONNECTION or SSH_TTY'
assert_eq 1 "${${AC_U[sshconn]-x}%%$'\t'*}"
assert_eq 1 "${${AC_U[sshtty]-x}%%$'\t'*}"
assert_contains "${AC_U[sshconn]-}" 'SSH session'

t '_hop_code_usable: Linux with neither DISPLAY nor WAYLAND_DISPLAY is unusable, and either one is enough'
assert_eq 1 "${${AC_U[linux]-x}%%$'\t'*}"
assert_contains "${AC_U[linux]-}" 'DISPLAY'
assert_eq 0 "${${AC_U[wayland]-x}%%$'\t'*}"
assert_eq 0 "${${AC_U[x11]-x}%%$'\t'*}"
assert_eq 0 "${${AC_U[mac]-x}%%$'\t'*}" 'macOS needs no DISPLAY'

# ---------------------------------------------------------------------------
# The flags, through hop itself, headless, over the resolver's real-shaped fixture.
# ---------------------------------------------------------------------------
if [[ -z $IT_REAL_FZF ]]; then
	skip_cap 'flags: the action flags through hop' 'fzf is not installed'
	return 0
fi

typeset -g AC_MT AC_SP AC_EKS AC_WSH AC_WS
match_fixture || return 1
AC_MT=$REPLY
AC_SP=terraform/acct-security-tooling-prod/env-prod/us-east-1
AC_EKS="$AC_MT/$AC_SP/eks"
AC_WSH=$HOP_FIX_HOME
typeset ac_w
for ac_w in strava/configuration personal/notes; do
	mkdir -p -- "$AC_WSH/$ac_w"
	_hop_fix_git -C "$AC_WSH/$ac_w" init -q -b main
done
AC_WS="strava-ws=${AC_WSH}/strava:personal-ws=${AC_WSH}/personal"

# A case is a label, a cwd (relative to the fixture repo unless absolute), and the hop code to eval.
# - Each output line is the label, the status, the final $PWD, the code calls, and stderr, as in the matrix.
cat > "$AC_WORK/flags.zsh" <<'EOF'
_hop_tty_ok() { return 1 }
ac_flags() {
	emulate -L zsh
	local cases=$1 repo=$2 errf=$3 tab=$'\t'
	local -a f calls
	local line st cwd
	for line in "${(@f)$(<"$cases")}"; do
		f=("${(@ps:\t:)line}")
		: > "$HOP_FIX_LOG"
		cwd=${f[2]}
		[[ $cwd == /* ]] || cwd=$repo/$cwd
		builtin cd -q -- "$cwd"
		(
			eval "${f[3]}" 2>"$errf"
			st=$?
			calls=("${(@f)$(<"$HOP_FIX_LOG")}")
			calls=(${(M)calls:#(code|editor)$'\t'*})
			calls=("${(@)calls//$'\t'/ }")
			print -r -- "${f[1]}${tab}${st}${tab}${PWD}${tab}${(j:|:)calls}${tab}${(j: / :)${(f)"$(<"$errf")"}}"
		)
	done
}
EOF

typeset AC_FCASES="$AC_WORK/flagcases"
: > "$AC_FCASES"
# ac_fcase <label> <cwd> <hop-code>
ac_fcase() {
	emulate -L zsh
	print -r -- "${1}"$'\t'"${2}"$'\t'"${3}" >> "$AC_FCASES"
}

# Each flag, by itself and with every option that changes which rows there are or which level they come from.
typeset -ga AC_FLAGS=('-o' '-e' '--cd' '--cd -o' '--cd -e' '--action=cd+reveal')
typeset ac_fl
for ac_fl in "${AC_FLAGS[@]}"; do
	ac_fcase "plain ${ac_fl}" . "hop ${ac_fl} eks security"
	ac_fcase "kinds ${ac_fl}" . "hop -k tg ${ac_fl} eks security"
	ac_fcase "all ${ac_fl}" . "hop -a ${ac_fl} eks security"
	ac_fcase "cwd ${ac_fl}" "$AC_SP" "hop -c ${ac_fl} eks"
	ac_fcase "ws ${ac_fl}" . "HOP_WORKSPACES=${(q)AC_WS} hop -w ${ac_fl} strava"
	ac_fcase "repos ${ac_fl}" . "HOP_WORKSPACES=${(q)AC_WS} hop -R ${ac_fl} strava/conf"
	ac_fcase "empty ${ac_fl}" sandbox/abg "hop -k sbx -c ${ac_fl}"
done
# Exclusive and malformed combinations, each refused with exit 2 before anything is enumerated.
ac_fcase 'excl -o -e' . 'hop -o -e vpc'
ac_fcase 'excl -e -o' . 'hop --reveal --open vpc'
ac_fcase 'excl --action -o' . 'hop --action=open -o vpc'
ac_fcase 'excl --action --cd' . 'hop --cd --action=open vpc'
ac_fcase 'bad --action=bogus' . 'hop --action=bogus vpc'
ac_fcase 'bad --action' . 'hop --action open vpc'
ac_fcase 'bad --action=' . 'HOP_ACTION=open hop --action= eks security'
ac_fcase 'bad --action= -o' . 'hop --action= -o eks security'
ac_fcase 'slash -o' . 'hop / -o'
ac_fcase 'slash first -o' . 'hop -o /'
ac_fcase 'dash -e' . 'hop - -e'
ac_fcase 'dash first -e' . 'hop -e -'
# HOP_ACTION from the environment, then overridden for one call by a flag.
ac_fcase 'env cd+reveal' . 'HOP_ACTION=cd+reveal hop eks security'
ac_fcase 'env cd+reveal --cd' . 'HOP_ACTION=cd+reveal hop --cd eks security'
ac_fcase 'env open -e' . 'HOP_ACTION=open hop -e eks security'
ac_fcase 'env bogus' . 'HOP_ACTION=bogus hop eks security'
# Navigation by name stays a pure cd, whatever HOP_ACTION says.
ac_fcase 'hopr open' "$AC_SP" 'HOP_ACTION=open hopr'
ac_fcase 'hop / open' "$AC_SP" 'HOP_ACTION=open hop /'
ac_fcase 'hopw open' "$AC_WSH/strava/configuration" "HOP_WORKSPACES=${(q)AC_WS} HOP_ACTION=open hopw"
# Every way a jump happens, each under a mode that calls code: T0 dir and file, J2, and a dir with no top file.
ac_fcase 'T0 dir -o' . 'hop -o terraform/acct-security-tooling-prod'
ac_fcase 'T0 dir -e' . 'hop -e terraform/acct-security-tooling-prod'
ac_fcase 'T0 file -o' . 'hop -o kubernetes/services/monitoring/grafana.yaml'
ac_fcase 'T0 file --cd -e' . 'hop --cd -e kubernetes/services/monitoring/grafana.yaml'
ac_fcase 'J2 -e' . 'hop -e security-tooling-prod'
ac_fcase 'J2 --cd -e' . 'hop --cd -e security-tooling-prod'
ac_fcase 'kubernetes/values -e' . 'hop -e kubernetes/values'
ac_fcase 'kubernetes/values --cd -e' . 'hop --cd -e kubernetes/values'

typeset AC_FOUT
AC_FOUT=$(hop_bound 120 zsh -f -c "$(fixture_pins)
source ${(q)HOP_HOME}/hop.zsh || exit 97
source ${(q)AC_WORK}/flags.zsh
ac_flags ${(q)AC_FCASES} ${(q)AC_MT} ${(q)AC_WORK}/ferr")
typeset -A AC_F
for ac_line in "${(@f)AC_FOUT}"; do
	ac_f=("${(@ps:\t:)ac_line}")
	AC_F[${ac_f[1]}]="${ac_f[2]}"$'\t'"${ac_f[3]}"$'\t'"${ac_f[4]-}"$'\t'"${ac_f[5]-}"
done

# ac_flag_want <label> <status> <pwd> <calls> [stderr-needle] -> assert one flag case, inside the open test.
ac_flag_want() {
	emulate -L zsh
	local got=${AC_F[$1]-}
	if [[ -z $got ]]; then
		_hop_t_bad "no result for case: $1"
		return 1
	fi
	local -a g=("${(@ps:\t:)got}")
	assert_eq "$4" "${g[3]-}" "$1: the code calls; stderr: ${g[4]-}"
	assert_eq "$2" "${g[1]}" "$1: the status; stderr: ${g[4]-}"
	assert_eq "$3" "${g[2]}" "$1: the shell's directory afterwards"
	[[ -n ${5:-} ]] && assert_contains "${g[4]-}" "$5" "$1: stderr"
	return 0
}

t 'flags: the probe ran every flag case'
assert_eq "${#${(f)$(ac_slurp "$AC_FCASES")}}" "${#AC_F}" 'a flag case went missing'

# Per flag: whether it cds, and the code call for a tg leaf, a workspace or repo, and the abg dir.
# - eks's preview is main.tf, so reveal names that file and open names the dir.
# - abg's preview is its README, which is a file under the dir, so reveal reveals it.
typeset -A AC_FLAG_CD=(
	'-o' 0 '-e' 0 '--cd' 1 '--cd -o' 1 '--cd -e' 1 '--action=cd+reveal' 1
)
typeset -A AC_FLAG_VERB=(
	'-o' open '-e' reveal '--cd' '' '--cd -o' open '--cd -e' reveal '--action=cd+reveal' reveal
)
typeset ac_d ac_p ac_want ac_pwd ac_sh
typeset -a ac_shapes=(plain kinds all cwd ws repos empty)
for ac_fl in "${AC_FLAGS[@]}"; do
	t "flags: ${ac_fl} sets the matching mode, alone and with -k, -a, -c, -w, -R and an empty query"
	for ac_sh in "${ac_shapes[@]}"; do
		case $ac_sh in
			plain|kinds|all|cwd) ac_d=$AC_EKS ac_p=$AC_EKS/main.tf ;;
			ws) ac_d=$AC_WSH/strava ac_p='' ;;
			repos) ac_d=$AC_WSH/strava/configuration ac_p='' ;;
			empty) ac_d=$AC_MT/sandbox/abg ac_p=$AC_MT/sandbox/abg/README.md ;;
		esac
		ac_pwd=$AC_MT
		[[ $ac_sh == cwd ]] && ac_pwd=$AC_MT/$AC_SP
		[[ $ac_sh == empty ]] && ac_pwd=$AC_MT/sandbox/abg
		(( ${AC_FLAG_CD[$ac_fl]} )) && ac_pwd=$ac_d
		case ${AC_FLAG_VERB[$ac_fl]}:$ac_sh in
			:*) ac_want='' ;;
			*:ws|*:repos) ac_want="code -n ${ac_d}" ;;
			open:*) ac_want="code -n ${ac_d}" ;;
			reveal:*) ac_want="code -r ${ac_p}" ;;
		esac
		ac_flag_want "${ac_sh} ${ac_fl}" 0 "$ac_pwd" "$ac_want"
	done
done

t 'flags: -o and -e are exclusive, either way round'
ac_flag_want 'excl -o -e' 2 "$AC_MT" '' 'hop: -o and -e are exclusive'
ac_flag_want 'excl -e -o' 2 "$AC_MT" '' 'hop: -o and -e are exclusive'

t 'flags: --action cannot be mixed with --cd, -o or -e'
ac_flag_want 'excl --action -o' 2 "$AC_MT" '' 'cannot be combined with --cd, -o or -e'
ac_flag_want 'excl --action --cd' 2 "$AC_MT" '' 'cannot be combined with --cd, -o or -e'

t 'flags: an unknown --action mode, or --action with no MODE, is refused'
ac_flag_want 'bad --action=bogus' 2 "$AC_MT" '' 'hop: --action=bogus is not one of cd, open, reveal, cd+open, cd+reveal'
ac_flag_want 'bad --action' 2 "$AC_MT" '' 'hop: --action needs a mode'
ac_flag_want 'bad --action=' 2 "$AC_MT" '' 'hop: --action needs a mode'
ac_flag_want 'bad --action= -o' 2 "$AC_MT" '' 'hop: --action needs a mode'

t 'flags: hop / and hop - still refuse every other argument, an action flag included'
ac_flag_want 'slash -o' 2 "$AC_MT" '' 'hop: / takes no other arguments'
ac_flag_want 'slash first -o' 2 "$AC_MT" '' 'hop: / takes no other arguments'
ac_flag_want 'dash -e' 2 "$AC_MT" '' 'hop: - takes no other arguments'
ac_flag_want 'dash first -e' 2 "$AC_MT" '' 'hop: - takes no other arguments'

t 'HOP_ACTION from the environment sets the mode, and a flag replaces it for the call'
ac_flag_want 'env cd+reveal' 0 "$AC_EKS" "code -r ${AC_EKS}/main.tf"
ac_flag_want 'env cd+reveal --cd' 0 "$AC_EKS" ''
ac_flag_want 'env open -e' 0 "$AC_MT" "code -r ${AC_EKS}/main.tf"

t 'an invalid HOP_ACTION warns exactly once and cds'
ac_flag_want 'env bogus' 0 "$AC_EKS" '' 'hop: HOP_ACTION=bogus is not one of cd, open, reveal, cd+open, cd+reveal; using cd'
typeset -a ac_g=("${(@ps:\t:)${AC_F[env bogus]-}}")
typeset -a ac_warn=("${(@s: / :)${ac_g[4]-}}")
ac_warn=(${(M)ac_warn:#*HOP_ACTION=bogus*})
assert_eq 1 "${#ac_warn}" 'the warning repeated'

t 'hopr, hop / and hopw are navigation by name, so HOP_ACTION=open still only cds'
ac_flag_want 'hopr open' 0 "$AC_MT" ''
ac_flag_want 'hop / open' 0 "$AC_MT" ''
ac_flag_want 'hopw open' 0 "$AC_WSH/strava" ''

# The account dir has no README and one file at its top, which is what the real terraform account dirs look like.
t 'a literal path jumps with the mode: a dir opens with -n and reveals its top file, a file opens with -r'
ac_flag_want 'T0 dir -o' 0 "$AC_MT" "code -n ${AC_MT}/terraform/acct-security-tooling-prod"
ac_flag_want 'T0 dir -e' 0 "$AC_MT" "code -r ${AC_MT}/terraform/acct-security-tooling-prod/terragrunt_aws_account.hcl"
ac_flag_want 'T0 file -o' 0 "$AC_MT" "code -r ${AC_MT}/kubernetes/services/monitoring/grafana.yaml"
ac_flag_want 'T0 file --cd -e' 0 "$AC_MT/kubernetes/services/monitoring" "code -r ${AC_MT}/kubernetes/services/monitoring/grafana.yaml"

t 'a J2 directory jump reveals the account dir'"'"'s top file, with the note, and --cd keeps the cd'
ac_flag_want 'J2 -e' 0 "$AC_MT" "code -r ${AC_MT}/terraform/acct-security-tooling-prod/terragrunt_aws_account.hcl" 'hop: security-tooling-prod -> terraform/acct-security-tooling-prod/'
ac_flag_want 'J2 --cd -e' 0 "$AC_MT/terraform/acct-security-tooling-prod" "code -r ${AC_MT}/terraform/acct-security-tooling-prod/terragrunt_aws_account.hcl"

t 'reveal on a dir with no file at its top explains itself: a failure alone, a note after a cd'
ac_flag_want 'kubernetes/values -e' 1 "$AC_MT" '' 'hop: nothing to reveal at the top of kubernetes/values/; use -o to open it as a folder'
ac_flag_want 'kubernetes/values --cd -e' 0 "$AC_MT/kubernetes/values" '' 'hop: nothing to reveal at the top of kubernetes/values/'

# HOP_ACTION in config.zsh wins over the environment, because config is sourced after lib/actions.zsh sets the default.
t 'HOP_ACTION set in config.zsh is honoured over the environment, and --cd still replaces it'
typeset AC_CFG2="$AC_WORK/config-action.zsh"
print -rl -- "$(ac_slurp "$HOP_FIX_CONFIG")" 'typeset -g HOP_ACTION=cd+reveal' > "$AC_CFG2"
: > "$AC_FCASES"
ac_fcase 'config' . 'hop eks security'
ac_fcase 'config --cd' . 'hop --cd eks security'
AC_FOUT=$(hop_bound 60 zsh -f -c "$(fixture_pins "HOP_CONFIG=$AC_CFG2" HOP_ACTION=open)
source ${(q)HOP_HOME}/hop.zsh || exit 97
source ${(q)AC_WORK}/flags.zsh
ac_flags ${(q)AC_FCASES} ${(q)AC_MT} ${(q)AC_WORK}/ferr")
AC_F=()
for ac_line in "${(@f)AC_FOUT}"; do
	ac_f=("${(@ps:\t:)ac_line}")
	AC_F[${ac_f[1]}]="${ac_f[2]}"$'\t'"${ac_f[3]}"$'\t'"${ac_f[4]-}"$'\t'"${ac_f[5]-}"
done
ac_flag_want 'config' 0 "$AC_EKS" "code -r ${AC_EKS}/main.tf"
ac_flag_want 'config --cd' 0 "$AC_EKS" ''

# ---------------------------------------------------------------------------
# The picker's always-cd key, with a stub that selects instead of drawing.
# ---------------------------------------------------------------------------
# ac_pickrun <stubdir> <hop-code> [VAR=value...] -> hop with a terminal assumed and the selecting stub as fzf.
ac_pickrun() {
	emulate -L zsh
	local stub=$1 code=$2
	shift 2
	hop_bound 30 zsh -f -c "$(fixture_pins "$@")
export PATH=${(q)stub}:\$PATH
source ${(q)HOP_HOME}/hop.zsh || exit 97
_hop_tty_ok() { return 0 }
builtin cd -q -- ${(q)AC_MT} || exit 96
${code}
print -r -- \"PWD=\$PWD\"" 2>&1
}

typeset AC_STUB
typeset -a AC_IN AC_R2
stub_fzf_select alt-enter 2
AC_STUB=$REPLY
stub_reset
AC_RUN=$(ac_pickrun "$AC_STUB" 'hop vpc' HOP_ACTION=open)
AC_IN=("${(@f)$(ac_slurp "$AC_STUB/stdin")}")
AC_R2=("${(@ps:\t:)AC_IN[2]}")
t 'picker: alt-enter on row 2 under HOP_ACTION=open cds there and calls no code'
assert_nonempty "${AC_R2[2]-}" 'the picker never ran, so nothing below means anything'
assert_contains "$AC_RUN" "PWD=${AC_R2[2]-}"
assert_empty "$(stub_calls code)" 'alt-enter is the always-cd key, so it must not reach code'

stub_fzf_select '' 2
AC_STUB=$REPLY
stub_reset
AC_RUN=$(ac_pickrun "$AC_STUB" 'hop vpc' HOP_ACTION=open)
AC_IN=("${(@f)$(ac_slurp "$AC_STUB/stdin")}")
AC_R2=("${(@ps:\t:)AC_IN[2]}")
t 'picker: Enter on row 2 under HOP_ACTION=open opens its dir and leaves the shell where it was'
assert_contains "$AC_RUN" "PWD=$AC_MT"
assert_eq "code	-n	${AC_R2[2]-}" "$(stub_calls code)"
