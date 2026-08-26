#!/usr/bin/env zsh
# hop core suite: the four defects in hop.zsh itself, each with a case that fails if the fix is reverted.
# - Every fzf here is a STUB that draws nothing and exits with whatever status the test asked for.
# - The real fzf is never started, not even with --filter, so no case in this file can touch a tty.

# ---------------------------------------------------------------------------
# A stub fzf, plus a probe that runs hop() against it.
# ---------------------------------------------------------------------------

# co_stub_fzf -> a directory holding a recording fzf, first on PATH only for the probes that ask.
# - It records argv and stdin, then exits $HOP_FZF_EXIT, which is how a status ladder gets tested.
# - `--version` is answered by the same script, and a non-version string makes _hop_fzf_ok pass.
typeset -g CO_STUBDIR='' CO_ARGV='' CO_STDIN=''
co_stub_fzf() {
	emulate -L zsh
	[[ -z $CO_STUBDIR ]] || return 0
	local REPLY
	fixture_tmpdir fzfstub || return 1
	CO_STUBDIR=$REPLY
	CO_ARGV="$CO_STUBDIR/argv"
	CO_STDIN="$CO_STUBDIR/stdin"
	print -rl -- \
		'#!/bin/sh' \
		'# hop test stub: records the call, draws nothing, exits the status the test picked.' \
		': > "$HOP_FZF_ARGV"' \
		'for a in "$@"; do printf "%s\n" "$a" >> "$HOP_FZF_ARGV"; done' \
		'cat > "$HOP_FZF_STDIN"' \
		'exit ${HOP_FZF_EXIT:-1}' > "$CO_STUBDIR/fzf"
	chmod +x "$CO_STUBDIR/fzf" || return 1
	return 0
}

# co_run <code> [VAR=value...] -> run code in a probe child whose only fzf is the stub.
# - perl's alarm bounds it, because a stub that somehow blocked would otherwise hang the suite.
# - Both streams are captured, since every assertion here is about a message on stderr.
# - The probe's status is this function's OWN status: a caller reads it as $? after the $(...).
# - Setting a global instead would lose it, because $(co_run ...) runs the whole body in a subshell.
# - _hop_tty_ok is forced true, because hop now refuses the picker outright with no controlling terminal.
# - This suite has none: a CI runner and an agent's shell both lack one, and neither can be given one cheaply.
# - The stub fzf is already a fiction that draws nothing and exits on demand, so the tty is the same fiction.
# - Without this every case below would take the headless path and stop testing the status ladder at all.
# - Overridden in the CHILD rather than the product, so no environment variable can disable the real guard.
co_run() {
	emulate -L zsh
	co_stub_fzf || return 1
	local code=$1
	shift
	: > "$CO_ARGV"
	: > "$CO_STDIN"
	local out st
	out=$(perl -e 'alarm 20; exec @ARGV' env \
		"HOP_FZF_ARGV=${CO_ARGV}" "HOP_FZF_STDIN=${CO_STDIN}" "$@" \
		zsh -f -c "$(fixture_pins)
export PATH=${(q)CO_STUBDIR}:\$PATH
source ${(q)HOP_HOME}/hop.zsh || exit 97
_hop_tty_ok() { return 0 }
${code}" 2>&1)
	st=$?
	print -r -- "$out"
	return $st
}

# co_ws -> REPLY is a directory usable as a workspace, so `hop -w` renders exactly one row.
# - _hop_provider_ws emits a row for any workspace that EXISTS, repos or not, so one mkdir is enough.
co_ws() {
	emulate -L zsh
	fixture_tmpdir ws || return 1
	return 0
}

# ---------------------------------------------------------------------------
# Item 4: _hop_ws_picker has to read fzf's exit status, like every other picker.
# ---------------------------------------------------------------------------
# Built here at the top level, not inside a $(...), or the stub's path would not survive the subshell.
co_stub_fzf || return 1
typeset CO_WS out
typeset -i st
co_ws
CO_WS=$REPLY

t 'the stub fzf really is the only fzf a probe can see'
out=$(co_run 'print -r -- ${commands[fzf]}')
assert_eq "$CO_STUBDIR/fzf" "$out" 'a real fzf on PATH would make every case below meaningless'

t 'hop -w reports a non-zero fzf status instead of swallowing it'
out=$(co_run 'hop -w' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=2'); st=$?
assert_contains "$out" 'hop: fzf exited with status 2' 'the ws picker skipped the status ladder'
assert_eq 2 "$st" 'the fzf status has to reach the caller, not be replaced by 0'

t 'hop -R reports the same status the same way, so the two pickers cannot drift'
out=$(co_run 'hop -R' "HOP_REPOS=${CO_WS}" 'HOP_FZF_EXIT=2'); st=$?
assert_contains "$out" 'hop: fzf exited with status 2'
assert_eq 2 "$st"

t 'hop -w on a no-match says so, rather than printing nothing at all'
out=$(co_run 'hop -w nosuchworkspace' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=1'); st=$?
assert_contains "$out" 'hop: no match for: nosuchworkspace'
assert_eq 1 "$st"

t 'hop -w on a user cancel stays silent and succeeds'
out=$(co_run 'hop -w' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=130'); st=$?
assert_empty "$out" '130 is esc, and esc must never print anything'
assert_eq 0 "$st" 'cancelling is not a failure'

t 'esc out of the repo picker is silent too, which is what makes 130 a shared rule'
out=$(co_run 'hop -R' "HOP_REPOS=${CO_WS}" 'HOP_FZF_EXIT=130'); st=$?
assert_empty "$out"
assert_eq 0 "$st"

t 'both pickers route through the one _hop_fzf_status, so the ladder cannot be duplicated'
out=$(co_run 'print -r -- ${#${(M)${(f)"$(functions _hop_run _hop_ws_picker)"}:#*fzf exited with status*}}')
assert_eq 0 "$out" 'a picker with its own copy of the message has forked the ladder again'
out=$(co_run 'whence -w _hop_fzf_status')
assert_contains "$out" 'function' 'the shared helper has to exist for either picker to use it'

t '_hop_ws_picker leaves no _hop_key or _hop_st behind in the calling shell'
out=$(co_run 'hop -w >/dev/null 2>&1; print -r -- "key=${_hop_key-unset} st=${_hop_st-unset}"' \
	"HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=130')
assert_eq 'key=unset st=unset' "$out" 'the picker must not leak state into the interactive shell'

# ---------------------------------------------------------------------------
# Item 7: HOP_DEBUG=1 has to log the failures people actually file bugs about.
# ---------------------------------------------------------------------------
# co_dbg <hop-code> [VAR=value...] -> the debug log a probe wrote, with HOP_DEBUG on for that probe.
# - HOP_DEBUG is pinned OFF by fixture_pins, so turning it on INSIDE the probe is the only honest way.
# - The log path is pinned per call, because the default lands under the throwaway $HOME either way.
co_dbg() {
	emulate -L zsh
	local code=$1
	shift
	local REPLY
	fixture_tmpdir dbg || return 1
	local log="$REPLY/debug.log"
	co_run "export HOP_DEBUG=1 HOP_DEBUG_LOG=${(q)log}
${code}" "$@" >/dev/null 2>&1
	[[ -r $log ]] || return 0
	cat -- "$log"
	return 0
}

t 'HOP_DEBUG=1 logs a pick that found no match, which used to log nothing at all'
out=$(co_dbg 'hop -w nosuchthing' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=1')
assert_contains "$out" 'st=1' 'a no-match is the single most reported failure, so it has to be logged'
assert_contains "$out" 'pick label=workspaces'
assert_contains "$out" 'query=nosuchthing' 'the query is what makes a no-match report reproducible'

t 'HOP_DEBUG=1 logs a user cancel, so an abandoned pick is distinguishable from a crash'
out=$(co_dbg 'hop -w' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=130')
assert_contains "$out" 'st=130'

t 'HOP_DEBUG=1 logs a hard fzf failure, the case a bug report cannot diagnose without it'
out=$(co_dbg 'hop -R' "HOP_REPOS=${CO_WS}" 'HOP_FZF_EXIT=2')
assert_contains "$out" 'st=2'
assert_contains "$out" 'pick label=repos'

t 'the row count reaches the log, so "empty list" and "list did not match" are tellable apart'
out=$(co_dbg 'hop -w' "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=1')
assert_contains "$out" 'rows=1' 'one configured workspace is one row'

t 'HOP_DEBUG unset still writes nothing, so the new call site stays opt-in'
typeset CO_OFFLOG
fixture_tmpdir dbgoff
CO_OFFLOG="$REPLY/debug.log"
co_run "export HOP_DEBUG_LOG=${(q)CO_OFFLOG}
hop -w" "HOP_WORKSPACES=${CO_WS}" 'HOP_FZF_EXIT=1' >/dev/null 2>&1
out=''
[[ -r $CO_OFFLOG ]] && out=$(cat -- "$CO_OFFLOG")
assert_empty "$out" 'a pick must not write a debug log unless HOP_DEBUG asked for one'

# ---------------------------------------------------------------------------
# Item 1: hop -c has to work through a symlink, and on a name holding a backslash.
# ---------------------------------------------------------------------------
# The repo is reached through a REAL symlink, which is the only way $PWD and git disagree.
# - fixture_tmpdir resolves its own path, so the link has to be made here to get a logical $PWD.
# - This is the /var case suite_smoke pins, one level further: /tmp is a symlink on macOS too.
# The tg preset needs two path components under terraform/, so every unit here is scope/name.
typeset CO_REPO CO_LINK CO_SUB CO_BS
fixture_repo core
CO_REPO=$REPLY
fixture_write 'terraform/acct/prod/us-east-1/terragrunt.hcl' 'include {}'
fixture_write 'terraform/acct/stage/us-east-1/terragrunt.hcl' 'include {}'
fixture_write 'README.md' '# fixture'
fixture_commit 'initial'

fixture_tmpdir link
CO_LINK="$REPLY/link"
ln -sfn -- "$CO_REPO" "$CO_LINK"
CO_SUB='terraform/acct/prod'

t 'the fixture really is reached through a symlink, or the cases below prove nothing'
assert_eq "$CO_REPO" "${CO_LINK:A}" 'the link has to resolve to the fixture repo'
assert_ne "$CO_REPO" "$CO_LINK" 'an unresolved link is what makes $PWD and git disagree'
out=$(co_run "builtin cd -q -- ${(q)CO_LINK}/${CO_SUB}
print -r -- \"\$PWD\"
git rev-parse --show-toplevel")
assert_contains "$out" "$CO_LINK/$CO_SUB" 'zsh keeps $PWD logical, which is the whole bug'
assert_contains "$out" "$CO_REPO" 'git reports the physical root, which is the other half'

t 'hop -c finds targets in a subtree entered through a symlink'
out=$(co_run "builtin cd -q -- ${(q)CO_LINK}/${CO_SUB}
hop -c -k tg" 'HOP_FZF_EXIT=1'); st=$?
assert_not_contains "$out" 'hop: no targets under' 'the logical/physical mismatch dropped every row'
assert_contains "$out" 'hop: no match' 'reaching fzf at all is what proves the rows survived'
assert_eq 1 "$st"

t 'and the surviving rows are the ones under that subtree, not the whole repo'
co_run "builtin cd -q -- ${(q)CO_LINK}/${CO_SUB}
hop -c -k tg" 'HOP_FZF_EXIT=1' >/dev/null 2>&1
out=$(cat -- "$CO_STDIN")
assert_contains "$out" "$CO_REPO/terraform/acct/prod/us-east-1" 'the row in the subtree has to be offered'
assert_not_contains "$out" 'acct/stage' 'a sibling subtree must still be filtered out'

t 'hop -c still narrows, so the symlink fix did not turn the filter off'
co_run "builtin cd -q -- ${(q)CO_LINK}/terraform/acct/stage
hop -c -k tg" 'HOP_FZF_EXIT=1' >/dev/null 2>&1
out=$(cat -- "$CO_STDIN")
assert_contains "$out" "$CO_REPO/terraform/acct/stage/us-east-1"
assert_not_contains "$out" 'acct/prod' 'standing in stage must not offer prod'

t 'hop -c under a subtree with no targets still says so, by its own message'
out=$(co_run "builtin cd -q -- ${(q)CO_LINK}
mkdir -p empty/deeper
builtin cd -q -- empty/deeper
hop -c -k tg" 'HOP_FZF_EXIT=1'); st=$?
assert_contains "$out" 'hop: no targets under' 'a genuinely empty subtree keeps the original message'
assert_eq 1 "$st"

t 'a directory whose name holds a backslash is not mangled, which awk -v did'
CO_BS='terraform/we\ird/unit'
fixture_write "${CO_BS}/terragrunt.hcl" 'include {}'
fixture_commit 'backslash'
out=$(co_run "builtin cd -q -- ${(q)CO_REPO}/${(q)CO_BS}
hop -c -k tg" 'HOP_FZF_EXIT=1'); st=$?
assert_not_contains "$out" 'hop: no targets under' 'awk -v escape-processed the backslash away'
assert_contains "$out" 'hop: no match'
assert_eq 1 "$st"

t 'and that backslash subtree offers its own row, not a sibling'
co_run "builtin cd -q -- ${(q)CO_REPO}/${(q)CO_BS}
hop -c -k tg" 'HOP_FZF_EXIT=1' >/dev/null 2>&1
out=$(cat -- "$CO_STDIN")
assert_contains "$out" "$CO_REPO/$CO_BS"
assert_not_contains "$out" 'acct/prod' 'the filter still has to exclude everything else'

t 'the -c filter no longer forks awk, per the same rule providers.zsh already follows'
out=$(co_run 'print -r -- ${#${(M)${(f)"$(functions hop)"}:#*awk*}}')
assert_eq 0 "$out" 'awk -v cannot carry a path safely, so hop() must not use it'

# ---------------------------------------------------------------------------
# Item 2: a user's own HOP_CONFIG has to reach the children that re-source hop.zsh.
# ---------------------------------------------------------------------------
# The kinds below are declared in a config a probe points HOP_CONFIG at, exactly as a user would.
typeset CO_CFG
fixture_tmpdir usercfg
CO_CFG="$REPLY/mine.zsh"
print -rl -- \
	'hop_kind mine --default --marker OWNER --under mine --layout "name..." --desc "my own kind"' \
	> "$CO_CFG"
fixture_write 'mine/alpha/OWNER' 'me'
fixture_commit 'own kind'

# HOP_CONFIG has to be UNSET first in every case below, or the export proves nothing.
# - fixture_pins exports HOP_CONFIG, and `typeset -g` KEEPS an export attribute that already exists.
# - So a probe that inherits the pin passes whether hop.zsh says -g or -gx, which is no test at all.
# - Unsetting and then assigning plainly is what a .zshrc line actually does.
t 'a plainly assigned HOP_CONFIG is exported, which is what a .zshrc line needs'
out=$(co_run "unset HOP_CONFIG
HOP_CONFIG=${(q)CO_CFG}
source \${HOP_HOME}/hop.zsh
print -r -- \"attr=\${(t)HOP_CONFIG}\"
zsh -f -c 'print -r -- \"child=\${HOP_CONFIG:-nothing}\"'")
assert_contains "$out" 'export' 'an unexported HOP_CONFIG is invisible to bin/hop-kinds'
assert_contains "$out" "child=$CO_CFG" 'a child process is the only thing this attribute is for'

t 'HOP_HOPRC is not invented when it was never set'
out=$(co_run 'print -r -- ${+HOP_HOPRC}-${HOP_HOPRC:-empty}')
assert_contains "$out" 'empty' 'exporting an unset HOP_HOPRC would opt the user into running .hoprc'

t 'HOP_HOPRC is exported once the user does set it, so the opt-in survives into a child'
out=$(co_run 'export HOP_HOPRC=1
source ${HOP_HOME}/hop.zsh
print -r -- ${(t)HOP_HOPRC}')
assert_contains "$out" 'export'

# hop-kinds is launched bare from fzf's reload(), so ONLY the export can carry the config to it.
# - That makes this the case that pins `typeset -gx`, with no explicit forwarding to fall back on.
t 'bin/hop-kinds sees the user kinds, which is what the : menu renders'
out=$(co_run "unset HOP_CONFIG
HOP_CONFIG=${(q)CO_CFG}
source \${HOP_HOME}/hop.zsh
\${HOP_HOME}/bin/hop-kinds menu ${(q)CO_REPO}")
assert_contains "$out" 'my own kind' 'the : menu showed the eight shipped presets instead'
assert_not_contains "$out" 'terragrunt units' 'a user config replaces the presets, it does not add to them'

t 'the reload command forwards HOP_CONFIG, so alt-a regenerates with the user kinds'
out=$(co_run "export HOP_CONFIG=${(q)CO_CFG}
source \${HOP_HOME}/hop.zsh
_hop_reload_cmd ${(q)CO_REPO} mine")
assert_contains "$out" "HOP_CONFIG=" 'the child gets no registry unless the config path is named'
assert_contains "$out" "$CO_CFG"

t 'and running that reload command really does emit the user rows, not unknown kind'
out=$(co_run "unset HOP_CONFIG
HOP_CONFIG=${(q)CO_CFG}
source \${HOP_HOME}/hop.zsh
eval \"\$(_hop_reload_cmd ${(q)CO_REPO} mine)\"")
assert_not_contains "$out" 'unknown kind' 'alt-a and r printed this and then blanked the picker'
assert_contains "$out" "$CO_REPO/mine/alpha" 'the reload child has to produce the same rows hop did'

t 'the reload child keeps zsh -f, so a reload can never source the user rc files'
out=$(co_run "source \${HOP_HOME}/hop.zsh
_hop_reload_cmd ${(q)CO_REPO} mine")
assert_contains "$out" 'zsh -f -c' 'dropping -f would run .zshrc inside every reload'

t 'a HOP_CONFIG assigned AFTER hop.zsh was sourced still reaches the reload child'
out=$(co_run "HOP_CONFIG=${(q)CO_CFG}
_hop_reload_cmd ${(q)CO_REPO} mine")
assert_contains "$out" "$CO_CFG" 'the live value is what the child needs, not the one seen at source time'
