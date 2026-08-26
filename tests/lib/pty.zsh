#!/usr/bin/env zsh
# hop pty harness: drive the REAL interactive picker through a synthetic terminal.
# - This is the only place in tests/ allowed to start fzf without --filter.
# - Everything here was derived by execution, so the comments record what failed, not theory.
# - fzf in --height mode emits ESC[6n and blocks forever on a report zpty never sends.
# - So HOP_FZF_HEIGHT='' forces fullscreen, and that alone is what makes the picker runnable here.
# - Nothing reads the pty's output side, so fzf fills the buffer, blocks in write() and DROPS keys.
# - pty_settle therefore drains continuously; that drain is load-bearing, not hygiene.
# - zsh/zpty cannot set the window size (no TIOCSWINSZ), so the rendered UI is never usable.
# - Assertions read only the trace file, the stub log, and the child's final $PWD. Never the screen.
# - fzf reports its own state instead, through FZF_DEFAULT_OPTS binds on focus, change and result.
# - Those write $FZF_PROMPT, which IS hop's mode variable, to a file that no ANSI can corrupt.
# - hop binds none of those three events, and a default-opts bind for an unmentioned event survives.

typeset -g  HOP_PTY_NAME=HOPPTY
typeset -g  HOP_PTY_WORK=''
typeset -g  HOP_PTY_TRACE=''
typeset -g  HOP_PTY_ERR=''
typeset -g  HOP_PTY_PWDF=''
typeset -g  HOP_PTY_PIDF=''
typeset -g  HOP_PTY_REPO=''
typeset -g  HOP_PTY_SHARED=''
typeset -ga HOP_PTY_PIDS=()

# The fixture's four scopes, in the order `hop -k tg` lists them. Neutral names on purpose.
typeset -ga HOP_PTY_ROWS=(alpha bravo charlie delta)
# This suite's own process group, so a reap can never target the process doing the reaping.
typeset -g  HOP_PTY_SELFPG=''
# Trace line count, kept in a variable because a barrier must not fork on every poll.
typeset -gi HOP_PTY_N=0
# What the canary's fzf actually returned, so the gate's own test can assert on it.
typeset -g  HOP_PTY_CANARY=''

# Seconds a key with no observable event is given to land. Raise it on a loaded runner.
typeset -gF HOP_PTY_SETTLE=${HOP_PTY_SETTLE:-0.25}
# Ceiling on every poll, so a wedged fzf fails one test instead of eating the suite's alarm.
typeset -gF HOP_PTY_WAIT=${HOP_PTY_WAIT:-10}
# How long the trace must stop growing before a state read counts as settled.
# - The one timing value a caller could not override, and the only one that can go WRONG rather
#   than merely slow: too short and pty_quiesce reads a half-applied action chain.
typeset -gF HOP_PTY_QUIET=${HOP_PTY_QUIET:-0.2}

# pty_supported -> 0 when zsh/zpty loads. The suite skips everything when this fails.
# - Also the one place the suite's own process group is recorded, before any child exists.
pty_supported() {
	emulate -L zsh
	local REPLY
	_hop_pty_pgid $$ && HOP_PTY_SELFPG=$REPLY
	zmodload zsh/zpty 2>/dev/null
}

# _hop_pty_drain -> swallow whatever the pty has produced so far, never blocking.
# - An undrained pty wedges fzf mid-write, and the keystrokes typed after that are lost silently.
_hop_pty_drain() {
	local junk
	while zpty -r -t "$HOP_PTY_NAME" junk 2>/dev/null; do :; done
	return 0
}

# pty_settle [seconds] -> let the child work for a while, draining the whole time.
pty_settle() {
	emulate -L zsh
	local -F want=${1:-$HOP_PTY_SETTLE} spent=0
	while (( spent < want )); do
		_hop_pty_drain
		sleep 0.02
		(( spent += 0.02 ))
	done
	return 0
}

# _hop_pty_lines -> REPLY_A holds the trace file's non-empty lines.
_hop_pty_lines() {
	emulate -L zsh
	REPLY_A=()
	[[ -r ${HOP_PTY_TRACE:-} ]] || return 1
	REPLY_A=("${(@f)$(<"$HOP_PTY_TRACE")}")
	REPLY_A=(${REPLY_A:#})
	return 0
}

# pty_wait_lines <n> -> poll until the trace holds at least n lines, draining as it goes.
# - This is both the readiness barrier and the per-key barrier. Never a fixed sleep.
pty_wait_lines() {
	emulate -L zsh
	local -i want=$1
	local -F spent=0
	local -a REPLY_A
	while (( spent < HOP_PTY_WAIT )); do
		_hop_pty_drain
		_hop_pty_lines && (( $#REPLY_A >= want )) && return 0
		sleep 0.02
		(( spent += 0.02 ))
	done
	return 1
}

# pty_trace -> the whole trace, for a failure message.
pty_trace() {
	emulate -L zsh
	local -a REPLY_A
	_hop_pty_lines || return 1
	print -rl -- "${REPLY_A[@]}"
}

# _hop_pty_n -> HOP_PTY_N is the current trace line count, set without forking a subshell.
_hop_pty_n() {
	emulate -L zsh
	local -a REPLY_A
	_hop_pty_lines
	HOP_PTY_N=$#REPLY_A
	return 0
}

# pty_count -> the same number, printed, for a probe that wants it in a substitution.
pty_count() {
	emulate -L zsh
	_hop_pty_n
	print -r -- $HOP_PTY_N
}

# pty_quiesce [quiet] -> return once the trace has stopped growing for `quiet` seconds.
# - "+1 trace line" is the WRONG barrier: one keystroke fires several events, not one.
# - `:` proved it. The focus event arrives with the OLD prompt, and change-prompt lands later.
# - Reading state after +1 line therefore sampled a half-applied action chain, and was flaky.
# - Waiting for quiet instead means every assertion reads a settled state.
pty_quiesce() {
	emulate -L zsh
	local -F quiet=${1:-$HOP_PTY_QUIET} spent=0 still=0
	local -i last
	_hop_pty_n
	last=$HOP_PTY_N
	while (( spent < HOP_PTY_WAIT )); do
		_hop_pty_drain
		sleep 0.02
		(( spent += 0.02 ))
		_hop_pty_n
		if (( HOP_PTY_N == last )); then
			(( still += 0.02 ))
			(( still >= quiet )) && return 0
		else
			last=$HOP_PTY_N
			still=0
		fi
	done
	return 1
}

# pty_last [kind] -> the newest trace line, optionally only of kind F, C or R.
pty_last() {
	emulate -L zsh
	local -a REPLY_A
	_hop_pty_lines || return 1
	local -a want=("${REPLY_A[@]}")
	[[ -n ${1:-} ]] && want=(${(M)want:#$1 *})
	(( $#want )) || return 1
	print -r -- "${want[-1]}"
}

# pty_get <field> [kind] -> one bracketed field out of the newest trace line.
# - Bracketed rather than tab-separated because an EMPTY query is the interesting case here.
# - zsh's `read` collapses the repeated tabs an empty field produces, which loses the field.
pty_get() {
	emulate -L zsh
	local line
	line=$(pty_last "${2:-}") || return 1
	local v=${line#*"${1}=["}
	[[ $v == "$line" ]] && return 1
	print -r -- "${v%%]*}"
}

# pty_err -> whatever the child wrote to stderr, which is where hop's own messages land.
pty_err() {
	emulate -L zsh
	[[ -r ${HOP_PTY_ERR:-} ]] || return 1
	print -rn -- "$(<"$HOP_PTY_ERR")"
}

# pty_pwd -> the child's $PWD after the picker exited, or empty while it is still running.
pty_pwd() {
	emulate -L zsh
	[[ -r ${HOP_PTY_PWDF:-} ]] || return 0
	print -rn -- "$(<"$HOP_PTY_PWDF")"
}

# pty_wait_exit -> poll until the child records its final $PWD, meaning hop returned.
pty_wait_exit() {
	emulate -L zsh
	local -F spent=0
	while (( spent < HOP_PTY_WAIT )); do
		_hop_pty_drain
		[[ -s ${HOP_PTY_PWDF:-} ]] && return 0
		sleep 0.02
		(( spent += 0.02 ))
	done
	return 1
}

# pty_calls [name] -> the stub binaries this session recorded, newest last.
pty_calls() {
	emulate -L zsh
	local log="${HOP_PTY_WORK}/calls.log"
	[[ -r $log ]] || return 1
	local -a lines=("${(@f)$(<"$log")}")
	lines=(${lines:#})
	(( $# )) && lines=(${(M)lines:#$1$'\t'*})
	print -rl -- "${lines[@]}"
	return 0
}

# _hop_pty_shared -> REPLY is a dir holding the trace script, the stub bins and the driver.
# - Built once per suite: none of the three depends on the session, only their output paths do.
_hop_pty_shared() {
	emulate -L zsh
	if [[ -n $HOP_PTY_SHARED ]]; then
		REPLY=$HOP_PTY_SHARED
		return 0
	fi
	local REPLY
	fixture_tmpdir ptyshared || return 1
	HOP_PTY_SHARED=$REPLY

	print -rl -- '#!/bin/sh' \
		'# hop pty trace: fzf reporting its own state, which no screen scrape could do reliably.' \
		"printf '%s prompt=[%s] pos=[%s] count=[%s] query=[%s] state=[%s]\\n' \\" \
		'  "$1" "$FZF_PROMPT" "$FZF_POS" "$FZF_MATCH_COUNT" "$FZF_QUERY" "$FZF_INPUT_STATE" \' \
		'  >> "$HOP_PTY_TRACE"' > "$HOP_PTY_SHARED/trace.sh"
	chmod +x "$HOP_PTY_SHARED/trace.sh" || return 1

	# Each stub reads $HOP_FIX_LOG at CALL time, so a per-session value is all the isolation needed.
	local n
	for n in code gh bat pbcopy pbpaste open editor vim nvim wl-copy xclip xsel; do
		print -rl -- '#!/bin/sh' \
			'# hop pty stub: records the call and exits 0, so nothing reaches the desktop.' \
			'# ONE append per call, because a concurrent stub used to interleave inside the line.' \
			'# - This wrote the name, then each argument, then the newline, as 2+N separate appends.' \
			'# - The preview pane runs the bat stub on every render, so a second call really does land mid-line.' \
			'# - Measured: it recorded `batgh browse` for `gh browse`, which read as a verb that never ran.' \
			'# - The FORMAT is built from literals only and every byte of data stays in the arguments.' \
			'fmt="%s"' \
			'for a in "$@"; do fmt="$fmt\t%s"; done' \
			"printf \"\$fmt\\n\" '${n}' \"\$@\" >> \"\$HOP_FIX_LOG\"" \
			'exit 0' > "$HOP_PTY_SHARED/$n"
		chmod +x "$HOP_PTY_SHARED/$n" || return 1
	done

	print -rl -- \
		'# hop pty driver: runs inside the pty, and is the only thing that starts real hop.' \
		'print -r -- $$ > "$HOP_PTY_PIDF"' \
		'source "$HOP_HOME/hop.zsh" || exit 97' \
		'builtin cd -q -- "$HOP_PTY_REPO" || exit 96' \
		'eval "$HOP_PTY_CMD" 2> "$HOP_PTY_ERR"' \
		'print -r -- "$PWD" > "$HOP_PTY_PWDF"' > "$HOP_PTY_SHARED/driver.zsh"

	REPLY=$HOP_PTY_SHARED
	return 0
}

# pty_fixture_repo -> REPLY is a committed repo of four neutrally named terragrunt units.
# - Built once per suite: a git init per test costs more than every keystroke in it.
# - The `tg` layout is scope/name under terraform/, so the four scopes ARE the four rows in order.
# - Every test drives `hop -k tg` for that reason: one kind means row 1 is alpha and row 2 is bravo.
pty_fixture_repo() {
	emulate -L zsh
	if [[ -n $HOP_PTY_REPO ]]; then
		REPLY=$HOP_PTY_REPO
		return 0
	fi
	fixture_repo ptyrepo || return 1
	local d
	for d in "${HOP_PTY_ROWS[@]}"; do
		fixture_write "terraform/${d}/vpc/terragrunt.hcl" "# unit ${d}" || return 1
	done
	fixture_commit 'pty fixture' || return 1
	HOP_PTY_REPO=$HOP_FIX_REPO
	REPLY=$HOP_PTY_REPO
	return 0
}

# pty_row <n> -> the directory the nth row of `hop -k tg` cds to.
pty_row() {
	emulate -L zsh
	print -rn -- "${HOP_PTY_REPO}/terraform/${HOP_PTY_ROWS[$1]}/vpc"
}

# pty_open [hop-command] -> start the picker under a pty and block until its first focus event.
# - Non-zero means the picker never reported ready, which every test treats as a failure.
pty_open() {
	emulate -L zsh
	local cmd=${1:-hop}
	pty_close

	local REPLY
	_hop_pty_shared || return 1
	local shared=$REPLY
	pty_fixture_repo || return 1
	fixture_tmpdir ptyrun || return 1
	HOP_PTY_WORK=$REPLY
	HOP_PTY_TRACE="$HOP_PTY_WORK/trace"
	HOP_PTY_ERR="$HOP_PTY_WORK/err"
	HOP_PTY_PWDF="$HOP_PTY_WORK/pwd"
	HOP_PTY_PIDF="$HOP_PTY_WORK/pid"
	: > "$HOP_PTY_TRACE"
	: > "$HOP_PTY_ERR"
	: > "$HOP_PTY_WORK/calls.log"

	export HOP_PTY_TRACE HOP_PTY_ERR HOP_PTY_PWDF HOP_PTY_PIDF HOP_PTY_REPO
	export HOP_PTY_CMD=$cmd
	export HOP_FIX_LOG="$HOP_PTY_WORK/calls.log"

	# The bind spec MUST be shell-quoted INSIDE the variable, which is not obvious and not optional.
	# - `--bind=focus:execute-silent(true)` gives rc=2 and `invalid command line string`.
	export FZF_DEFAULT_OPTS="--bind 'focus:execute-silent(${shared}/trace.sh F)'"
	FZF_DEFAULT_OPTS+=" --bind 'change:execute-silent(${shared}/trace.sh C)'"
	FZF_DEFAULT_OPTS+=" --bind 'result:execute-silent(${shared}/trace.sh R)'"

	zpty -b "$HOP_PTY_NAME" "zsh -f ${shared}/driver.zsh" || return 1

	# Register the pid BEFORE the readiness barrier, not after.
	# - A picker that never becomes ready is exactly the one that needs reaping.
	# - Only this list survives into the EXIT trap, so an early return must not skip it.
	local -F spent=0
	while (( spent < HOP_PTY_WAIT )); do
		[[ -s $HOP_PTY_PIDF ]] && break
		sleep 0.02
		(( spent += 0.02 ))
	done
	[[ -s $HOP_PTY_PIDF ]] && HOP_PTY_PIDS+=("$(<"$HOP_PTY_PIDF")")

	pty_wait_lines 1 || return 1
	return 0
}

# pty_key <key> [expected-trace-lines] -> one keystroke, then wait for it to have landed.
# - ALWAYS `zpty -w -n`: without -n zpty appends a newline, so the key arrives as key+Enter.
# - That silently means `accept`, and it corrupted three spikes with phantom off-by-ones.
# - One key per write with a settle: a batched zero-sleep send produced `ctrl-o|alpha` for `charlie`.
# - Passing the expected count returns as soon as the event lands, which beats any sleep on both axes.
pty_key() {
	emulate -L zsh
	local key=$1 want=${2:-}
	case $key in
		esc) key=$'\e' ;;
		enter) key=$'\r' ;;
		space) key=' ' ;;
	esac
	zpty -w -n "$HOP_PTY_NAME" "$key" || return 1
	# With a barrier the caller owns the settling, so do NOT sleep here as well.
	[[ -n $want ]] && { pty_wait_lines "$want"; return $? }
	pty_settle
}

# pty_key_ev <key> -> send a key that MUST move fzf's state, then wait for the state to settle.
# - Waits for the first event as a liveness check, then for quiet, so the read is of a final state.
pty_key_ev() {
	emulate -L zsh
	_hop_pty_n
	pty_key "$1" $(( HOP_PTY_N + 1 )) || return 1
	pty_quiesce
}

# _hop_pty_pgid <pid> -> REPLY is that pid's process group, or empty when ps cannot say.
# - The driver is NOT the group leader: zpty forks an intermediate that leads the group.
# - So `kill -- -$driverpid` names a group that does not exist and is a silent no-op.
_hop_pty_pgid() {
	emulate -L zsh
	REPLY=''
	local v
	v=$(ps -o pgid= -p "$1" 2>/dev/null) || return 1
	v=${v//[[:space:]]/}
	[[ $v == <-> ]] || return 1
	REPLY=$v
	return 0
}

# _hop_pty_tree <root-pid> -> REPLY_A is root plus every descendant, found through ppid.
# - A process-group kill is not enough: fzf puts its preview children in their OWN group.
# - Measured here: the group held 4 processes while the ppid tree held 6.
# - Snapshot BEFORE killing anything, or an orphan reparents to init and becomes unfindable.
_hop_pty_tree() {
	emulate -L zsh
	local root=$1
	REPLY_A=($root)
	local -a pairs frontier next
	pairs=("${(@f)$(ps -A -o pid=,ppid= 2>/dev/null)}")
	frontier=($root)
	local line pid ppid
	while (( $#frontier )); do
		next=()
		for line in "${pairs[@]}"; do
			pid=${${=line}[1]}
			ppid=${${=line}[2]}
			[[ $pid == <-> && $ppid == <-> ]] || continue
			(( ${frontier[(I)$ppid]} )) || continue
			next+=($pid)
			REPLY_A+=($pid)
		done
		frontier=($next)
	done
	return 0
}

# _hop_pty_kill <pid> -> KILL the driver's real group, then anything that escaped it.
# - KILL and never TERM, for two independent reasons, both measured here.
# - A hung fzf traps TERM while in raw mode and simply survives it.
# - Worse, zpty's forked intermediate still carries THIS SUITE'S EXIT trap.
# - TERM therefore ran fixture_cleanup inside that fork and deleted the fixture repo mid-suite.
# - SIGKILL cannot be trapped, so it cannot run an inherited trap in somebody else's fork.
# - The self-group guard is what stops a bad ps reading from killing the suite itself.
_hop_pty_kill() {
	emulate -L zsh
	local p=$1
	[[ $p == <-> ]] || return 0
	local REPLY
	local -a REPLY_A
	local pg=''
	_hop_pty_pgid "$p" && pg=$REPLY
	[[ -n $HOP_PTY_SELFPG && $pg == $HOP_PTY_SELFPG ]] && pg=''
	_hop_pty_tree "${pg:-$p}"
	local -a doomed=(${REPLY_A:#(1|$$)})
	[[ -n $pg ]] && kill -KILL -$pg 2>/dev/null
	(( $#doomed )) && kill -KILL "${doomed[@]}" 2>/dev/null
	return 0
}

# pty_close -> reap the child's whole process group, then drop the pty.
# - `zpty -d` was proven NOT to reap: it leaves fzf orphaned and hung, reparented to init.
# - The driver records its own $$, which _hop_pty_kill resolves to the real group; it is NOT one.
pty_close() {
	emulate -L zsh
	local p=''
	[[ -s ${HOP_PTY_PIDF:-} ]] && read -r p < "$HOP_PTY_PIDF"
	if [[ -n $p ]]; then
		_hop_pty_kill "$p"
		HOP_PTY_PIDS=(${HOP_PTY_PIDS:#$p})
	fi
	zpty -d "$HOP_PTY_NAME" 2>/dev/null
	HOP_PTY_PIDF=''
	return 0
}

# pty_reap_all -> last-resort cleanup for every session this suite ever opened.
# - The runner's own alarm is a backstop, not a substitute: this must leave it nothing to find.
pty_reap_all() {
	emulate -L zsh
	local p
	for p in "${HOP_PTY_PIDS[@]}"; do
		_hop_pty_kill "$p"
	done
	HOP_PTY_PIDS=()
	zpty -d 2>/dev/null
	return 0
}

# _hop_pty_onexit -> the runner's own EXIT trap is REPLACED by this, so it is restated in full.
# - Reaping has to survive the suite dying, because an unreaped fzf hangs on its pty forever.
_hop_pty_onexit() {
	(( ${+functions[_hop_t_report]} )) && _hop_t_report
	pty_reap_all
	(( ${+functions[fixture_cleanup]} )) && fixture_cleanup
	return 0
}
trap _hop_pty_onexit EXIT INT TERM

# pty_env -> pin HOME, the XDG roots and every hop path at throwaway values, once.
# - The real ~/.config/hop is personal, so reading it would make results depend on whose laptop ran.
# - Call it AFTER the fixture repo exists, because git needs a sane HOME to init one.
pty_env() {
	emulate -L zsh
	local REPLY
	_hop_pty_shared || return 1
	fixture_tmpdir ptyhome || return 1
	export HOME=$REPLY
	mkdir -p "$HOME/.config" "$HOME/.local/state" "$HOME/.cache" || return 1
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XDG_CACHE_HOME="$HOME/.cache"
	export HOP_CONFIG="$HOP_FIX_NOCONFIG"
	export HOP_HISTFILE=/dev/null
	export HOP_HOPRC=''
	export HOP_VIM=1
	# Empty, not unset: this is the one flag that keeps ESC[6n out of the pty.
	export HOP_FZF_HEIGHT=''
	export EDITOR="${HOP_PTY_SHARED}/editor" VISUAL="${HOP_PTY_SHARED}/editor"

	# Every OTHER variable hop reads, pinned because the zpty child inherits this environment.
	# - This is the class a grep for `/Users` cannot find: a needle built from the parent's env.
	# - All of these use `:-` in hop, so empty means "use hop's own default", not "use nothing".
	# - HOP_FZF_MIN empty therefore keeps the product's real floor rather than restating it here.
	# - WORKSPACES_FILE and DEBUG_LOG are pinned explicitly, not left to the XDG roots above,
	#   because an exported value overrides those and would read the user's real, private config.
	export HOP_DEBUG='' HOP_DEBUG_LOG="$HOME/.local/state/hop/debug.log"
	export HOP_WORKSPACES='' HOP_WORKSPACES_FILE="$HOME/.config/hop/workspaces"
	export HOP_REPOS='' HOP_DEFAULT_KINDS='' HOP_CLIPBOARD='' HOP_HIST_MAX='' HOP_FZF_MIN=''
	# The newest variable hop reads, and the one a developer is most likely to have exported by hand.
	# - Empty keeps bin/hop-guard's own 150ms default, exactly as HOP_FZF_MIN above keeps fzf's floor.
	# - Left unpinned, an exported HOP_GUARD_WINDOW=0 turns seven suite_pty_escape negatives red.
	export HOP_GUARD_WINDOW=''
	# fzf's own inherited settings: OPTS is rebuilt per session in pty_open, COMMAND is never wanted.
	export FZF_DEFAULT_COMMAND=''
	# PATH is exported here rather than through stub_bin, because PATH is what the zpty child gets.
	# - An audit found a `local PATH` does not survive the fork to `zsh -f`, so it must be global.
	export PATH="${HOP_PTY_SHARED}:$PATH"
	return 0
}

# pty_canary -> 0 when a real keystroke reaches fzf and print()+accept comes back out.
# - Deliberately mirrors hop's own mechanism, since every letter verb is print(key)+accept.
# - This is the gate: a runner that loses pty capability must turn CI RED, not skip 8 tests.
# - It uses no trace script, so the gate does not depend on the trace contract as well.
pty_canary() {
	emulate -L zsh
	local REPLY
	fixture_tmpdir ptycanary || return 1
	local w=$REPLY
	print -rl -- alpha bravo > "$w/list"
	zpty -b "$HOP_PTY_NAME" "fzf --no-height --layout=reverse --bind 'o:print(ctrl-o)+accept' < ${w}/list > ${w}/out 2> ${w}/err" || return 1
	pty_settle 0.4
	zpty -w -n "$HOP_PTY_NAME" 'o'
	local -F spent=0
	while (( spent < HOP_PTY_WAIT )); do
		_hop_pty_drain
		[[ -s $w/out ]] && break
		sleep 0.02
		(( spent += 0.02 ))
	done
	zpty -d "$HOP_PTY_NAME" 2>/dev/null
	HOP_PTY_CANARY=''
	[[ -r $w/out ]] && read -r HOP_PTY_CANARY < "$w/out"
	[[ $HOP_PTY_CANARY == ctrl-o ]]
}
