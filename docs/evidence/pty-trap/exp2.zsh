#!/usr/bin/env zsh
# Task #43 experiment 1: does the zpty intermediate fork run an inherited EXIT trap?
# - Mirrors pty_canary's exact shape: zpty -b with a real fzf that ACCEPTS and exits normally.
# - The trap is instrumented with $$ so the log says WHICH process ran it.
# - Bounded: the whole experiment runs under a fork + setpgrp + parent alarm + KILL -pid.

emulate -L zsh
setopt no_nomatch
zmodload zsh/zpty || { print -r -- 'no zpty'; exit 1 }
zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null

typeset -g Q=/private/tmp/hop-ptytrap
typeset -g W=$Q/work
rm -rf -- "$W"
mkdir -p "$W"

typeset -g TRAPLOG=$W/traplog
: > "$TRAPLOG"

print -r -- "parent pid=$$"

# A stand-in for HOP_FIX_DIRS: the dirs an inherited fixture_cleanup would delete.
typeset -ga FIXDIRS=("$W/ptyshared" "$W/ptyhome" "$W/ptycanary")
mkdir -p "${FIXDIRS[@]}"
print -r -- 'marker' > "$W/ptyshared/keep"
print -r -- 'marker' > "$W/ptyhome/keep"

# fake_cleanup -> exactly what fixture_cleanup does: rm -rf every registered dir.
fake_cleanup() {
	local d
	for d in "${FIXDIRS[@]}"; do
		[[ -n $d && -d $d ]] || continue
		rm -rf -- "$d"
	done
	return 0
}

# The instrumented stand-in for _hop_pty_onexit, which is what pty.zsh:458 installs.
fake_onexit() {
	print -r -- "TRAP_RAN pid=$$ ppid=$PPID" >> "$TRAPLOG"
	fake_cleanup
	return 0
}
trap fake_onexit EXIT INT TERM

print -rl -- alpha bravo > "$W/ptycanary/list"

# ---------------------------------------------------------------------------
# The canary shape, verbatim in structure: fzf that exits normally on one key.
# ---------------------------------------------------------------------------
typeset -F t0=${EPOCHREALTIME:-0}
trap - EXIT INT TERM
zpty -b CANARY "fzf --no-height --layout=reverse --bind 'o:print(ctrl-o)+accept' < ${W}/ptycanary/list > ${W}/ptycanary/out 2> ${W}/ptycanary/err"
print -r -- "zpty -b status=$?"
trap fake_onexit EXIT INT TERM

# pty_settle 0.4 equivalent, draining as it goes.
typeset junk
typeset -F spent=0
while (( spent < 0.4 )); do
	while zpty -r -t CANARY junk 2>/dev/null; do :; done
	sleep 0.02
	(( spent += 0.02 ))
done

zpty -w -n CANARY 'o'
print -r -- "key sent"

# Poll exactly as pty_canary does, but record the trap log state at each step.
spent=0
typeset broke=no
while (( spent < 10 )); do
	while zpty -r -t CANARY junk 2>/dev/null; do :; done
	if [[ -s $W/ptycanary/out ]]; then
		broke=yes
		break
	fi
	sleep 0.02
	(( spent += 0.02 ))
done
typeset -F t1=${EPOCHREALTIME:-0}

print -r -- "poll broke=${broke} after ${spent}s"
print -r -- "--- BEFORE zpty -d:"
print -r -- "    traplog: [$(tr '\n' ';' < "$TRAPLOG")]"
print -r -- "    ptyshared exists? $([[ -d $W/ptyshared ]] && print yes || print NO-DELETED)"
print -r -- "    ptyhome exists?   $([[ -d $W/ptyhome ]] && print yes || print NO-DELETED)"
print -r -- "    out=[$([[ -r $W/ptycanary/out ]] && tr -d '\n' < "$W/ptycanary/out" || print '<gone>')]"

zpty -d CANARY 2>/dev/null
sleep 0.3

print -r -- "--- AFTER zpty -d:"
print -r -- "    traplog: [$(tr '\n' ';' < "$TRAPLOG" 2>/dev/null)]"
print -r -- "    ptyshared exists? $([[ -d $W/ptyshared ]] && print yes || print NO-DELETED)"
print -r -- "    ptyhome exists?   $([[ -d $W/ptyhome ]] && print yes || print NO-DELETED)"
printf '    elapsed=%.2fs\n' $(( t1 - t0 ))

# Clear our own trap so the harness's own exit does not confuse the log.
trap - EXIT INT TERM
print -r -- "--- final traplog (parent pid was $$):"
[[ -r $TRAPLOG ]] && cat "$TRAPLOG" || print -r -- '(no log)'
exit 0
