#!/usr/bin/env zsh
# hop actions: one function per verb, all dispatched from the key --expect returned.

# History of visited dirs, most-recent-first, used to float familiar rows to the top.
typeset -g HOP_HISTFILE=${HOP_HISTFILE:-${XDG_STATE_HOME:-$HOME/.local/state}/hop/history}
typeset -g HOP_HIST_MAX=${HOP_HIST_MAX:-300}

# _hop_need <command> <what-for> -> 0 if runnable, else one line on stderr
# - A bare name is resolved on $PATH, same as always.
# - A name with a slash (absolute, or relative like ./bin/ed) is a path zsh execs directly.
_hop_need() {
	emulate -L zsh
	if [[ $1 == */* ]]; then
		if [[ -x $1 && ! -d $1 ]]; then
			return 0
		fi
		if [[ ! -e $1 ]]; then
			print -ru2 -- "hop: ${1} does not exist, cannot ${2}"
		else
			print -ru2 -- "hop: ${1} is not executable, cannot ${2}"
		fi
		return 1
	fi
	if (( ${+commands[$1]} )); then
		return 0
	fi
	print -ru2 -- "hop: ${1} is not installed, cannot ${2}"
	return 1
}

# _hop_editor -> REPLY, the terminal editor to fall back to when `code` is absent.
_hop_editor() {
	emulate -L zsh
	REPLY=${VISUAL:-${EDITOR:-vi}}
	[[ -n $REPLY ]]
}

# _hop_remember <dir> -> push dir onto the front of the MRU list, deduped and bounded.
# - Rewriting the whole file is fork-free via $(<file) and the list never exceeds HOP_HIST_MAX.
_hop_remember() {
	emulate -L zsh
	local dir=$1
	[[ -n $dir && -n ${HOP_HISTFILE:-} ]] || return 0
	local d=${HOP_HISTFILE:h}
	[[ -d $d ]] || mkdir -p -- "$d" 2>/dev/null || return 0
	local -a h
	[[ -r $HOP_HISTFILE ]] && h=("${(@f)$(<"$HOP_HISTFILE")}")
	h=("$dir" ${h:#$dir})
	h=(${h:#})
	print -rl -- "${(@)h[1,$HOP_HIST_MAX]}" > "$HOP_HISTFILE" 2>/dev/null
	return 0
}

# `cd`, not `builtin cd`, on purpose: a zoxide/autojump wrapper and chpwd hooks should still fire.
_hop_act_cd() {
	emulate -L zsh
	local dir=$1
	if [[ ! -d $dir ]]; then
		print -ru2 -- "hop: not a directory: ${dir}"
		return 1
	fi
	cd "$dir" || return $?
	_hop_remember "$dir"
}

# code -r reveals the file's directory in the explorer, so this doubles as "show me where this lives".
# - Falls back to $VISUAL/$EDITOR rather than hard-failing, since `code` is not on every machine.
_hop_act_open() {
	emulate -L zsh
	local target=$1
	if [[ ! -e $target ]]; then
		print -ru2 -- "hop: nothing to open at: ${target}"
		return 1
	fi
	if (( ${+commands[code]} )); then
		code -r "$target"
		return $?
	fi
	_hop_act_edit "$target"
}

# alt-o: open in the terminal editor, which gets the real tty because dispatch is back in the shell.
_hop_act_edit() {
	emulate -L zsh
	local target=$1 REPLY
	if [[ ! -e $target ]]; then
		print -ru2 -- "hop: nothing to open at: ${target}"
		return 1
	fi
	_hop_editor
	local -a cmd=(${=REPLY})
	_hop_need "${cmd[1]}" 'edit a file' || return 1
	"${cmd[@]}" "$target"
}

_hop_act_folder() {
	emulate -L zsh
	local dir=$1
	if [[ ! -d $dir ]]; then
		print -ru2 -- "hop: not a directory: ${dir}"
		return 1
	fi
	if (( ${+commands[code]} )); then
		code "$dir"
		return $?
	fi
	_hop_act_edit "$dir"
}

_hop_act_copy() {
	emulate -L zsh
	local what=$1
	local -a cmd
	# HOP_CLIPBOARD is a hard override, word-split so `xclip -sel c` works, and skips the probe below.
	if [[ -n ${HOP_CLIPBOARD:-} ]]; then
		cmd=(${=HOP_CLIPBOARD})
	# Preference order, first match wins:
	# - pbcopy: native on macOS.
	# - wl-copy: Wayland, checked before X11 because a Wayland session often still has xclip installed.
	# - xclip / xsel: the two common X11 clipboard tools.
	# - clip.exe: WSL's bridge back to the Windows clipboard.
	elif (( ${+commands[pbcopy]} )); then
		cmd=(pbcopy)
	elif (( ${+commands[wl-copy]} )); then
		cmd=(wl-copy)
	elif (( ${+commands[xclip]} )); then
		cmd=(xclip -selection clipboard)
	elif (( ${+commands[xsel]} )); then
		cmd=(xsel --clipboard --input)
	elif (( ${+commands[clip.exe]} )); then
		cmd=(clip.exe)
	else
		# _hop_need only ever names ONE command, and no single tool is right across every platform here.
		print -ru2 -- 'hop: no clipboard tool found, install pbcopy, wl-copy, xclip, xsel, or clip.exe (WSL)'
		return 1
	fi
	print -rn -- "$what" | "${cmd[@]}"
	# ${pipestatus[-1]} names the clipboard tool's own exit status, deliberately, not just $?.
	local rc=${pipestatus[-1]}
	if (( rc != 0 )); then
		print -ru2 -- "hop: ${cmd[1]} failed to copy ${what}"
		return $rc
	fi
	print -r -- "hop: copied ${what}"
}

# gh resolves the remote from the cwd, so this runs from inside the repo and passes a relative path.
# - The dir is canonicalised first: on macOS /tmp is a symlink, so a $HOP_REPOS entry under it
#   never prefix-matched --show-toplevel and the strip silently produced a bogus relative path.
_hop_act_browse() {
	emulate -L zsh
	local dir=${1:A}
	_hop_need gh 'browse on GitHub' || return 1
	local root
	root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
	root=${root:A}
	if [[ -z $root ]]; then
		# Reached most often by pressing ctrl-g on a WORKSPACE row, meaning to go deeper.
		# - ^G launches hop, so ctrl-g inside it reads as "again", but it is the browse verb.
		# - Naming the drill key here is the only place the mistake is visible enough to correct.
		print -ru2 -- "hop: not in a git repository: ${dir}"
		print -ru2 -- 'hop: to go INTO a repo from a workspace, press l (NORMAL) or ctrl-l (SEARCH)'
		return 1
	fi
	if [[ $dir == "$root" ]]; then
		( builtin cd -q -- "$root" && gh browse )
		return $?
	fi
	if [[ $dir != "$root"/* ]]; then
		print -ru2 -- "hop: ${dir} is not inside ${root}, refusing to guess a path"
		return 1
	fi
	( builtin cd -q -- "$root" && gh browse -- "${dir#"$root"/}" )
}

# _hop_dispatch <key> <dir> <preview>
# - An empty key is plain Enter, which is the only verb allowed to cd.
# - Every side-effect verb leaves the shell where it was, per the spec.
# - ^Y and M-y are split because the preview pane shows a file while the row's dir is a directory.
_hop_dispatch() {
	emulate -L zsh
	local key=$1 dir=$2 preview=${3:-$2}
	_hop_dbg "dispatch key=${key:-<enter>} dir=${dir} preview=${preview}"
	case $key in
		'') _hop_act_cd "$dir" ;;
		ctrl-o) _hop_act_open "$preview" ;;
		ctrl-t) _hop_act_folder "$dir" ;;
		ctrl-y) _hop_act_copy "$dir" ;;
		ctrl-g) _hop_act_browse "$dir" ;;
		alt-o) _hop_act_edit "$preview" ;;
		alt-y) _hop_act_copy "$preview" ;;
		*)
			print -ru2 -- "hop: unhandled key: ${key}"
			return 1
			;;
	esac
}
