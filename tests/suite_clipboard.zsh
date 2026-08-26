#!/usr/bin/env zsh
# suite_clipboard: _hop_act_copy in lib/actions.zsh, the y/Y and ctrl-y/alt-y verb.
# - The real pbcopy/wl-copy/xclip/xsel/clip.exe are never run: every tool is a recording stub.
# - Presence and absence are simulated with PATH, not by installing or removing anything.
# - stub_bin's own log has no way to prove what was piped on stdin, so this suite rolls its own.

# ---------------------------------------------------------------------------
# A directory holding one recording stub per candidate tool, plus its stdin payload.
# ---------------------------------------------------------------------------
typeset -g CB_ROOT='' CB_LOG=''
typeset -ga CB_TOOLS=(pbcopy wl-copy xclip xsel clip.exe)

# cb_setup -> build $CB_ROOT/<tool>/<tool> for every candidate, once per suite run.
cb_setup() {
	emulate -L zsh
	[[ -z $CB_ROOT ]] || return 0
	local REPLY
	fixture_tmpdir clip || return 1
	CB_ROOT=$REPLY
	CB_LOG="$CB_ROOT/calls.log"
	: > "$CB_LOG"
	export CB_LOG
	local n
	for n in "${CB_TOOLS[@]}"; do
		mkdir -p -- "$CB_ROOT/$n" || return 1
		# zsh, not /bin/sh: the restricted PATH has no `cat`, so stdin capture needs a builtin.
		print -rl -- \
			'#!/usr/bin/env zsh' \
			'emulate -L zsh' \
			"printf '%s' '${n}' >> \"\$CB_LOG\"" \
			'for a in "$@"; do printf "\t%s" "$a" >> "$CB_LOG"; done' \
			'printf "\n" >> "$CB_LOG"' \
			'local payload; IFS= read -r -d "" payload <&0' \
			"print -rn -- \"\$payload\" > '${CB_ROOT}/${n}/${n}.stdin'" \
			'exit 0' > "$CB_ROOT/$n/$n"
		chmod +x "$CB_ROOT/$n/$n" || return 1
	done
	return 0
}

# cb_reset -> forget every recorded call and payload, for a test that asserts on one invocation.
cb_reset() {
	emulate -L zsh
	[[ -n ${CB_LOG:-} ]] || return 0
	: > "$CB_LOG"
	local n
	for n in "${CB_TOOLS[@]}"; do
		rm -f -- "$CB_ROOT/$n/$n.stdin"
	done
	return 0
}

# cb_calls -> the whole call log since the last cb_reset, newest last.
cb_calls() {
	emulate -L zsh
	[[ -n ${CB_LOG:-} && -r ${CB_LOG:-} ]] || return 1
	local -a lines=("${(@f)$(<"$CB_LOG")}")
	lines=(${lines:#})
	print -rl -- "${lines[@]}"
	return 0
}

# cb_payload <tool> -> the bytes that tool's stub received on stdin, or empty if never invoked.
cb_payload() {
	emulate -L zsh
	local f="${CB_ROOT}/$1/$1.stdin"
	[[ -r $f ]] || return 1
	print -rn -- "$(<"$f")"
	return 0
}

# ---------------------------------------------------------------------------
# A minimal PATH: just the chosen tool stubs plus a real zsh, so hop_probe can still start.
# ---------------------------------------------------------------------------
typeset -g CB_BASEPATH=''

# cb_basepath -> a dir holding only a symlink to the real zsh, mirroring it_nobat_path.
cb_basepath() {
	emulate -L zsh
	[[ -z $CB_BASEPATH ]] || return 0
	local REPLY
	fixture_tmpdir clipbase || return 1
	CB_BASEPATH=$REPLY
	[[ -n ${commands[zsh]} ]] || return 1
	ln -sf -- "${commands[zsh]}" "$CB_BASEPATH/zsh" || return 1
	return 0
}

# cb_probe <code> <tool...> -> hop_probe with PATH exposing only the named tool stubs.
# - A tool left out of the argument list is genuinely unresolvable, not merely unpreferred.
cb_probe() {
	emulate -L zsh
	local code=$1
	shift
	cb_basepath || return 1
	cb_setup || return 1
	local -a dirs=()
	local n
	for n in "$@"; do
		dirs+=("$CB_ROOT/$n")
	done
	dirs+=("$CB_BASEPATH")
	local PATH="${(j.:.)dirs}"
	hop_probe "$code"
}

# cb_probe_override <code> <clipboard> <tool...> -> like cb_probe, but forces HOP_CLIPBOARD=<clipboard>.
cb_probe_override() {
	emulate -L zsh
	local code=$1 clipboard=$2
	shift 2
	cb_basepath || return 1
	cb_setup || return 1
	local -a dirs=()
	local n
	for n in "$@"; do
		dirs+=("$CB_ROOT/$n")
	done
	dirs+=("$CB_BASEPATH")
	local PATH="${(j.:.)dirs}"
	local -x HOP_CLIPBOARD=$clipboard
	hop_probe "$code"
}

cb_setup

typeset -g CB_ERR
typeset REPLY
fixture_tmpdir clipstderr
CB_ERR="$REPLY/stderr"

# ---------------------------------------------------------------------------
# Preference order.
# ---------------------------------------------------------------------------
t 'pbcopy is chosen when every candidate is present'
cb_reset
cb_probe '_hop_act_copy "hello world"' pbcopy wl-copy xclip xsel clip.exe >/dev/null 2>"$CB_ERR"
assert_eq 'pbcopy' "$(cb_calls)"
assert_eq 'hello world' "$(cb_payload pbcopy)"

t 'wl-copy is chosen when pbcopy is absent'
cb_reset
cb_probe '_hop_act_copy "hello world"' wl-copy xclip xsel clip.exe >/dev/null 2>"$CB_ERR"
assert_eq 'wl-copy' "$(cb_calls)"
assert_eq 'hello world' "$(cb_payload wl-copy)"

t 'xclip is chosen when pbcopy and wl-copy are absent'
cb_reset
cb_probe '_hop_act_copy "hello world"' xclip xsel clip.exe >/dev/null 2>"$CB_ERR"
assert_eq $'xclip\t-selection\tclipboard' "$(cb_calls)"
assert_eq 'hello world' "$(cb_payload xclip)"

t 'xsel is chosen when pbcopy, wl-copy and xclip are absent'
cb_reset
cb_probe '_hop_act_copy "hello world"' xsel clip.exe >/dev/null 2>"$CB_ERR"
assert_eq $'xsel\t--clipboard\t--input' "$(cb_calls)"
assert_eq 'hello world' "$(cb_payload xsel)"

t 'clip.exe is the last resort, chosen only when nothing else is present'
cb_reset
cb_probe '_hop_act_copy "hello world"' clip.exe >/dev/null 2>"$CB_ERR"
assert_eq 'clip.exe' "$(cb_calls)"
assert_eq 'hello world' "$(cb_payload clip.exe)"

# ---------------------------------------------------------------------------
# HOP_CLIPBOARD is a hard override, bypassing the preference order above.
# ---------------------------------------------------------------------------
t 'HOP_CLIPBOARD overrides the probe even when pbcopy is available'
cb_reset
cb_probe_override '_hop_act_copy "hello world"' xsel pbcopy wl-copy xclip xsel clip.exe >/dev/null 2>"$CB_ERR"
assert_eq 'xsel' "$(cb_calls)"
assert_eq 'hello world' "$(cb_payload xsel)"

t 'HOP_CLIPBOARD word-splits so extra arguments reach the command'
cb_reset
cb_probe_override '_hop_act_copy "hello world"' 'xclip -sel c' pbcopy wl-copy xclip xsel clip.exe >/dev/null 2>"$CB_ERR"
assert_eq $'xclip\t-sel\tc' "$(cb_calls)"
assert_eq 'hello world' "$(cb_payload xclip)"

# ---------------------------------------------------------------------------
# The payload, not just the tool, must be right.
# ---------------------------------------------------------------------------
t 'the exact text handed to hop is what reaches the clipboard tool, unmodified'
cb_reset
cb_probe '_hop_act_copy "/a/b c/terragrunt.hcl"' pbcopy >/dev/null 2>"$CB_ERR"
assert_eq '/a/b c/terragrunt.hcl' "$(cb_payload pbcopy)"

t 'the copy is a stdin pipe, never an argv, even for tools that take extra flags'
cb_reset
cb_probe '_hop_act_copy "secret-path"' xsel >/dev/null 2>"$CB_ERR"
assert_not_contains "$(cb_calls)" 'secret-path'
assert_eq 'secret-path' "$(cb_payload xsel)"

# ---------------------------------------------------------------------------
# Nothing available.
# ---------------------------------------------------------------------------
t 'no clipboard tool available: one clear stderr line, non-zero exit, nothing invoked'
cb_reset
typeset out
out=$(cb_probe '_hop_act_copy "hello world"; print -r -- "exit:$?"' 2>"$CB_ERR")
assert_contains "$out" 'exit:1'
assert_empty "$(cb_calls)"
typeset msg
msg=$(<"$CB_ERR")
assert_contains "$msg" 'hop:'
assert_contains "$msg" 'clipboard'
typeset -a msglines=(${(f)msg})
assert_eq 1 $#msglines 'the no-tool message must be exactly one line'

t 'no clipboard tool available: the message names install options, not a stack trace'
assert_contains "$msg" 'pbcopy'
assert_contains "$msg" 'xclip'

# ---------------------------------------------------------------------------
# A clipboard command that runs but fails must not be reported as a success.
# ---------------------------------------------------------------------------
typeset -g CB_BROKEN=''

# cb_broken_bin -> path to a stub that consumes stdin and always exits 5, once per suite run.
cb_broken_bin() {
	emulate -L zsh
	[[ -z $CB_BROKEN ]] || return 0
	local REPLY
	fixture_tmpdir clipbroken || return 1
	print -rl -- \
		'#!/usr/bin/env zsh' \
		'emulate -L zsh' \
		'IFS= read -r -d "" _ <&0' \
		'exit 5' > "$REPLY/broken-clip"
	chmod +x "$REPLY/broken-clip" || return 1
	CB_BROKEN="$REPLY/broken-clip"
	return 0
}

t 'a failing clipboard command is reported, not swallowed as success'
cb_reset
cb_broken_bin
out=$(cb_probe_override '_hop_act_copy "hello world"; print -r -- "exit:$?"' "$CB_BROKEN" 2>"$CB_ERR")
assert_contains "$out" 'exit:5'
assert_not_contains "$out" 'hop: copied'
msg=$(<"$CB_ERR")
assert_contains "$msg" 'hop:'
assert_contains "$msg" "$CB_BROKEN"
assert_contains "$msg" 'hello world'
