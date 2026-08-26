#!/usr/bin/env zsh
# hop test fixtures: throwaway git repos, fake binaries, and a child shell to probe hop in.
# - Tests assert against synthetic repos, because a real checkout changes under you.
# - Tests must never run the real `code`, `gh` or `$EDITOR`: an early run opened editor windows.
# - Every directory a fixture makes is registered, and the EXIT trap removes the lot.

# The resolved temp root, because mktemp hands back /var/... while `:A` reports /private/var/...
typeset -g HOP_FIX_TMPROOT=${${TMPDIR:-/tmp}:A}

typeset -ga HOP_FIX_DIRS=()
typeset -g  HOP_FIX_REPO=''
typeset -g  HOP_FIX_STUBDIR=''
typeset -g  HOP_FIX_LOG=''
typeset -g  HOP_FIX_HIST=''
typeset -g  HOP_FIX_CONFIG=''

# A path that cannot exist, which is how a probe asks hop.zsh for the SHIPPED presets.
# - hop.zsh sources $HOP_CONFIG when it is readable, and that file is the USER'S personal one.
# - Inheriting it would make every kind assertion depend on whose laptop the suite ran on.
typeset -g HOP_FIX_NOCONFIG="${HOP_FIX_TMPROOT}/hop-tests-no-such-config.zsh"

# A throwaway $HOME, because hop resolves EVERY default path through $HOME or an XDG variable.
# - Created eagerly, since a lazy accessor called from $(...) would build a dir the parent forgets.
typeset -g HOP_FIX_HOME=''

# fixture_cleanup -> remove every directory a fixture created.
# - The temp-root prefix check is the guard that makes a stray value unable to delete anything.
fixture_cleanup() {
	emulate -L zsh
	local d
	for d in "${HOP_FIX_DIRS[@]}"; do
		[[ -n $d && -d $d && $d == ${HOP_FIX_TMPROOT}/* ]] || continue
		rm -rf -- "$d"
	done
	HOP_FIX_DIRS=()
	HOP_FIX_REPO=''
	HOP_FIX_STUBDIR=''
	return 0
}
trap fixture_cleanup EXIT INT TERM

# _hop_fix_git <args...> -> git with the real user's config, hooks and templates cut out.
# - A global `core.hooksPath` or a commit template would otherwise leak into every fixture.
_hop_fix_git() {
	emulate -L zsh
	GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TEMPLATE_DIR='' \
		git -c commit.gpgsign=false -c advice.detachedHead=false "$@"
}

# fixture_tmpdir [label] -> REPLY is a new empty temp dir, resolved through any symlink.
# - The path is resolved because `git rev-parse --show-toplevel` reports the resolved form.
fixture_tmpdir() {
	emulate -L zsh
	local d
	d=$(mktemp -d "${HOP_FIX_TMPROOT}/hop-${1:-fix}.XXXXXX") || return 1
	REPLY=${d:A}
	HOP_FIX_DIRS+=("$REPLY")
	return 0
}

# _hop_fix_home_init -> build the throwaway $HOME every probe child is pinned to.
# - The XDG directories are created too, so a child writing a default path lands inside this dir.
# - `local REPLY` keeps this out of the global REPLY a suite is about to use for its own fixture.
_hop_fix_home_init() {
	emulate -L zsh
	local REPLY
	fixture_tmpdir home || return 1
	HOP_FIX_HOME=$REPLY
	mkdir -p -- "$REPLY/.config" "$REPLY/.local/state" "$REPLY/.cache" || return 1
	return 0
}
if ! _hop_fix_home_init; then
	print -ru2 -- 'fixture: could not build a throwaway $HOME, so no probe would be hermetic'
	return 1
fi

# fixture_repo [label] -> REPLY is a fresh git repo with no commits yet; HOP_FIX_REPO points at it.
# - Branch is forced to main so the init hint never appears in captured output.
fixture_repo() {
	emulate -L zsh
	fixture_tmpdir "${1:-repo}" || return 1
	local d=$REPLY
	_hop_fix_git -C "$d" init -q -b main || return 1
	_hop_fix_git -C "$d" config user.email 'hop-tests@example.invalid' || return 1
	_hop_fix_git -C "$d" config user.name 'hop tests' || return 1
	HOP_FIX_REPO=$d
	REPLY=$d
	return 0
}

# fixture_write <relative-path> [line...] -> write a file in the fixture repo, parents included.
# - With no lines the file is created empty, which is how a .gitkeep case gets built.
fixture_write() {
	emulate -L zsh
	if [[ -z $HOP_FIX_REPO ]]; then
		print -ru2 -- 'fixture_write: no fixture repo, call fixture_repo first'
		return 1
	fi
	local p="${HOP_FIX_REPO}/$1"
	shift
	mkdir -p -- "${p:h}" || return 1
	if (( $# )); then
		print -rl -- "$@" > "$p"
	else
		: > "$p"
	fi
	return 0
}

# fixture_mkdir <relative-path> -> an empty directory in the fixture repo.
# - git tracks no empty directory, so this only matters for the -d tests providers make.
fixture_mkdir() {
	emulate -L zsh
	[[ -n $HOP_FIX_REPO ]] || return 1
	mkdir -p -- "${HOP_FIX_REPO}/$1"
}

# fixture_commit [message] -> stage everything and commit it.
# - --allow-empty keeps a fixture that only made directories from failing here.
fixture_commit() {
	emulate -L zsh
	[[ -n $HOP_FIX_REPO ]] || return 1
	_hop_fix_git -C "$HOP_FIX_REPO" add -A || return 1
	_hop_fix_git -C "$HOP_FIX_REPO" commit -q --allow-empty --no-gpg-sign -m "${1:-fixture}"
}

# fixture_histfile -> HOP_HISTFILE points at a throwaway file, so ranking can be tested.
# - The real history lives under ~/.local/state/hop and a test must never append to it.
fixture_histfile() {
	emulate -L zsh
	if [[ -z $HOP_FIX_HIST ]]; then
		local REPLY
		fixture_tmpdir hist || return 1
		HOP_FIX_HIST="$REPLY/history"
	fi
	print -rl -- "$@" > "$HOP_FIX_HIST"
	export HOP_HISTFILE=$HOP_FIX_HIST
	return 0
}

# fixture_config <line...> -> write a hop config and point HOP_FIX_CONFIG at it.
# - Every probe below reads HOP_FIX_CONFIG, so this is how a test declares its own kinds.
# - Call fixture_config_reset to go back to the shipped presets.
fixture_config() {
	emulate -L zsh
	if [[ -z $HOP_FIX_CONFIG ]]; then
		local REPLY
		fixture_tmpdir config || return 1
		HOP_FIX_CONFIG="$REPLY/config.zsh"
	fi
	print -rl -- "$@" > "$HOP_FIX_CONFIG"
	return 0
}

# fixture_config_reset -> forget any fixture config, so a probe loads the shipped presets instead.
fixture_config_reset() {
	emulate -L zsh
	HOP_FIX_CONFIG=''
	return 0
}

# _hop_fix_config -> the config path a probe should use, real or deliberately absent.
_hop_fix_config() {
	emulate -L zsh
	print -rn -- "${HOP_FIX_CONFIG:-$HOP_FIX_NOCONFIG}"
}

# fixture_sources <group> -> `reply` is every file in that group; REPLY names any empty component.
# - Three suites scan a file list for a banned construct, and each guarded it with a hand floor.
# - A floor drifts: one typo'd glob took a list from 18 files to 12, still over its floor of 10.
# - The planted become() in lib/ went undetected while that guard reported healthy, so no constant.
# - Every component is a whole-directory read, which has no subset for a typo to quietly select.
# - It either names a real directory or matches nothing, and nothing is what REPLY reports.
fixture_sources() {
	emulate -L zsh
	setopt local_options null_glob no_nomatch
	local -a specs=()
	case $1 in
		# The executable source: what a ban on a construct has to be scanned across.
		shipped) specs=('hop.zsh' 'lib/*(.)' 'presets/*(.)' 'bin/*(.)' 'completions/_*(.)') ;;
		# The enumeration source: shipped minus completions, which never talks to git.
		enum) specs=('hop.zsh' 'lib/*(.)' 'presets/*(.)' 'bin/*(.)') ;;
		# Everything `zsh -n` must accept, the test harness included.
		parseable) specs=('hop.zsh' 'config.example.zsh' 'lib/*(.)' 'presets/*(.)' 'bin/*(.)' \
			'completions/_*(.)' 'tests/run' 'tests/lib/*(.)' 'tests/suite_*.zsh') ;;
		*) print -ru2 -- "fixture_sources: unknown group: ${1}"; return 2 ;;
	esac
	reply=()
	local spec
	local -a hit=() empty=()
	for spec in "${specs[@]}"; do
		hit=($HOP_HOME/${~spec})
		if (( $#hit == 0 )); then
			empty+=("$spec")
			continue
		fi
		reply+=("${hit[@]}")
	done
	REPLY=${(pj:\n:)empty}
	(( $#empty == 0 ))
}

# stub_bin [name...] -> put recording no-op stubs for these commands first on PATH.
# - The default list is every external command a hop action can shell out to.
# - Each invocation appends one TAB-separated line to $HOP_FIX_LOG for later assertion.
# - EDITOR and VISUAL are redirected too, since _hop_act_edit resolves the editor through them.
stub_bin() {
	emulate -L zsh
	local -a names=("$@")
	(( $#names )) || names=(code gh bat pbcopy pbpaste open editor vim nvim)
	if [[ -z $HOP_FIX_STUBDIR ]]; then
		local REPLY
		fixture_tmpdir stubbin || return 1
		HOP_FIX_STUBDIR=$REPLY
		HOP_FIX_LOG="$REPLY/calls.log"
		: > "$HOP_FIX_LOG"
		export HOP_FIX_LOG
		path=("$HOP_FIX_STUBDIR" $path)
		names+=(editor)
	fi
	local n
	for n in "${names[@]}"; do
		[[ -n $n ]] || continue
		print -rl -- \
			'#!/bin/sh' \
			'# hop test stub: records the call and exits 0, so nothing reaches the desktop.' \
			"printf '%s' '${n}' >> \"\$HOP_FIX_LOG\"" \
			'for a in "$@"; do printf "\t%s" "$a" >> "$HOP_FIX_LOG"; done' \
			'printf "\n" >> "$HOP_FIX_LOG"' \
			'exit 0' > "$HOP_FIX_STUBDIR/$n"
		chmod +x "$HOP_FIX_STUBDIR/$n" || return 1
	done
	export EDITOR="$HOP_FIX_STUBDIR/editor"
	export VISUAL="$HOP_FIX_STUBDIR/editor"
	rehash
	return 0
}

# stub_calls [name] -> the recorded calls, newest last, optionally for one command only.
stub_calls() {
	emulate -L zsh
	[[ -n ${HOP_FIX_LOG:-} && -r ${HOP_FIX_LOG:-} ]] || return 1
	local -a lines=("${(@f)$(<"$HOP_FIX_LOG")}")
	lines=(${lines:#})
	if (( $# )); then
		lines=(${(M)lines:#$1$'\t'*})
	fi
	print -rl -- "${lines[@]}"
	return 0
}

# stub_reset -> forget every recorded call, for a test that asserts on a single invocation.
stub_reset() {
	emulate -L zsh
	[[ -n ${HOP_FIX_LOG:-} ]] || return 0
	: > "$HOP_FIX_LOG"
}

# fixture_pins -> `export` lines a child shell must run before it sources hop.zsh.
# - Emitted as code for INSIDE the child, because a `local VAR=` is dynamically scoped, not exported.
# - Measured: `local HOME=/nope; hop_probe 'print $HOME'` printed the REAL $HOME.
# - Not delivered via `env`, because suite_clipboard hands a probe a PATH with no env on it.
# - HOME and the XDG pins are load-bearing, not tidiness: every default path resolves through them.
# - Unpinned, a probe READ the real ~/.config/hop/workspaces and SOURCED the real config.zsh.
# - HOP_HOPRC is forced empty, so a .hoprc in a fixture repo can never run inside a probe.
# - HOP_CONFIG is forced too, because the default points at the USER'S OWN config.zsh.
# - Without that the suite would assert against whatever kinds this laptop happens to declare.
# - HOP_DEBUG is forced OFF, so an exported HOP_DEBUG=1 cannot make a test write the real debug log.
# - A test that WANTS logging sets HOP_DEBUG inside the probe code, where it is visible.
# - HOP_HISTFILE defaults to /dev/null so a probe cannot touch the real frecency history.
# - PATH is passed explicitly for the same dynamic-scope reason as HOME.
fixture_pins() {
	emulate -L zsh
	local home=$HOP_FIX_HOME
	local config="${home}/.config" state="${home}/.local/state" cache="${home}/.cache"
	local hopconfig="$(_hop_fix_config)" hist=${HOP_HISTFILE:-/dev/null}
	print -rl -- \
		"export HOME=${(q)home}" \
		"export XDG_CONFIG_HOME=${(q)config}" \
		"export XDG_STATE_HOME=${(q)state}" \
		"export XDG_CACHE_HOME=${(q)cache}" \
		"export HOP_CONFIG=${(q)hopconfig}" \
		"export HOP_HOPRC=''" \
		"export HOP_DEBUG=''" \
		"export HOP_HISTFILE=${(q)hist}" \
		"export PATH=${(q)PATH}"
}

# hop_probe <zsh-code> -> run the code in a fresh shell with hop.zsh sourced, and print its output.
# - A child shell means a provider under test cannot leave functions behind in the suite process.
# - -f skips the user's rc files, which is what keeps a probe hermetic and fast.
# - The child is non-interactive, so hop.zsh never reaches its bindkey block.
# - Nothing here can start fzf: the caller supplies the code, and fzf only ever runs with --filter.
# - The environment is fixture_pins, where each pin says why it is not optional.
hop_probe() {
	emulate -L zsh
	local code=$1
	zsh -f -c "$(fixture_pins)
source ${(q)HOP_HOME}/hop.zsh || exit 97
${code}"
}

# fzf_filter <query> -> fzf's non-interactive matcher, fed rows on stdin.
# - --filter is the only fzf mode a test may use, because it never opens a terminal.
# - The flags mirror the real _hop_pick call, so a match here means a match in the picker.
fzf_filter() {
	emulate -L zsh
	(( ${+commands[fzf]} )) || return 127
	fzf --filter="$1" --delimiter=$'\t' --with-nth=1 --tiebreak=begin,index
}
