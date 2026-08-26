#!/usr/bin/env zsh
# Sabotage matrix for task #43: each test must fail when the thing it guards is reverted.
# - Applied to the COMMITTED tree, then reverted with git checkout, so nothing is lost.

emulate -L zsh
setopt no_nomatch
typeset -g WT=/private/tmp/hop-wt-ptytrap

revert() { git -C "$WT" checkout -q -- tests/lib/pty.zsh }

report() {
	print -r -- "=============================================================="
	print -r -- "SABOTAGE: $1"
	print -r -- "=============================================================="
	zsh "$WT/tests/run" suite_pty_trap 2>&1 | grep -E '✓|✗|passed|failed' | sed 's/^/    /'
	print -r -- ''
}

revert
print -r -- 'BASELINE (fix intact)'
zsh "$WT/tests/run" suite_pty_trap 2>&1 | grep -E 'passed' | sed 's/^/    /'
print -r -- ''

# ---------------------------------------------------------------------------
# S1: revert the fix entirely. The helper stops clearing the trap.
# ---------------------------------------------------------------------------
perl -0pi -e 's/\temulate -L zsh\n\ttrap - EXIT INT TERM\n\tzpty -b "\$1" "\$2"/\temulate -L zsh\n\tzpty -b "\$1" "\$2"/s' "$WT/tests/lib/pty.zsh"
report 'S1 helper no longer clears the EXIT trap (the pre-fix behaviour)'
revert

# ---------------------------------------------------------------------------
# S2: a SECOND bare zpty -b appears, bypassing the helper.
# ---------------------------------------------------------------------------
perl -0pi -e 's/(\tpty_wait_lines 1 \|\| return 1\n)/\t[[ -n \$HOP_PTY_NEVER ]] && zpty -b BYPASS "true"\n$1/s' "$WT/tests/lib/pty.zsh"
report 'S2 a second bare zpty -b bypasses the helper'
revert

# ---------------------------------------------------------------------------
# S3: the helper clears the trap GLOBALLY and never restores it.
# ---------------------------------------------------------------------------
# Dropping `emulate -L zsh` drops local_traps, so the clear leaks out to the caller for good.
perl -0pi -e 's/_hop_pty_spawn\(\) \{\n\temulate -L zsh\n\ttrap - EXIT INT TERM\n/_hop_pty_spawn() {\n\ttrap - EXIT INT TERM\n/s' "$WT/tests/lib/pty.zsh"
report 'S3 helper clears the trap globally and never restores it'
revert

print -r -- 'FINAL (reverted)'
zsh "$WT/tests/run" suite_pty_trap 2>&1 | grep -E 'passed' | sed 's/^/    /'
print -r -- "git status: [$(git -C "$WT" status --short | tr '\n' ' ')]"
print -r -- '=== leftovers ==='
pgrep -x fzf
pgrep -x zpty
print -r -- '(empty above means nothing survived)'
