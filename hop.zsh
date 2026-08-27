#!/usr/bin/env zsh
# hop: a zsh+fzf navigator for large config monorepos.
# - Activated by one line in .zshrc: source ~/.local/share/hop/hop.zsh
# - HOP_HOME is derived from this file's own path, so the directory can move or become its own repo.
# - Nothing here may reference the parent path of $HOP_HOME.

# Derived unconditionally, never inherited, because an inherited value can name the WRONG install.
# - Honouring a pre-set HOP_HOME broke `source ~/.zshrc` in a shell that had loaded an older path.
# - There is no use for an override that points somewhere without this file in it.
typeset -g HOP_HOME="${${(%):-%x}:A:h}"

# Your own hop_kind declarations live here; nothing repo-specific ships in the code.
# - EXPORTED, because bin/hop-kinds and the alt-a reload child both re-source this file to get kinds.
# - fzf runs those from its own environment, so an unexported value left them on the shipped presets.
# - Symptom: the `:` menu showed the eight presets and alt-a/r said `hop: unknown kind: <yours>`.
typeset -gx HOP_CONFIG=${HOP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hop/config.zsh}

# HOP_HOPRC is exported only when you actually set it, so opting in survives into those children.
# - Exporting it unconditionally would invent a variable nobody set, and .hoprc runs repo code.
[[ -z ${HOP_HOPRC:-} ]] || typeset -gx HOP_HOPRC

source "$HOP_HOME/lib/providers.zsh"
source "$HOP_HOME/lib/dsl.zsh"
source "$HOP_HOME/lib/workspaces.zsh"
source "$HOP_HOME/lib/ui.zsh"
source "$HOP_HOME/lib/actions.zsh"
source "$HOP_HOME/lib/doctor.zsh"
source "$HOP_HOME/lib/upgrade.zsh"

# Kinds come from your config, or from every shipped preset when there is no config yet.
# - An unconfigured install still works, which is what makes hop useful in a fresh clone.
if [[ -r $HOP_CONFIG ]]; then
	source "$HOP_CONFIG"
fi
if (( ${#_HOP_ALL_KINDS} == 0 )); then
	hop_preset terragrunt terraform-modules helm serverless puppet backstage dir file
fi

# The default set is whatever was declared --default, unless you pin HOP_DEFAULT_KINDS yourself.
[[ -n ${HOP_DEFAULT_KINDS:-} ]] || _hop_set_default_kinds

if [[ -d $HOP_HOME/completions ]] && (( ! ${fpath[(I)$HOP_HOME/completions]} )); then
	fpath=("$HOP_HOME/completions" $fpath)
fi

_hop_usage() {
	emulate -L zsh
	print -r -- 'usage: hop [-a|--all] [-k KIND[,KIND...]] [-R] [--no-vim] [-h] [/|-] [words...]'
	print -r -- ''
	print -r -- '  hop                 pick from the default kinds, starting in NORMAL mode'
	print -r -- '  hop vpc prod        prefill the query; a unique match jumps with no UI'
	print -r -- '  hop -a, --all       include every registered kind, not just the defaults'
	print -r -- '  hop -k tg,helm      restrict to specific kinds'
	print -r -- '  hop -c, --cwd       only targets under $PWD, for any kind'
	print -r -- '  hop -k file x.yml   find a tracked FILE by name (opt-in: it is every file)'
	print -r -- '  hop -c -k file x    find a file in just this subtree'
	print -r -- '  hop /   hopr        cd to the repo root'
	print -r -- '  hop -               cd -'
	print -r -- '  hop -R, --repos     pick a repo from $HOP_REPOS'
	print -r -- '  hop -w, --workspaces  pick a workspace; enter cds, ctrl-l or l shows its repos'
	print -r -- '  hopw                cd to the workspace containing $PWD (longest prefix wins)'
	print -r -- '  hop --no-vim        search-first fzf, no modal layer (same as HOP_VIM=0)'
	print -r -- '  hop --vim           force the modal layer on when HOP_VIM=0 is set'
	print -r -- '  hop --doctor        dump config, tools and kind counts for a bug report'
	print -r -- '  hop --doctor=short  the same, minus paths and names; safe to paste publicly'
	print -r -- '  HOP_DEBUG=1 hop     log every pick and key dispatch, read it with --doctor'
	print -r -- '  hop upgrade         fast-forward main to the newest release, then exec zsh'
	print -r -- '  hop upgrade 0.1.0   pin the install to exactly that release, detached'
	print -r -- '  hop upgrade --check what is installed vs what is released; changes nothing'
	print -r -- '  hop -V, --version   print the installed version'
	print -r -- '  hop -h, --help      this text'
	print -r -- ''
	print -r -- '  kinds, * being in the default set:'
	local k mark
	for k in "${_HOP_ALL_KINDS[@]}"; do
		if (( ${_HOP_K_DEFAULT[$k]:-0} )); then mark='*'; else mark=' '; fi
		printf '    %s %-12s %s\n' "$mark" "$k" "${_HOP_K_DESC[$k]:-}"
	done
	print -r -- ''
	print -r -- "  declare your own in ${HOP_CONFIG}; see config.example.zsh"
	print -r -- ''
	print -r -- '  NORMAL: j/k move | g/G first/last | ^d/^u half page | enter cd'
	print -r -- '          o code file | O code dir | e $EDITOR file | y/Y copy dir/file'
	print -r -- '          b gh browse | p preview | r refresh | ? help | q or esc quit'
	print -r -- '          l drill in | h back out | / SEARCH | : switch view'
	print -r -- ''
	print -r -- '  : opens the view menu in place; enter switches, esc goes back.'
	print -r -- ''
	print -r -- '  SEARCH: every key types | esc back to NORMAL | enter cd'
	print -r -- '          ctrl-o code -r file | ctrl-t code dir'
	print -r -- '          ctrl-y copy dir | alt-y copy file | alt-o $EDITOR file'
	print -r -- '          ctrl-g gh browse | alt-a all kinds | ctrl-r refresh preview'
	print -r -- '          alt-p or ctrl-/ toggle preview'
	print -r -- ''
	print -r -- '  ^G and alt-g launch hop from a half-typed command line.'
	print -r -- '  ^G replaces zsh send-break; use ^C to abandon a line, or rebind hop-widget.'
	print -r -- '  A repo-root .hoprc is OPT-IN: it runs code, so set HOP_HOPRC=1 to allow it.'
}

# _hop_version -> print "hop X.Y.Z", plus "(describe)" when this install is a git checkout.
# - VERSION is read with a zsh builtin `read`, never `cat`: no fork, even though this path is cold.
# - Works with VERSION missing (falls back to 'unknown') and with git missing (drops the suffix).
_hop_version() {
	emulate -L zsh
	local v='unknown' f="$HOP_HOME/VERSION" line
	if [[ -r $f ]]; then
		read -r line < "$f"
		[[ -n $line ]] && v=$line
	fi
	local desc
	desc=$(git -C "$HOP_HOME" describe --tags --always --dirty 2>/dev/null)
	if [[ -n $desc ]]; then
		print -r -- "hop ${v} (${desc})"
	else
		print -r -- "hop ${v}"
	fi
}

_hop_repos() {
	emulate -L zsh
	setopt local_options null_glob
	local -a repos
	if [[ -n ${HOP_REPOS:-} ]]; then
		repos=("${(s.:.)HOP_REPOS}")
	else
		# No explicit list: every repo in every configured workspace, which needs no second setting.
		local -a wss
		local ws
		if _hop_ws_parse; then
			wss=("${reply[@]}")
			for ws in "${wss[@]}"; do
				_hop_ws_repos "${ws#*$'\t'}" || continue
				repos+=("${reply[@]}")
			done
		fi
	fi
	repos=(${repos:#})
	(( $#repos )) || return 1
	print -rl -- "${(@u)repos}"
}

# _hop_rank <targets> -> the same rows, with previously-visited dirs floated to the top.
# - fzf's final implicit tiebreak is input order, so pre-sorting the input is the whole mechanism.
# - 644 terragrunt units include 36 named `vpc`; alphabetical order buries the one you use daily.
# - The rank+index key keeps the sort stable and survives two rows sharing one dir.
_hop_rank() {
	emulate -L zsh
	local targets=$1
	local -a hist
	[[ -r ${HOP_HISTFILE:-} ]] && hist=("${(@f)$(<"$HOP_HISTFILE")}")
	hist=(${hist:#})
	if (( $#hist == 0 )); then
		print -r -- "$targets"
		return 0
	fi

	local -A rank
	local -i i=0
	local h row d
	for h in "${hist[@]}"; do
		(( ++i ))
		[[ -n ${rank[$h]} ]] || rank[$h]=$i
	done

	local -a keyed
	i=0
	for row in "${(@f)targets}"; do
		d=${${row#*$'\t'}%$'\t'*}
		keyed+=("${(l:6::0:)${rank[$d]:-999999}} ${(l:6::0:)$(( ++i ))}"$'\t'"$row")
	done
	print -rl -- "${(@)${(@o)keyed}#*$'\t'}"
}

# _hop_fzf_status <status> <label> <rows> [query] -> 0 to use fzf's output, non-zero to stop.
# - The only place fzf's exit status is interpreted, and EVERY picker has to route through it.
# - 130 is a user cancel and must stay silent, so "stop" and "failed" are not the same answer.
# - _hop_st is the status the CALLER returns when this says stop, since cancel stops but succeeds.
# - The caller declares it `local`, exactly as _hop_run does for _hop_parse_result's three fields.
# - _hop_ws_picker used to skip this ladder, so a too-old fzf there looked like pressing esc.
# - Also the one HOP_DEBUG line EVERY pick passes through, whether or not a dispatch follows.
# - _hop_dispatch's line was the only one, so a no-match logged nothing and --doctor showed nothing.
# - Those are precisely the failures people file bugs about, so the log has to reach them first.
_hop_fzf_status() {
	emulate -L zsh
	local -i st=$1
	local label=$2 rows=$3 query=${4:-}
	_hop_dbg "pick label=${label} rows=${rows} query=${query} st=${st}"
	_hop_st=0
	(( st == 0 )) && return 0
	if (( st == 130 )); then
		return 1
	fi
	if (( st == 1 )); then
		print -ru2 -- "hop: no match${query:+ for: $query}"
		_hop_st=1
		return 1
	fi
	print -ru2 -- "hop: fzf exited with status ${st}"
	_hop_st=$st
	return 1
}

# _hop_tty_ok -> 0 when a terminal is reachable, so the interactive picker can actually run.
# - fzf reads keys from /dev/tty and NOT from stdin, which is why every redirected shape still works.
# - `hop < /dev/null`, `hop | cat`, `echo x | hop` and `hop 0<&-` all keep their controlling terminal.
# - So this deliberately never looks at stdin, since a stdin test would refuse four shapes that work.
# - The real failure is having no controlling terminal at all: a script, a cron job, a CI step.
# - There fzf 0.73.1 does not error; it starts, writes nothing, and blocks forever on keys it cannot get.
# - Measured OPENABLE under script(1), under screen(1), and in all four redirected shapes.
# - CLOSED only with no ctty, where `: < /dev/tty` fails ENXIO as `device not configured`.
_hop_tty_ok() {
	{ : < /dev/tty } 2>/dev/null
}

# _hop_pick_headless <targets> <query> <label> -> resolve with no terminal, or explain and fail.
# - --filter is the one fzf mode needing no terminal, and it honours --accept-nth.
# - So a single match arrives in the very same dir<TAB>preview shape _hop_parse_result already reads.
# - EXACTLY ONE match is dispatched as plain Enter, which is what --select-1 does today.
# - That keeps `hop <unique-query>` working from a script, and preserving it is why this is a separate path.
# - A guard in FRONT of the picker runs before uniqueness is known, so it would refuse that working case.
# - The real rule is "exactly one match", not "a query was given", which is a genuine distinction.
# - A ONE-ROW target list with an EMPTY query also auto-accepts today, and counting matches covers both.
# - Zero or many cannot be resolved without a human, so both name the cause AND the count.
# - A bare `no match` would be a lie when 37 rows matched, and the count is what ends the bug hunt.
# - Nothing matched and N matched get DIFFERENT messages, because the next move differs.
# - A typo wants correcting; a broad query wants narrowing, and one string cannot say both.
# - --filter ignores exactly one flag _hop_pick passes, which is --disabled.
# - _hop_pick adds --disabled ONLY for an empty query, where every row matches either way.
# - So that discrepancy is unreachable rather than merely unobserved, and needs no handling here.
# - The match-affecting flags come from _HOP_MATCHER_FLAGS, which lib/ui.zsh defines and this file sources.
# - --filter is a separate fzf process, so it has to match rows exactly the way the picker would.
# - They were restated here, under a comment asking you to keep two copies in step by hand.
# - Sharing the array makes that structural instead: there is no second list left to forget.
# - tests/suite_nottty.zsh pins the array's value and fails if either caller hardcodes a flag again.
# - fzf's stderr is NOT suppressed, because --filter still parses every option it is handed.
# - A genuine complaint about one of these flags has to reach the user, not look like an empty result.
_hop_pick_headless() {
	emulate -L zsh
	local targets=$1 query=${2:-} label=$3
	local out
	out=$(print -r -- "$targets" | fzf --filter="$query" "${_HOP_MATCHER_FLAGS[@]}")
	local -a rows=("${(@f)out}")
	rows=(${rows:#})
	_hop_dbg "headless label=${label} rows=${#rows} query=${query}"

	if (( $#rows == 1 )); then
		local dir preview
		IFS=$'\t' read -r dir preview <<< "${rows[1]}"
		[[ -n $preview ]] || preview=$dir
		# An empty key is plain Enter, the only verb allowed to cd; see _hop_dispatch.
		_hop_dispatch '' "$dir" "$preview"
		return $?
	fi

	print -ru2 -- 'hop: no terminal available, so the picker cannot run (/dev/tty could not be opened).'
	if (( $#rows == 0 )); then
		print -ru2 -- "hop: nothing matched${query:+ the query: $query}, so there was nothing to jump to."
	else
		print -ru2 -- "hop: ${#rows} targets matched${query:+ the query: $query}, and picking one needs a terminal."
		print -ru2 -- 'hop: narrow the query until exactly one target matches and hop will jump straight to it.'
	fi
	return 1
}

# _hop_run <label> <query> <reload> <targets> [root] [restore]
# - fzf's status is read by _hop_fzf_status, which this shares with _hop_ws_picker.
# - _hop_key/_hop_dir/_hop_preview are local here so nothing leaks into the interactive shell.
# - root is passed through only so the modal `:` kind picker can re-enumerate; '' disables it.
_hop_run() {
	emulate -L zsh
	local label=$1 query=$2 reload=$3 targets=$4 root=${5:-} restore=${6:-} up=${7:-}
	local _hop_key _hop_dir _hop_preview _hop_st
	local header out st
	local -a trows=("${(f)targets}")
	header=$(_hop_header "$reload")
	# No terminal means the picker would block forever, so resolve headlessly instead of opening it.
	if ! _hop_tty_ok; then
		_hop_pick_headless "$targets" "$query" "$label"
		return $?
	fi
	out=$(print -r -- "$targets" | _hop_pick "$label" "$header" "$query" "$reload" "$root" '' "$restore" "$up")
	st=$?
	_hop_fzf_status "$st" "$label" "${#trows}" "$query" || return $_hop_st
	_hop_parse_result "$out" || return 0

	# ctrl-h/h goes UP a level, so the caller names the picker one step out.
	if [[ $_hop_key == ctrl-h && -n $up ]]; then
		"$up"
		return $?
	fi
	_hop_dispatch "$_hop_key" "$_hop_dir" "$_hop_preview"
}

# _hop_ws_picker [query] -> the WORKSPACE level: enter cds there, ctrl-l or l shows its repos.
# - Answers "just nav to the workspace, or show its repos" without forcing the choice up front.
# - Drilling scopes $HOP_REPOS to the chosen workspace, so the repo picker needs no new argument.
_hop_ws_picker() {
	emulate -L zsh
	local query=${1:-} targets out st
	local _hop_key _hop_dir _hop_preview _hop_st
	targets=$(_hop_provider_ws)
	if [[ -z $targets ]]; then
		print -ru2 -- "hop: no workspaces configured (edit ${HOP_WORKSPACES_FILE})"
		return 1
	fi

	local -a rows=("${(f)targets}")
	local label="workspaces  ${#rows}"
	# Same headless resolve as _hop_run: this picker is a second entry point, not a special case.
	if ! _hop_tty_ok; then
		_hop_pick_headless "$targets" "$query" "$label"
		return $?
	fi
	out=$(print -r -- "$targets" | _hop_pick "$label" "$(_hop_header)" "$query" '' '' drill)
	st=$?
	_hop_fzf_status "$st" "$label" "${#rows}" "$query" || return $_hop_st
	_hop_parse_result "$out" || return 0

	if [[ $_hop_key == ctrl-l ]]; then
		local HOP_REPOS=$_hop_dir
		_hop_repo_picker
		return $?
	fi
	_hop_dispatch "$_hop_key" "$_hop_dir" "$_hop_preview"
}

# hopw -> cd to the workspace containing $PWD, longest prefix first.
# - Two configured workspaces can nest, e.g. ~/work and ~/work/code, so shortest match would be wrong.
hopw() {
	emulate -L zsh
	local REPLY
	if _hop_ws_for "$PWD"; then
		_hop_act_cd "$REPLY"
		return $?
	fi
	print -ru2 -- "hop: ${PWD} is not inside any configured workspace"
	return 1
}

# Testing _hop_repos' status rather than its output is what makes the zero-repos error reachable.
_hop_repo_picker() {
	emulate -L zsh
	local query=${1:-} out
	local -a repos
	if out=$(_hop_repos); then
		repos=("${(@f)out}")
		repos=(${repos:#})
	fi
	if (( $#repos == 0 )); then
		print -ru2 -- 'hop: not in a git repository, and no repos found (set $HOP_REPOS)'
		return 1
	fi
	local targets
	targets=$(_hop_provider_repo "${repos[@]}")
	if [[ -z $targets ]]; then
		print -ru2 -- 'hop: no readable repos in $HOP_REPOS'
		return 1
	fi
	_hop_run "repos  ${#repos} found" "$query" '' "$targets" '' '' _hop_ws_picker
}

hop() {
	emulate -L zsh
	setopt local_options no_nomatch
	# emulate -L zsh localises options and traps but NOT IFS, and ${=...} below splits on IFS.
	local IFS=$' \t\n\0'

	local -a kinds words
	local all=0 repopick=0 wspick=0 here=0 opts=0 mode=''
	kinds=(${=${HOP_DEFAULT_KINDS//,/ }})

	# --no-vim shadows the global for this call only, which is what _hop_vim_on reads.
	# - Someone with years of fzf muscle memory needs a way out, and it is also a clean A/B.
	local HOP_VIM=${HOP_VIM:-1}

	while (( $# )); do
		case $1 in
			-h | --help)
				_hop_usage
				return 0
				;;
			-V | --version)
				_hop_version
				return 0
				;;
			-a | --all)
				all=1
				opts=1
				shift
				;;
			-R | --repos)
				repopick=1
				opts=1
				shift
				;;
			-w | --workspaces)
				wspick=1
				opts=1
				shift
				;;
			-c | --cwd | --here)
				here=1
				opts=1
				shift
				;;
			--no-vim)
				HOP_VIM=0
				opts=1
				shift
				;;
			--vim)
				HOP_VIM=1
				opts=1
				shift
				;;
			--doctor=short)
				_hop_doctor_short
				return $?
				;;
			--doctor=*)
				print -ru2 -- "hop: ${1}: unknown --doctor mode, want: --doctor=short"
				return 2
				;;
			--doctor)
				if [[ ${2:-} == short ]]; then
					_hop_doctor_short
					return $?
				fi
				_hop_doctor
				return $?
				;;
			upgrade)
				# Only the FIRST word is the verb, so a target named upgrade still searches.
				if (( $#words || opts )); then
					words+=("$1")
					shift
					continue
				fi
				shift
				_hop_upgrade "$@"
				return $?
				;;
			-k | --kinds)
				if (( $# < 2 )); then
					print -ru2 -- 'hop: -k needs a comma-separated kind list'
					return 2
				fi
				kinds=(${=${2//,/ }})
				opts=1
				shift 2
				;;
			-k*)
				kinds=(${=${${1#-k}//,/ }})
				opts=1
				shift
				;;
			/ | -)
				mode=$1
				shift
				# Silently dropping the rest would cd somewhere the user did not ask for.
				if (( $# || $#words || opts )); then
					print -ru2 -- "hop: ${mode} takes no other arguments"
					return 2
				fi
				break
				;;
			--)
				shift
				words+=("$@")
				break
				;;
			-*)
				print -ru2 -- "hop: unknown option: $1"
				return 2
				;;
			*)
				words+=("$1")
				shift
				;;
		esac
	done

	if [[ $mode == '-' ]]; then
		cd -
		return $?
	fi

	local root
	root=$(git rev-parse --show-toplevel 2>/dev/null)

	if [[ $mode == '/' ]]; then
		if [[ -z $root ]]; then
			print -ru2 -- 'hop: not in a git repository'
			return 1
		fi
		_hop_act_cd "$root"
		return $?
	fi

	if (( ! ${+commands[fzf]} )); then
		print -ru2 -- 'hop: fzf is not installed'
		return 1
	fi
	# A too-old fzf otherwise fails as a bare `unknown option`, which names no cause and no fix.
	_hop_fzf_ok || return 1

	local query="${(j: :)words}"

	if (( wspick )); then
		_hop_ws_picker "$query"
		return $?
	fi

	# Outside a repo the workspace level is strictly more useful, but only if one is configured.
	if (( repopick )) || [[ -z $root ]]; then
		if [[ -z $root ]] && (( ! repopick )) && _hop_ws_parse; then
			_hop_ws_picker "$query"
			return $?
		fi
		_hop_repo_picker "$query"
		return $?
	fi

	(( all )) && kinds=("${_HOP_ALL_KINDS[@]}")
	kinds=("${(@u)kinds}")
	if (( $#kinds == 0 )); then
		print -ru2 -- 'hop: no kinds selected'
		return 2
	fi

	local targets
	targets=$(_hop_generate "$root" "${kinds[@]}")
	if [[ -z $targets ]]; then
		print -ru2 -- "hop: no targets in ${root} for kinds: ${(j:,:)kinds}"
		return 1
	fi

	# -c narrows every kind to the subtree you are standing in, not just the file kind.
	# - Enumeration still starts at the repo root, because a kind's bases are repo-root relative.
	# - Filtering the rows afterwards is what makes one flag work identically for all kinds.
	# - $PWD is LOGICAL while the rows are built from git's PHYSICAL root, so both sides resolve first.
	# - Unresolved, every row was dropped in any repo under macOS /tmp or a symlinked parent.
	# - _hop_act_browse fixed this same class with ${1:A}, and its comment names the /tmp case.
	# - Filtering in zsh rather than awk, because `awk -v` escape-processes the value it is handed.
	# - So a directory whose name contains a backslash silently matched nothing at all.
	if (( here )); then
		local hdir=${PWD:A} hroot=${root:A}
		if [[ $hdir != "$hroot" ]]; then
			local -a kept=()
			local row rdir
			for row in "${(@f)targets}"; do
				[[ -n $row ]] || continue
				# Field 2 is the absolute dir, read exactly as _hop_rank reads it.
				rdir=${${row#*$'\t'}%$'\t'*}
				[[ $rdir == "$hdir" || $rdir == "$hdir"/* ]] && kept+=("$row")
			done
			targets=${(F)kept}
			if [[ -z $targets ]]; then
				print -ru2 -- "hop: no targets under ${PWD} for kinds: ${(j:,:)kinds}"
				return 1
			fi
		fi
	fi

	local -a rows=("${(f)targets}")
	targets=$(_hop_rank "$targets")

	# alt-a always reloads with every registered kind, which is the whole point of the binding.
	local -a rkinds=("${_HOP_ALL_KINDS[@]}")
	local reload
	reload=$(_hop_reload_cmd "$root" "${rkinds[@]}")

	# restore is what esc out of the `:` view menu regenerates, so cancelling loses nothing.
	local restore
	restore=$(_hop_reload_cmd "$root" "${kinds[@]}")

	_hop_run "${root:t}  ${#rows} targets  ${(j:,:)kinds}" "$query" "$reload" "$targets" "$root" "$restore" _hop_repo_picker
}

hopr() {
	emulate -L zsh
	local root
	root=$(git rev-parse --show-toplevel 2>/dev/null)
	if [[ -z $root ]]; then
		print -ru2 -- 'hop: not in a git repository'
		return 1
	fi
	_hop_act_cd "$root"
}

# ^G launches hop without discarding a half-typed command line, which the buffer keeps for free.
# - A non-zero return would ring the bell on a no-match, so the widget always reports success.
# - alt-g is bound too, because ^G otherwise costs you zsh's send-break.
_hop_widget() {
	emulate -L zsh
	hop
	zle reset-prompt
	return 0
}

if [[ -o interactive ]]; then
	zle -N hop-widget _hop_widget
	bindkey '^G' hop-widget
	bindkey '^[g' hop-widget
fi
