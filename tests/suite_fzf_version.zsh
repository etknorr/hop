#!/usr/bin/env zsh
# suite_fzf_version: the minimum-fzf guard, which exists because apt ships an fzf hop cannot use.
# - Debian and Ubuntu package fzf 0.44.x, where the picker dies with `unknown option: --accept-nth`.
# - hop needs 0.60.3: 0.60.0 added --accept-nth, and 0.60.3 made it work with --select-1.
# - Every test here uses a STUB fzf, so nothing depends on the fzf installed on this machine.
# - No test may run the real fzf, and none of them run fzf at all beyond `--version` on the stub.

typeset FZ_STUB='' FZ_LOG=''

# _fz_stub -> put a stub fzf on its own directory, reporting whatever $HOP_FZF_STUB_OUT says.
# - It logs every call, which is how "at most one fork per shell" becomes an assertion.
_fz_stub() {
	emulate -L zsh
	local REPLY
	fixture_tmpdir fzfstub || return 1
	FZ_STUB=$REPLY
	FZ_LOG="$REPLY/calls.log"
	: > "$FZ_LOG"
	print -rl -- \
		'#!/bin/sh' \
		'# hop test stub: answers --version, and refuses anything else loudly rather than silently.' \
		'printf "fzf %s\n" "$*" >> "$HOP_FZF_STUB_LOG"' \
		'case "$1" in' \
		'	--version) ;;' \
		'	*) printf "stub fzf: refusing to emulate the UI: %s\n" "$*" >&2; exit 2 ;;' \
		'esac' \
		'if [ -n "$HOP_FZF_STUB_OUT" ]; then printf "%s\n" "$HOP_FZF_STUB_OUT"; fi' \
		'exit 0' > "$FZ_STUB/fzf"
	chmod +x "$FZ_STUB/fzf" || return 1
	return 0
}

# _fz_path -> a PATH holding the stub plus the base system directories, and nothing else.
# - The real fzf lives in a package-manager prefix, so omitting those makes it UNREACHABLE here.
# - A real fzf in --height mode emits ESC[6n and waits forever when no tty can answer it.
# - Shadowing alone was not enough: one test unshadowed it and orphaned a hung fzf to init.
# - git, zsh, cat and chmod all resolve under this, which is everything a probe needs.
_fz_path() {
	emulate -L zsh
	print -rn -- "${FZ_STUB}:/usr/bin:/bin:/usr/sbin:/sbin"
}

# _fz_probe <version-output> <code> -> run code with hop.zsh sourced and ONLY the stub fzf reachable.
# - `${+commands[fzf]}` stays true inside hop(), which is what keeps the not-installed branch out.
# - The call log is truncated first, so each probe's fork count stands on its own.
_fz_probe() {
	emulate -L zsh
	local ver=$1 code=$2
	: > "$FZ_LOG"
	HOP_FZF_STUB_OUT=$ver HOP_FZF_STUB_LOG=$FZ_LOG PATH="$(_fz_path)" \
		HOP_HOPRC='' HOP_HISTFILE=/dev/null HOP_CONFIG="$(_hop_fix_config)" \
		zsh -f -c "source ${(q)HOP_HOME}/hop.zsh || exit 97
${code}"
}

# _fz_forks -> how many times the stub fzf was executed by the last probe.
_fz_forks() {
	emulate -L zsh
	[[ -r $FZ_LOG ]] || return 1
	local -a lines=("${(@f)$(command cat -- "$FZ_LOG")}")
	lines=(${lines:#})
	print -r -- $#lines
}

typeset out
typeset -i st

t 'the fzf stub is in place, so nothing below touches the real fzf'
_fz_stub
assert_nonempty "$FZ_STUB" 'no stub directory, so every test below would use the real fzf'
assert_exec "$FZ_STUB/fzf"

t 'the only fzf a probe can reach is the stub'
# If this ever fails, a probe can start a real picker with no tty, which hangs until it is killed.
out=$(_fz_probe '0.74.1' 'command -v fzf')
assert_eq "$FZ_STUB/fzf" "$out" 'a probe could reach a real fzf, which would hang with no tty'

t 'the stub refuses to emulate the picker, so a stray UI call fails instead of passing'
out=$(_fz_probe '0.74.1' 'fzf --height=80% >/dev/null' 2>&1)
st=$?
assert_eq 2 "$st" 'the stub answered a UI invocation, so a bad test could look green'
assert_contains "$out" 'refusing to emulate'

t 'sourcing hop.zsh forks nothing, because every shell pays for that'
out=$(_fz_probe '0.44.1 (debian)' 'true' 2>&1)
st=$?
assert_eq 0 "$st"
assert_eq 0 "$(_fz_forks)" 'hop.zsh ran fzf at source time, which every interactive shell pays for'

t 'an fzf older than the minimum is refused, with the version, the need and the fix'
out=$(_fz_probe '0.44.1 (debian)' '_hop_fzf_ok' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" '0.44.1'
assert_contains "$out" '0.60.3'
assert_contains "$out" 'Ubuntu'
assert_contains "$out" 'github.com/junegunn/fzf/releases'

t 'the message names the flag combination that actually breaks'
assert_contains "$out" '--accept-nth'
assert_contains "$out" '--select-1'

t 'the exact minimum passes'
out=$(_fz_probe '0.60.3 (abc1234)' '_hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"
assert_empty "$out" 'a supported fzf must say nothing at all'

t 'one patch release below the minimum is refused'
# 0.60.0 through 0.60.2 have --accept-nth but mishandle it with --select-1, which hop always passes.
out=$(_fz_probe '0.60.2' '_hop_fzf_ok' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" '0.60.2'

t 'a newer fzf passes, including a two-digit minor'
out=$(_fz_probe '0.74.1 (brew)' '_hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"

t 'a major-version bump passes rather than reading as older'
out=$(_fz_probe '1.0.0' '_hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"

t 'a two-field version is compared as if the patch were zero'
out=$(_fz_probe '0.61' '_hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"

t 'an unparseable version proceeds, because locking out a working fzf is worse'
out=$(_fz_probe 'fzf version unknown' '_hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st" 'a version hop cannot read must never block it'
assert_empty "$out"

t 'no version output at all also proceeds'
out=$(_fz_probe '' '_hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"
assert_empty "$out"

t 'the version is read at most once per shell, however often hop runs'
out=$(_fz_probe '0.74.1' '_hop_fzf_ok; _hop_fzf_ok; _hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"
assert_eq 1 "$(_fz_forks)" 'the version is memoized, so three calls must still be one fork'

t 'an unparseable version is memoized too, so it cannot fork on every call'
out=$(_fz_probe 'nonsense' '_hop_fzf_ok; _hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"
assert_eq 1 "$(_fz_forks)"

t 'the floor covers every fzf action the keymap uses, including search()'
# An UNKNOWN action makes fzf refuse to START, so adding one to the keymap is a floor question.
# - `search()` arrived in fzf 0.59.0, which the 0.60.3 floor already covers, so it did not move.
# - The whole BIND SET is read, not HOP_VIM_TO_NORMAL: search() moved to the esc bind and this
#   check is about which actions the keymap uses, wherever they happen to sit.
out=$(_fz_probe '0.74.1' '
_hop_vim_init
typeset -a args=()
_hop_vim_binds /bin/true "" "" "" "" "" ""
print -rl -- "${args[@]}"')
assert_contains "$out" 'search()' 'esc must re-match, or NORMAL is left holding an empty list'
assert_contains "$out" 'clear-query+search()' 'search() before clear-query re-runs the dead query'
# Ordering guard: search() has to sit AHEAD of the transform, never inside it.
# - Folding it back in is the one edit that reintroduces the dead list without breaking anything else.
assert_contains "$out" 'search()+transform:' 'search() from inside a transform is silently a no-op'
out=$(_fz_probe '0.74.1' '_hop_ver_lt 0.59.0 $HOP_FZF_MIN && print -r -- covered')
assert_eq covered "$out" 'the floor must be at or above 0.59.0, where search() was added'

t 'HOP_FZF_MIN can be lowered, for an fzf that is fine despite its version string'
out=$(_fz_probe '0.44.1' 'HOP_FZF_MIN=0.1.0 _hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st" 'the minimum has to be overridable, or a false positive is unfixable'

t 'a HOP_FZF_MIN with a non-numeric field still returns a verdict, not a math error'
# `local -i` on the field made an override like 0.60.3rc1 abort the caller with a bad math expression.
out=$(_fz_probe '0.74.1' 'HOP_FZF_MIN=0.60.3rc1 _hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"
assert_not_contains "$out" 'bad math expression'

t 'a garbage HOP_FZF_MIN fails open rather than blocking every hop'
out=$(_fz_probe '0.74.1' 'HOP_FZF_MIN=latest _hop_fzf_ok' 2>&1)
st=$?
assert_eq 0 "$st"
assert_not_contains "$out" 'bad math expression'

t 'the shipped minimum is the one the changelog justifies'
out=$(_fz_probe '0.74.1' 'print -r -- $HOP_FZF_MIN' 2>&1)
assert_eq '0.60.3' "$out" 'fzf 0.60.0 added --accept-nth; 0.60.3 fixed it with --select-1'

# ---------------------------------------------------------------------------
# The comparison itself, since every refusal above rests on it.
# ---------------------------------------------------------------------------
t '_hop_ver_lt orders versions field by field, not as strings'
out=$(_fz_probe '0.74.1' '
for pair in 0.9.0:0.10.0 0.60.2:0.60.3 0.59.9:0.60.0 1.2.3:1.2.4; do
	_hop_ver_lt "${pair%%:*}" "${pair##*:}" && print -r -- "lt ${pair}" || print -r -- "GE ${pair}"
done')
assert_eq $'lt 0.9.0:0.10.0\nlt 0.60.2:0.60.3\nlt 0.59.9:0.60.0\nlt 1.2.3:1.2.4' "$out" \
	'a string compare would call 0.9.0 newer than 0.10.0'

t '_hop_ver_lt is false for equal and for newer versions'
out=$(_fz_probe '0.74.1' '
for pair in 0.60.3:0.60.3 0.60.4:0.60.3 1.0.0:0.60.3 0.10.0:0.9.0; do
	_hop_ver_lt "${pair%%:*}" "${pair##*:}" && print -r -- "LT ${pair}" || print -r -- "ge ${pair}"
done')
assert_eq $'ge 0.60.3:0.60.3\nge 0.60.4:0.60.3\nge 1.0.0:0.60.3\nge 0.10.0:0.9.0' "$out"

# ---------------------------------------------------------------------------
# The guard reached through hop() itself, which is where a user meets it.
# ---------------------------------------------------------------------------
# hop() must refuse BEFORE the picker, so even a broken guard cannot start the stub, let alone fzf.
t 'hop itself refuses on a too-old fzf, before it reaches the picker'
fixture_repo fzf-repo
fixture_write 'terraform/payments/prod/us-east-1/vpc/terragrunt.hcl' '# unit'
fixture_commit 'a unit to find'
out=$(cd "$HOP_FIX_REPO" && _fz_probe '0.44.1 (debian)' 'hop vpc' 2>&1)
st=$?
assert_eq 1 "$st"
assert_contains "$out" 'too old'
assert_eq 1 "$(_fz_forks)" 'only the version check may run fzf; the picker must never be reached'

skip 'hop refuses when fzf is absent' 'taking the stub off PATH finds the REAL fzf and hangs'
