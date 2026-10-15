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
source "$HOP_HOME/lib/match.zsh"
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
	local REPLY
	_hop_enter_mode
	local enter=$REPLY
	print -r -- 'usage: hop [-a|--all] [-k KIND[,KIND...]] [-c] [-R|-w] [-p] [[--cd] [-o|-e] | --action=MODE] [--no-vim] [-h] [/|-] [words...]'
	print -r -- ''
	print -r -- '  hop                 pick from the default kinds, starting in NORMAL mode'
	print -r -- '  hop vpc prod        a clear match jumps with no UI; otherwise the picker opens best-first'
	print -r -- '  hop terraform/x     a path that exists jumps straight there, before any matching;'
	print -r -- '                      outside its repo, hop looks for it in your repos and workspaces'
	print -r -- '  hop -p, --pick      always open the picker, even for a clear match (HOP_JUMP=never)'
	print -r -- '  hop -o, --open      Enter opens the target in VS Code instead of cd-ing'
	print -r -- '  hop -e, --reveal    Enter shows the target in the VS Code explorer instead of cd-ing'
	print -r -- '  hop --cd -o         Enter cds, then opens; --cd -e cds, then reveals'
	print -r -- '  hop --action=MODE   Enter does MODE: cd, open, reveal, cd+open, cd+reveal (HOP_ACTION)'
	print -r -- '  hop -a, --all       include every registered kind, not just the defaults'
	print -r -- '  hop -k tg,helm      restrict to specific kinds'
	print -r -- '  hop -c, --cwd       only targets under $PWD, for any kind'
	print -r -- '  hop -k file x.yml   find a tracked FILE by name (opt-in: it is every file)'
	print -r -- '  hop file x.yml      the same: a first word naming a kind outside the defaults is -k,'
	print -r -- '                      when it has targets here and no default target holds the word'
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
	print -r -- '  hop -V, -v, --version  print the version loaded, and installed when it differs'
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
	print -r -- "  NORMAL: j/k move | g/G first/last | ^d/^u half page | enter ${enter} | c cd"
	print -r -- '          o code file | O code dir | e $EDITOR file | y/Y copy dir/file'
	print -r -- '          b gh browse | p preview | r refresh | ? help | q quit'
	print -r -- '          l drill in | h back out | / SEARCH | : switch view'
	print -r -- '          esc clears the query, or quits when it is empty'
	print -r -- ''
	print -r -- '  : opens the view menu in place; enter switches, esc goes back.'
	print -r -- ''
	print -r -- "  SEARCH: every key types | esc NORMAL, query kept | enter ${enter} | alt-enter cd"
	print -r -- '          ctrl-o code -r file | ctrl-t code -n dir'
	print -r -- '          ctrl-y copy dir | alt-y copy file | alt-o $EDITOR file'
	print -r -- '          alt-B gh browse | alt-a all kinds | ctrl-r refresh preview'
	print -r -- '          alt-p or ctrl-/ toggle preview'
	print -r -- ''
	print -r -- '  ^G and alt-g launch hop from a half-typed command line.'
	print -r -- '  ^G replaces zsh send-break; use ^C to abandon a line, or rebind hop-widget.'
	print -r -- '  A repo-root .hoprc is OPT-IN: it runs code, so set HOP_HOPRC=1 to allow it.'
}

# _hop_version_disk -> REPLY is what $HOP_HOME/VERSION says right now, or 'unknown' without one.
# - A zsh builtin `read`, never `cat`, because this also runs while hop.zsh is being sourced.
_hop_version_disk() {
	emulate -L zsh
	local line=''
	[[ -r $HOP_HOME/VERSION ]] && read -r line < "$HOP_HOME/VERSION"
	REPLY=${line:-unknown}
	return 0
}

# The version this shell actually loaded, because `hop upgrade` moves VERSION on disk under it.
# - Before this, a shell still running 0.2.0's functions printed 0.3.0 for --version.
() {
	emulate -L zsh
	local REPLY
	_hop_version_disk
	typeset -g _HOP_LOADED_VERSION=$REPLY
}

# _hop_version -> print "hop X.Y.Z", plus "(describe)" when this install is a git checkout.
# - When the shell loaded a different VERSION than is on disk now, it says both and how to reload.
# - Works with VERSION missing (falls back to 'unknown') and with git missing (drops the suffix).
_hop_version() {
	emulate -L zsh
	local REPLY desc
	_hop_version_disk
	desc=$(git -C "$HOP_HOME" describe --tags --always --dirty 2>/dev/null)
	if [[ $REPLY != "$_HOP_LOADED_VERSION" ]]; then
		print -r -- "hop ${_HOP_LOADED_VERSION} loaded, ${REPLY} installed${desc:+ (${desc})}: run 'exec zsh' to load it"
		return 0
	fi
	print -r -- "hop ${REPLY}${desc:+ (${desc})}"
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
# - Only the rows whose dir is in the history are keyed and sorted; the rest keep input order untouched.
# - Field 2 comes from _hop_dirs_of in one pass rather than one extraction per row; _hop_dirs_of has the cost.
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

	local -a rows=("${(@f)targets}") reply
	_hop_dirs_of "${rows[@]}"
	local -a dirs=("${reply[@]}")
	# Most history entries name no row at all, often dirs that no longer exist, and then nothing moves.
	local -a present=("${(@u)hist:*dirs}")
	if (( $#present == 0 )); then
		print -r -- "$targets"
		return 0
	fi

	local -A rank
	local -i i n=0
	local h
	for h in "${hist[@]}"; do
		(( ${+rank[$h]} )) || rank[$h]=$(( ++n ))
	done

	local -a front keyed rest
	for (( i = 1; i <= $#rows; i++ )); do
		if (( ${+rank[${dirs[i]}]} )); then
			keyed+=("${(l:6::0:)rank[${dirs[i]}]}${(l:6::0:)i}")
		else
			rest+=("${rows[i]}")
		fi
	done
	local k
	for k in "${(@o)keyed}"; do
		front+=("${rows[${k:6}]}")
	done
	print -rl -- "${front[@]}" "${rest[@]}"
}

# _hop_filter_under <dir> <row...> -> reply is the rows whose dir is <dir> or lies beneath it.
# - Field 2 is the absolute dir, read in one pass by _hop_dirs_of, exactly as _hop_rank reads it.
# - The "$dir"/* arm needs the slash, so standing in /a/b never keeps a sibling /a/bc.
_hop_filter_under() {
	emulate -L zsh
	local under=$1
	shift
	local -a rows=("$@")
	_hop_dirs_of "${rows[@]}"
	local -a dirs=("${reply[@]}") kept
	local -i i
	for (( i = 1; i <= $#rows; i++ )); do
		[[ ${dirs[i]} == "$under" || ${dirs[i]} == "$under"/* ]] && kept+=("${rows[i]}")
	done
	reply=("${kept[@]}")
}

# _hop_fzf_status <status> <label> <rows> [query] -> 0 to use fzf's output, non-zero to stop.
# - The only place fzf's exit status is interpreted, and EVERY picker has to route through it.
# - 130 is a user cancel and must stay silent, so "stop" and "failed" are not the same answer.
# - _hop_st is the status the CALLER returns when this says stop, since cancel stops but succeeds.
# - The caller declares it `local`, exactly as _hop_run does for _hop_parse_result's fields.
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

# _hop_res_pick <label> <header> <query> <targets> <reload> <root> <drill> <restore> <up> -> act on a resolve.
# - The caller has run _hop_resolve, terminal or not, so a clear match jumps with no picker drawn at all.
# - 0 means the picker returned a row in _hop_key/_hop_dir/_hop_preview/_hop_rel, for the caller to dispatch.
# - 1 means the call is over, and _hop_st is what the caller returns: a jump, a headless report or a cancel.
# - A resolver PICK opens in ordered mode, best rows first, and never with --select-1.
# - So one approximate candidate cannot auto-accept; only an empty query keeps today's one-row accept.
_hop_res_pick() {
	emulate -L zsh
	local label=$1 header=$2 query=$3 targets=$4 reload=$5 root=$6 drill=$7 restore=$8 up=$9
	if [[ $_hop_res_verdict == jump ]]; then
		_hop_res_jump
		_hop_st=$?
		return 1
	fi
	# No terminal means the picker would block forever, so the resolve is reported instead.
	if ! _hop_tty_ok; then
		_hop_headless_report "$query" "$label"
		_hop_st=$?
		return 1
	fi
	local _hop_pick_ordered=0 _hop_pick_select1=0 _hop_pick_note=$_hop_res_note
	local input=$targets out
	local -i st
	case $_hop_res_verdict in
		pick)
			_hop_pick_ordered=1
			input=$(_hop_res_input "$targets")
			;;
		empty)
			# A kind read from the first word names a family, not a target, so even its one row waits for Enter.
			[[ ${_hop_jump:-$HOP_JUMP} != never && -z ${_hop_kword:-} ]] && _hop_pick_select1=1
			;;
	esac
	local -a trows=("${(f)targets}")
	out=$(print -r -- "$input" | _hop_pick "$label" "$header" "$_hop_res_query" "$reload" "$root" "$drill" "$restore" "$up")
	st=$?
	_hop_fzf_status "$st" "$label" "${#trows}" "$query" || return 1
	if ! _hop_parse_result "$out"; then
		_hop_st=0
		return 1
	fi
	return 0
}

# _hop_run <label> <query> <reload> <targets> [root] [restore] [up]
# - fzf's status is read by _hop_fzf_status, which this shares with _hop_ws_picker.
# - _hop_key/_hop_dir/_hop_preview/_hop_rel are local here so nothing leaks into the interactive shell.
# - So are the resolver's fields, which _hop_resolve writes by name.
# - Unless the caller set _hop_res_ready, which means it already resolved these targets into its own fields.
# - root is passed through only so the modal `:` kind picker can re-enumerate; '' disables it.
_hop_run() {
	emulate -L zsh
	local label=$1 query=$2 reload=$3 targets=$4 root=${5:-} restore=${6:-} up=${7:-}
	local _hop_key _hop_dir _hop_preview _hop_rel _hop_st
	# Read by _hop_row, so the ancestor rows the resolver injects line up with these.
	local _hop_row_like=${targets%%$'\n'*}
	local -i pre=${_hop_res_ready:-0}
	# Shadowed, so a picker reached from this one through ctrl-h resolves for itself.
	local -i _hop_res_ready=0
	if (( ! pre )); then
		local _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
		local -i _hop_res_n _hop_res_m _hop_res_inj
		local -a _hop_res_rows
		_hop_resolve "$query" "$targets" "$root" "${_hop_mode:-cd}" "${_hop_jump:-$HOP_JUMP}" "${_hop_under:-}"
	fi
	# A path this repo has nothing close to may be another repo's, and only then is anything outside it tried.
	if [[ $_hop_res_verdict == none && -n $root ]] && (( ${_hop_xrepo:-0} )) && _hop_elsewhere "$query" "$root"; then
		return $_hop_st
	fi
	_hop_res_pick "$label" "$(_hop_header "$reload")" "$query" "$targets" "$reload" "$root" '' "$restore" "$up" \
		|| return $_hop_st

	# ctrl-h/h goes UP a level, so the caller names the picker one step out.
	if [[ $_hop_key == ctrl-h && -n $up ]]; then
		"$up"
		return $?
	fi
	_hop_dispatch "$_hop_key" "$_hop_dir" "$_hop_preview" "$_hop_rel"
}

# _hop_ws_picker [query] [fallback] -> the WORKSPACE level: enter goes there, ctrl-l or l shows its repos.
# - Answers "just nav to the workspace, or show its repos" without forcing the choice up front.
# - Drilling scopes $HOP_REPOS to the chosen workspace, so the repo picker needs no new argument.
# - fallback is set only when hop chose this level itself, outside a repo, rather than by -w.
# - Then a query no workspace answers exactly is tried against the repos too, and the closer tier wins.
# - So `hop configuration` from ~ finds the repo, and `hop tf eks` is not a workspace pick that ignored eks.
# - A tie goes to the workspaces, which is the level hop chose.
_hop_ws_picker() {
	emulate -L zsh
	local query=${1:-} fallback=${2:-} targets
	local _hop_key _hop_dir _hop_preview _hop_rel _hop_st
	# Read by _hop_act_enter: a workspace row names a whole folder, so open and reveal both mean `code -n` on it.
	local -i _hop_folder_rows=1
	local _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
	local -i _hop_res_n _hop_res_m _hop_res_inj
	local -a _hop_res_rows
	targets=$(_hop_provider_ws)
	if [[ -z $targets ]]; then
		print -ru2 -- "hop: no workspaces configured (edit ${HOP_WORKSPACES_FILE})"
		return 1
	fi

	local -a rows=("${(f)targets}")
	local label="workspaces  ${#rows}"
	_hop_resolve "$query" "$targets" '' "${_hop_mode:-cd}" "${_hop_jump:-$HOP_JUMP}"
	if [[ -n $fallback && $_hop_res_verdict != (jump|empty) && $_hop_res_tier != T1 ]]; then
		local REPLY
		local -a reply
		_hop_res_rank
		local -i wsrank=$REPLY
		if _hop_repo_targets; then
			local repos=$REPLY
			local -i nrepos=$#reply
			_hop_resolve "$query" "$repos" '' "${_hop_mode:-cd}" "${_hop_jump:-$HOP_JUMP}"
			_hop_res_rank
			if (( REPLY > wsrank )); then
				local -i _hop_res_ready=1
				_hop_repo_picker "$query" "$repos" "$nrepos"
				return $?
			fi
			_hop_resolve "$query" "$targets" '' "${_hop_mode:-cd}" "${_hop_jump:-$HOP_JUMP}"
		fi
	fi
	_hop_res_pick "$label" "$(_hop_header)" "$query" "$targets" '' '' drill '' '' || return $_hop_st

	if [[ $_hop_key == ctrl-l ]]; then
		local HOP_REPOS=$_hop_dir
		_hop_repo_picker
		return $?
	fi
	_hop_dispatch "$_hop_key" "$_hop_dir" "$_hop_preview" "$_hop_rel"
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

# _hop_repo_targets -> 0 with REPLY the repo rows and reply the repo dirs.
# - 1 when no repo is configured or found, and 2 when none of them is readable, so each gets its own message.
# - Testing _hop_repos' status rather than its output is what makes the zero-repos error reachable.
_hop_repo_targets() {
	emulate -L zsh
	local out
	reply=()
	REPLY=''
	if out=$(_hop_repos); then
		reply=("${(@f)out}")
		reply=(${reply:#})
	fi
	(( $#reply )) || return 1
	REPLY=$(_hop_provider_repo "${reply[@]}")
	[[ -n $REPLY ]] || return 2
}

# _hop_repo_picker [query] [rows] [count] -> the REPO level; rows and count come from a caller that already built them.
_hop_repo_picker() {
	emulate -L zsh
	local query=${1:-} REPLY=${2:-}
	# A repo row names a whole folder too, exactly as a workspace row does in _hop_ws_picker.
	local -i _hop_folder_rows=1 n=${3:-0}
	local -a reply
	if [[ -z $REPLY ]]; then
		_hop_repo_targets
		case $? in
			1)
				print -ru2 -- 'hop: not in a git repository, and no repos found (set $HOP_REPOS)'
				return 1
				;;
			2)
				print -ru2 -- 'hop: no readable repos in $HOP_REPOS'
				return 1
				;;
		esac
		n=$#reply
	fi
	_hop_run "repos  ${n} found" "$query" '' "$REPLY" '' '' _hop_ws_picker
}

hop() {
	emulate -L zsh
	setopt local_options no_nomatch
	# emulate -L zsh localises options and traps but NOT IFS, and ${=...} below splits on IFS.
	local IFS=$' \t\n\0'

	local -a kinds words
	local all=0 repopick=0 wspick=0 here=0 opts=0 kgiven=0 mode=''
	local -i act_cd=0 act_open=0 act_reveal=0
	local act_flag=''
	# Read by the resolver, the pickers, the legends and _hop_act_enter through dynamic scope.
	# - So no signature has to carry them, and none of them outlives this call.
	local _hop_jump='' _hop_under='' _hop_mode='' _hop_st
	local -i _hop_xrepo=0
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
			-V | -v | --version)
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
			-p | --pick)
				_hop_jump=never
				opts=1
				shift
				;;
			--cd)
				act_cd=1
				opts=1
				shift
				;;
			-o | --open)
				act_open=1
				opts=1
				shift
				;;
			-e | --reveal)
				act_reveal=1
				opts=1
				shift
				;;
			# An empty --action= is refused too, or a `--action=$MODE` with MODE unset silently did what HOP_ACTION says.
			--action | --action=)
				print -ru2 -- "hop: --action needs a mode, as --action=MODE: ${(j:, :)_HOP_ACTIONS}"
				return 2
				;;
			--action=*)
				act_flag=${1#--action=}
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
				opts=1 kgiven=1
				shift 2
				;;
			-k*)
				kinds=(${=${${1#-k}//,/ }})
				opts=1 kgiven=1
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

	# The flags replace HOP_ACTION for this call, so two that disagree are refused rather than one picked.
	if (( act_open && act_reveal )); then
		print -ru2 -- 'hop: -o and -e are exclusive'
		return 2
	fi
	if [[ -n $act_flag ]]; then
		if (( act_cd || act_open || act_reveal )); then
			print -ru2 -- 'hop: --action=MODE cannot be combined with --cd, -o or -e'
			return 2
		fi
		if (( ! ${_HOP_ACTIONS[(Ie)$act_flag]} )); then
			print -ru2 -- "hop: --action=${act_flag} is not one of ${(j:, :)_HOP_ACTIONS}"
			return 2
		fi
	fi

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

	# Resolved after `hop /` and `hop -`, which are navigation by name and stay a pure cd.
	if [[ -n $act_flag ]]; then
		_hop_mode=$act_flag
	elif (( act_open )); then
		_hop_mode=open
	elif (( act_reveal )); then
		_hop_mode=reveal
	fi
	if (( act_cd )); then
		_hop_mode=cd${_hop_mode:++${_hop_mode}}
	elif [[ -z $_hop_mode ]]; then
		local REPLY
		_hop_action_mode "${HOP_ACTION:-cd}"
		_hop_mode=$REPLY
	fi

	if [[ -z $_hop_jump ]]; then
		_hop_jump=${HOP_JUMP:-auto}
		if [[ $_hop_jump != (auto|unique|never) ]]; then
			print -ru2 -- "hop: HOP_JUMP=${_hop_jump} is not one of auto, unique, never; using auto"
			_hop_jump=auto
		fi
	fi

	# -c narrows every kind to the subtree you are standing in, not just the file kind.
	# - Enumeration still starts at the repo root, because a kind's bases are repo-root relative.
	# - Filtering the rows afterwards, in _hop_rows, is what makes one flag work identically for all kinds.
	# - $PWD is LOGICAL while the rows are built from git's PHYSICAL root, so both sides resolve first.
	# - Unresolved, every row was dropped in any repo under macOS /tmp or a symlinked parent.
	# - _hop_act_browse fixed this same class with ${1:A}, and its comment names the /tmp case.
	# - Filtering in zsh rather than awk, because `awk -v` escape-processes the value it is handed.
	# - So a directory whose name contains a backslash silently matched nothing at all.
	if (( here )) && [[ -n $root ]]; then
		local hdir=${PWD:A} hroot=${root:A}
		[[ $hdir != "$hroot" ]] && _hop_under=$hdir
	fi

	# A first word naming a kind outside the active set, which no row here holds as a whole word, is that kind.
	# - So `hop file x` is `hop -k file x`, while tg vpc, a dir named puppet, and every later word stay plain words.
	# - It runs before T0, so the rest of the query is what T0 and the resolver see, exactly as after a typed -k.
	# - In a repo the word is a kind only when that kind has rows here, and both lists are kept for the resolve below.
	# - Outside a repo no kind is listed, so it is read only before a path, which it frees for T0 and the other repos.
	# - -w and -R list no kinds at all, so there it is always a plain word.
	local _hop_kword='' pre=''
	local -i pre_st=-1
	local w1=${(L)words[1]-}
	if (( ! kgiven && ! all && ! wspick && ! repopick && $#words && ${+commands[fzf]} )) && (( ${_HOP_ALL_KINDS[(Ie)$w1]} && ! ${kinds[(Ie)$w1]} )); then
		if [[ -z $root ]]; then
			(( $#words == 2 )) && [[ ${words[2]} == */* || ${words[2]} == '~'* || ${words[2]} == (.|..) ]] && _hop_kword=$w1
		else
			_hop_dbg "generate root=${root} kinds=${(j:,:)${(@u)kinds}}"
			pre=$(_hop_rows "$root" "$_hop_under" "${(@u)kinds}")
			pre_st=$?
			if _hop_word_unread "${words[1]}" "$pre"; then
				local krows
				_hop_dbg "generate root=${root} kinds=${w1}"
				if krows=$(_hop_rows "$root" "$_hop_under" "$w1") && [[ -n $krows ]]; then
					_hop_kword=$w1 pre=$krows pre_st=0
				fi
			fi
		fi
		if [[ -n $_hop_kword ]]; then
			print -ru2 -- "hop: reading \"${words[1]}\" as -k ${w1}"
			kinds=("$w1") words=("${(@)words[2,-1]}")
		fi
	fi

	# T0: a typed path is a filesystem fact, so it jumps before fzf or any enumeration is paid for.
	# - -k does not narrow it, because no kind is consulted; -w and -R name a different level, so they skip it.
	if (( ! wspick && ! repopick && $#words == 1 )); then
		if [[ $_hop_jump != never ]]; then
			local -a reply
			local -F t0=0
			[[ -n ${HOP_DEBUG:-} ]] && zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null && t0=$EPOCHREALTIME
			if _hop_literal_target "${words[1]}" "$root"; then
				local ms=-
				(( t0 > 0 )) && printf -v ms '%.1f' $(( (EPOCHREALTIME - t0) * 1000 ))
				_hop_dbg "resolve tier=T0 rule=path verdict=jump n=1 inj=0 q=${words[1]} target=${reply[3]} ms=${ms}"
				_hop_dispatch '' "${reply[1]}" "${reply[2]}" "${reply[3]}"
				return $?
			fi
		fi
		# _hop_xrepo arms _hop_elsewhere, which runs below outside a repo and from _hop_run inside one.
		# - Never under -c, which keeps every search under $PWD.
		# - Armed under -p and HOP_JUMP=never too, where it opens a picker over what it finds instead of jumping.
		(( here )) || _hop_xrepo=1
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
		if [[ -z $root ]] && (( _hop_xrepo )) && _hop_elsewhere "$query" ''; then
			return $_hop_st
		fi
		if [[ -z $root ]] && (( ! repopick )) && _hop_ws_parse; then
			_hop_ws_picker "$query" fallback
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
	local -i st
	if (( pre_st >= 0 )); then
		targets=$pre st=$pre_st
	else
		_hop_dbg "generate root=${root} kinds=${(j:,:)kinds}"
		targets=$(_hop_rows "$root" "$_hop_under" "${kinds[@]}")
		st=$?
	fi
	if (( st == 2 )); then
		print -ru2 -- "hop: no targets under ${PWD} for kinds: ${(j:,:)kinds}"
		return 1
	fi
	if (( st )) || [[ -z $targets ]]; then
		# T0 lists no kind, so a path in another repo is found even when these kinds list nothing here.
		if (( _hop_xrepo )) && _hop_elsewhere "$query" "$root"; then
			return $_hop_st
		fi
		print -ru2 -- "hop: no targets in ${root} for kinds: ${(j:,:)kinds}"
		return 1
	fi
	local -a rows=("${(f)targets}")

	# alt-a always reloads with every registered kind, which is the whole point of the binding.
	# - Both reloads carry the -c dir, so a reload narrows exactly as the list it replaces did.
	local -a rkinds=("${_HOP_ALL_KINDS[@]}")
	local reload
	reload=$(_hop_reload_cmd "$root" "$_hop_under" "${rkinds[@]}")

	# restore is what esc out of the `:` view menu regenerates, so cancelling loses nothing.
	local restore
	restore=$(_hop_reload_cmd "$root" "$_hop_under" "${kinds[@]}")

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
