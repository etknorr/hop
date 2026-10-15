#!/usr/bin/env zsh
# hop actions: one function per verb, all dispatched from the key --expect returned.

# History of visited dirs, most-recent-first, used to float familiar rows to the top.
typeset -g HOP_HISTFILE=${HOP_HISTFILE:-${XDG_STATE_HOME:-$HOME/.local/state}/hop/history}
typeset -g HOP_HIST_MAX=${HOP_HIST_MAX:-300}

# When a query may skip the picker: auto (any clear match), unique (one target only), never (always pick).
typeset -g HOP_JUMP=${HOP_JUMP:-auto}

# What Enter does to the target: cd, open, reveal, cd+open or cd+reveal.
# - Set here and not in hop(), because config.zsh is sourced after lib/ and has to win.
typeset -g HOP_ACTION=${HOP_ACTION:-cd}

# A VS Code-compatible CLI that accepts -r and -n: code, cursor, codium, code-insiders.
# - Word-split like HOP_CLIPBOARD, so a launcher can carry its own flags.
typeset -g HOP_CODE=${HOP_CODE:-code}

typeset -ga _HOP_ACTIONS=(cd open reveal cd+open cd+reveal)

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

# _hop_remember <dir> -> push dir onto the front of the MRU list, deduped, pruned and bounded.
# - Rewriting the whole file is fork-free via $(<file) and the list never exceeds HOP_HIST_MAX.
# - An entry that is no longer a directory is dropped, since it can never rank a row again.
# - Unpruned, 27 of 30 entries in one real history named dirs that were gone, crowding out live ones.
# - The (N-/) qualifier is one stat per entry, follows a symlinked dir, and reads each entry literally.
# - Only absolute entries are kept, so a stray relative line cannot survive by naming a dir under $PWD.
_hop_remember() {
	emulate -L zsh
	local dir=$1
	[[ -n $dir && -n ${HOP_HISTFILE:-} ]] || return 0
	local d=${HOP_HISTFILE:h}
	[[ -d $d ]] || mkdir -p -- "$d" 2>/dev/null || return 0
	local -a h
	[[ -r $HOP_HISTFILE ]] && h=("${(@f)$(<"$HOP_HISTFILE")}")
	h=("$dir" ${h:#$dir})
	h=(${(M)h:#/*})
	h=(${^h}(N-/))
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

# _hop_action_mode <value> [quiet] -> REPLY is the value when it names a mode, else cd with one warning.
# - hop() calls it once per call, so an invalid HOP_ACTION warns once rather than on every row.
# - quiet is for the legends, which only describe the mode and must not repeat the warning.
_hop_action_mode() {
	emulate -L zsh
	REPLY=$1
	(( ${_HOP_ACTIONS[(Ie)$REPLY]} )) && return 0
	[[ -n ${2:-} ]] || print -ru2 -- "hop: HOP_ACTION=${1} is not one of ${(j:, :)_HOP_ACTIONS}; using cd"
	REPLY=cd
	return 1
}

# _hop_enter_mode -> REPLY is what Enter does in this call: hop()'s resolved mode, else HOP_ACTION.
# - On workspace and repo rows reveal is named open, because there it runs `code -n` too; see _hop_act_enter.
_hop_enter_mode() {
	emulate -L zsh
	if [[ -n ${_hop_mode:-} ]]; then
		REPLY=$_hop_mode
	else
		_hop_action_mode "${HOP_ACTION:-cd}" quiet
	fi
	(( ${_hop_folder_rows:-0} )) && REPLY=${REPLY/reveal/open}
	return 0
}

# _hop_code_cmd -> reply is the VS Code launcher argv, HOP_CODE word-split.
_hop_code_cmd() {
	emulate -L zsh
	reply=(${=${HOP_CODE:-code}})
	(( $#reply )) || reply=(code)
}

# _hop_code_usable -> 0 when the launcher can reach a VS Code window, else 1 with the reason in REPLY.
# - A live VSCODE_IPC_HOOK_CLI socket is a window attached to this terminal, so it settles the question.
# - That includes Remote-SSH, where the remote host has no DISPLAY yet `code` still reaches the window.
# - A stale hook is a terminal that outlived its window, where `code` fails or opens on the wrong host.
# - With no hook, an SSH session means `code` would start on the remote host, which has no window.
# - Linux with no DISPLAY or WAYLAND_DISPLAY has no screen to open one on.
# - Except under WSL, where `code` is the Windows-side shim and opens VS Code on Windows with no X or Wayland at all.
_hop_code_usable() {
	emulate -L zsh
	local -a reply
	_hop_code_cmd
	if ! _hop_need "${reply[1]}" 'open VS Code' 2>/dev/null; then
		REPLY=$(_hop_need "${reply[1]}" 'open VS Code' 2>&1)
		REPLY=${REPLY#hop: }
		return 1
	fi
	if [[ -n ${VSCODE_IPC_HOOK_CLI:-} ]]; then
		[[ -S $VSCODE_IPC_HOOK_CLI ]] && return 0
		REPLY="VSCODE_IPC_HOOK_CLI names no live VS Code socket: ${VSCODE_IPC_HOOK_CLI}"
		return 1
	fi
	if [[ -n ${SSH_CONNECTION:-} || -n ${SSH_TTY:-} ]]; then
		REPLY='this is an SSH session with no VS Code window attached'
		return 1
	fi
	if [[ $OSTYPE == linux* && -z ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} && -z ${WSL_DISTRO_NAME:-} && -z ${WSL_INTEROP:-} ]]; then
		REPLY='there is no DISPLAY or WAYLAND_DISPLAY for VS Code to open on'
		return 1
	fi
	REPLY=''
	return 0
}

# _hop_code <arg...> -> run the launcher with these arguments, and return its status.
_hop_code() {
	emulate -L zsh
	local -a reply
	_hop_code_cmd
	"${reply[@]}" "$@"
}

# _hop_code_fallback <reason> <path> -> the terminal editor instead of VS Code, after saying why.
# - With no terminal there is no editor to hand the tty to, so the path is printed instead.
_hop_code_fallback() {
	emulate -L zsh
	print -ru2 -- "hop: ${1}; using the terminal editor instead"
	if ! _hop_tty_ok; then
		print -ru2 -- "hop: no terminal for an editor; target: ${2}"
		return 1
	fi
	_hop_act_edit "$2"
}

# ctrl-o: open the preview in VS Code, or in $VISUAL/$EDITOR when VS Code is not reachable.
# - A file gets `code -r`, which opens it in the last-focused window instead of a new one.
# - `-r` does not reveal anything by itself: the explorer follows only with explorer.autoReveal, inside an open folder.
# - A directory gets `code -n`, because `code -r <dir>` reloads the focused window onto that folder.
# - A dir preview is real: a row whose dir holds no previewable file previews the dir itself.
_hop_act_open() {
	emulate -L zsh
	local target=$1 REPLY
	if [[ ! -e $target ]]; then
		print -ru2 -- "hop: nothing to open at: ${target}"
		return 1
	fi
	_hop_code_usable || { _hop_code_fallback "$REPLY" "$target"; return $? }
	if [[ -d $target ]]; then
		_hop_code -n "$target"
	else
		_hop_code -r "$target"
	fi
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

# ctrl-t: the row's dir as a VS Code folder, always in a window of its own.
# - `-n` because a bare `code <dir>` obeys window.openFoldersInNewWindow, and at `off` it replaces the open workspace.
_hop_act_folder() {
	emulate -L zsh
	local dir=$1 REPLY
	if [[ ! -d $dir ]]; then
		print -ru2 -- "hop: not a directory: ${dir}"
		return 1
	fi
	_hop_code_usable || { _hop_code_fallback "$REPLY" "$dir"; return $? }
	_hop_code -n "$dir"
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

# _hop_reveal_file <dir> -> REPLY is the file that stands for a directory in VS Code's explorer.
# - VS Code cannot reveal a folder from the shell, so revealing a dir means revealing a file at its top.
# - A top-level README first, then the first regular file by name; 1 when the top holds no file at all.
_hop_reveal_file() {
	emulate -L zsh
	setopt local_options extended_glob
	local -a f=("$1"/(#i)README*(.N))
	(( $#f )) || f=("$1"/*(.N))
	REPLY=${f[1]-}
	[[ -n $REPLY ]]
}

# _hop_act_reveal <dir> <preview> <rel> [after-cd] -> show a dir target in the explorer, through a file inside it.
# - A file preview is the unit's own representative file, so it is the one revealed.
# - A dir preview names no file, so _hop_reveal_file picks one, and a top with none gets the note.
# - After a cd that note is not a failure, since the cd it followed was the point.
_hop_act_reveal() {
	emulate -L zsh
	local dir=$1 preview=$2 rel=${3:-$1} REPLY
	local -i after=${4:-0}
	if [[ -f $preview ]]; then
		_hop_code -r "$preview"
		return $?
	fi
	if _hop_reveal_file "$dir"; then
		_hop_code -r "$REPLY"
		return $?
	fi
	print -ru2 -- "hop: nothing to reveal at the top of ${rel}; use -o to open it as a folder"
	return $(( ! after ))
}

# _hop_act_enter <dir> <preview> <rel> -> Enter, a jump and headless dispatch, applying the mode's command.
# - A rel without a trailing / is a file target, whose dir is only its parent; see _hop_row.
# - A missing rel is a dir target, which is what a 3-field caller always handed over.
# - open on a dir is always `code -n`, and `code -r` only ever gets a file: `-r <dir>` reloads the focused window.
# - Workspace and repo rows name a whole folder, so open and reveal both mean a window on it; see _hop_folder_rows.
# - cd runs first, so chpwd and zoxide fire, and a code call that fails afterwards keeps the cd and returns its status.
_hop_act_enter() {
	emulate -L zsh
	local dir=$1 preview=${2:-$1} rel=${3:-} REPLY mode
	if [[ -n ${_hop_mode:-} ]]; then
		mode=$_hop_mode
	else
		_hop_action_mode "${HOP_ACTION:-cd}"
		mode=$REPLY
	fi
	local -i cd=0 file=0 whole=${_hop_folder_rows:-0}
	[[ $mode == cd* ]] && cd=1
	local verb=${${mode#cd}#+}
	(( ! whole )) && [[ -n $rel && $rel != */ ]] && file=1

	if (( cd )); then
		_hop_act_cd "$dir" || return $?
		[[ -n $verb ]] || return 0
	elif [[ -d $dir ]]; then
		_hop_remember "$dir"
	else
		print -ru2 -- "hop: not a directory: ${dir}"
		return 1
	fi
	if (( file )) && [[ ! -e $preview ]]; then
		print -ru2 -- "hop: nothing to open at: ${preview}"
		return 1
	fi

	if ! _hop_code_usable; then
		if (( cd )); then
			print -ru2 -- "hop: ${REPLY}, so this was a cd only"
			return 0
		fi
		if (( file )); then
			_hop_code_fallback "$REPLY" "$preview"
		elif [[ $verb == open ]] || (( whole )); then
			_hop_code_fallback "$REPLY" "$dir"
		elif [[ -f $preview ]]; then
			# -o here falls back on the dir, so pointing at it as a way to see this file would mislead.
			print -ru2 -- "hop: ${REPLY}, and only VS Code can reveal ${preview:t} in ${rel:-$dir}; -o opens the directory itself in the terminal editor"
			return 1
		else
			print -ru2 -- "hop: ${REPLY}, and only VS Code can reveal ${rel:-$dir}; use -o to open it in the terminal editor"
			return 1
		fi
		return $?
	fi

	if (( file )); then
		_hop_code -r "$preview"
	elif [[ $verb == open ]] || (( whole )); then
		_hop_code -n "$dir"
	else
		_hop_act_reveal "$dir" "$preview" "${rel:-$dir}" "$cd"
	fi
}

# _hop_dispatch <key> <dir> <preview> [rel]
# - An empty key is plain Enter, which applies the mode; alt-enter and NORMAL c always cd, whatever the mode.
# - Every other verb leaves the shell where it was, per the spec.
# - ^Y and M-y are split because the preview pane shows a file while the row's dir is a directory.
# - Every verb that navigates is remembered, so the MRU keeps learning when Enter is not cd.
_hop_dispatch() {
	emulate -L zsh
	local key=$1 dir=$2 preview=${3:-$2} rel=${4:-}
	_hop_dbg "dispatch key=${key:-<enter>} dir=${dir} preview=${preview} rel=${rel}"
	# Every row's dir is absolute, so a relative one is a `:` menu row's kind name, never a place to act on.
	if [[ $dir != /* ]]; then
		print -ru2 -- "hop: not a target directory: ${dir}"
		return 1
	fi
	case $key in
		'') _hop_act_enter "$dir" "$preview" "$rel" ;;
		alt-enter) _hop_act_cd "$dir" ;;
		ctrl-o) _hop_act_open "$preview" && _hop_remember "$dir" ;;
		ctrl-t) _hop_act_folder "$dir" && _hop_remember "$dir" ;;
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
