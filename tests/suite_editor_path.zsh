#!/usr/bin/env zsh
# suite_editor_path: _hop_need and _hop_act_edit in lib/actions.zsh, with an absolute-path editor.
# - $EDITOR/$VISUAL are ordinary $PATH-free settings (e.g. /opt/homebrew/bin/nvim), and
#   _hop_need must accept those, not just bare names it can find on $PATH.
# - stub_bin already exports EDITOR/VISUAL as an absolute path to its "editor" stub, so most of
#   this suite just exercises that existing fixture end to end instead of building a new one.

stub_bin

typeset -g EP_TARGET
fixture_tmpdir editorpath
print -r -- 'hello' > "$REPLY/target.txt"
EP_TARGET="$REPLY/target.txt"

typeset -g EP_ERR
fixture_tmpdir editorpatherr
EP_ERR="$REPLY/stderr"

# ep_err -> the last probe's stderr, slurped into a variable first.
# - `zsh -n` EVALUATES a top-level `$(<file)` used inline as an argument, so it must land in a
#   plain assignment before any assert sees it, same as it_slurp in suite_integration.zsh.
ep_err() {
	emulate -L zsh
	print -rn -- "$(<"$EP_ERR")"
}

# ---------------------------------------------------------------------------
# _hop_need: bare names still resolve on $PATH exactly as before.
# ---------------------------------------------------------------------------
t '_hop_need accepts a bare name found on PATH'
stub_reset
out=$(hop_probe '_hop_need editor "do a thing"; print -n $?' 2>"$EP_ERR")
assert_eq '0' "$out"
assert_empty "$(ep_err)"

t '_hop_need rejects a bare name missing from PATH, with the original wording'
: > "$EP_ERR"
out=$(hop_probe '_hop_need hop_test_missing_cmd_xyz "do a thing"; print -n $?' 2>"$EP_ERR")
assert_eq '1' "$out"
assert_eq 'hop: hop_test_missing_cmd_xyz is not installed, cannot do a thing' "$(ep_err)"

# ---------------------------------------------------------------------------
# _hop_need: a path (contains a slash) is checked directly, not looked up on PATH.
# ---------------------------------------------------------------------------
t '_hop_need accepts an absolute path to an executable'
: > "$EP_ERR"
out=$(hop_probe "_hop_need ${(q)HOP_FIX_STUBDIR}/editor 'edit a file'; print -n \$?" 2>"$EP_ERR")
assert_eq '0' "$out"
assert_empty "$(ep_err)"

t '_hop_need rejects an absolute path that does not exist, without claiming "not installed"'
: > "$EP_ERR"
out=$(hop_probe "_hop_need ${(q)HOP_FIX_STUBDIR}/no-such-editor 'edit a file'; print -n \$?" 2>"$EP_ERR")
assert_eq '1' "$out"
assert_eq "hop: ${HOP_FIX_STUBDIR}/no-such-editor does not exist, cannot edit a file" "$(ep_err)"

t '_hop_need rejects an absolute path that exists but is not executable'
typeset plainfile="${HOP_FIX_STUBDIR}/not-executable"
print -r -- '#!/bin/sh' > "$plainfile"
chmod -x "$plainfile"
: > "$EP_ERR"
out=$(hop_probe "_hop_need ${(q)plainfile} 'edit a file'; print -n \$?" 2>"$EP_ERR")
assert_eq '1' "$out"
assert_eq "hop: ${plainfile} is not executable, cannot edit a file" "$(ep_err)"

t '_hop_need accepts a relative path (contains a slash) resolved against the cwd'
typeset reldir
fixture_tmpdir editorpathrel
reldir=$REPLY
print -rl -- '#!/bin/sh' 'exit 0' > "$reldir/runme"
chmod +x "$reldir/runme"
: > "$EP_ERR"
out=$(hop_probe "builtin cd -q ${(q)reldir} && _hop_need ./runme 'run a thing'; print -n \$?" 2>"$EP_ERR")
assert_eq '0' "$out"
assert_empty "$(ep_err)"

# ---------------------------------------------------------------------------
# End to end: alt-o / _hop_act_edit with a real absolute-path $EDITOR.
# ---------------------------------------------------------------------------
t 'a real absolute-path $EDITOR is invoked to edit a file (alt-o)'
stub_reset
: > "$EP_ERR"
out=$(hop_probe "_hop_act_edit ${(q)EP_TARGET}; print -n \$?" 2>"$EP_ERR")
assert_eq '0' "$out"
assert_empty "$(ep_err)"
assert_eq "editor	${EP_TARGET}" "$(stub_calls editor)"

t 'an absolute-path $EDITOR that does not exist fails, and the editor is never invoked'
stub_reset
: > "$EP_ERR"
typeset badeditor="${HOP_FIX_STUBDIR}/no-such-editor"
out=$(hop_probe "EDITOR=${(q)badeditor} VISUAL=${(q)badeditor} _hop_act_edit ${(q)EP_TARGET}; print -n \$?" 2>"$EP_ERR")
assert_eq '1' "$out"
assert_eq "hop: ${badeditor} does not exist, cannot edit a file" "$(ep_err)"
assert_empty "$(stub_calls editor)"
