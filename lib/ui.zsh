#!/usr/bin/env zsh
# hop UI: the single fzf call, plus the parser for what it returns.

# _hop_header [has-reload] -> the keys legend, as three short lines.
# - fzf renders embedded newlines as separate header rows but never wraps a long one.
# - The header lives in the list pane, so one 83-column line was clipped to 32 at 80 columns.
# - Each line is <= 35 columns, which survives a 36-column pane.
# - M-a is omitted when nothing is bound to it, so the picker cannot advertise a dead key.
# - This is the non-modal legend, used when HOP_VIM=0 or --no-vim turns the modal layer off.
_hop_header() {
	emulate -L zsh
	local -a lines=(
		'enter cd · ^O file · ^T folder'
		'^Y copy · M-y copy file · M-o edit'
	)
	if [[ -n ${1:-} ]]; then
		lines+=('^G github · M-a +conf · M-p preview')
	else
		lines+=('^G github · M-p preview')
	fi
	print -rn -- "${(pj:\n:)lines}"
}

# Every key the modal layer owns, which is every printable ASCII key plus two page keys.
# - fzf's --disabled and disable-search stop FILTERING only, never keystroke insertion.
# - So search-off alone is not a normal mode; `ignore` is the action that makes one real.
# - SEARCH mode is then one `unbind` of this whole list, which restores plain self-insert.
# - Esc back to NORMAL is one `rebind` of the same list, which is probed to round-trip.
# - ( and ) are absent because fzf balances parens inside unbind(...) and would split the list.
# - They get their own single-key unbind(() and unbind()) calls, chained after the bulk one.
# - esc and enter are absent: both stay bound in both modes, and esc is mode-sensitive.
# - ctrl-d/ctrl-u are here so NORMAL gets half-page and SEARCH gets fzf's line editing back.
typeset -ga _HOP_VIM_KEYS
_hop_vim_init() {
	emulate -L zsh
	_HOP_VIM_KEYS=(
		{a..z} {A..Z} {0..9} space
		'!' '"' '#' '$' '%' '&' "'" '*' '+' ',' '-' '.' '/' ':' ';'
		'<' '=' '>' '?' '@' '[' '\' ']' '^' '_' '`' '{' '|' '}' '~'
		ctrl-d ctrl-u
	)
}
_hop_vim_init

# _hop_vim_on -> 0 when the modal layer should be active.
# - HOP_VIM=0 is the environment escape hatch; --no-vim sets it as a local inside hop().
_hop_vim_on() {
	emulate -L zsh
	[[ ${HOP_VIM:-1} != 0 ]]
}

# _hop_vim_header <NORMAL|SEARCH> -> the mode legend, mode name first.
# - Mode name first because which mode is active is the one thing a user must never guess.
# - The one-line form is 74 columns, so an 80-column terminal shows it without wrapping.
# - Above 120 columns the preview takes 55% and the header pane is only 45% of the terminal.
# - fzf CLIPS an over-long header rather than wrapping it, so a narrow pane re-flows the text.
_hop_vim_header() {
	emulate -L zsh
	local mode=$1
	local -i cols=${COLUMNS:-80}
	local -i avail=$cols
	(( cols >= 120 )) && avail=$(( cols * 45 / 100 ))
	(( avail = avail - 4 ))
	local -a lines
	if [[ $mode == SEARCH ]]; then
		lines=('SEARCH  type to filter  esc normal  enter cd  ^o code  ^y yank  ^g browse')
		if (( ${#lines[1]} > avail )); then
			lines=(
				'SEARCH  type to filter'
				'esc normal  enter cd'
				'^o code  ^y yank  ^g browse'
			)
		fi
	else
		lines=('NORMAL  j/k move  g/G top/bot  / search  : view  ? help  enter cd  q quit')
		if (( ${#lines[1]} > avail )); then
			lines=(
				'NORMAL  j/k move  g/G top/bot'
				'/ search  : view  ? help'
				'enter cd  q quit'
			)
		fi
	fi
	print -rn -- "${(pj:\n:)lines}"
}

# _hop_vim_binds <preview-cmd> <reload> <root> <restore> <query> [drill] [up]
# - Appends the whole modal --bind set to `args`, which is local in _hop_pick.
# - Also fills _hop_vim_prompt, _hop_vim_head, and the four HOP_VIM_* exports declared there.
# - Dynamic scoping is the established pattern in this file; see _hop_parse_result.
_hop_vim_binds() {
	emulate -L zsh
	local prev_cmd=$1 reload=$2 root=$3 restore=$4 query=$5 drill=${6:-} up=${7:-}
	local help_cmd="${(q)HOP_HOME}/bin/hop-preview --keys"
	local kinds_bin="${(q)HOP_HOME}/bin/hop-kinds"

	# Restoring the real preview on every nav key is what closes the `?` overlay, per the spec.
	# - change-preview with the same command is ~free: moving the focus re-runs the preview anyway.
	# - Emptying the label is the state reset, since the label is what `?` reads to pick a direction.
	local prev_restore="change-preview(${prev_cmd})+change-preview-label()"

	local keys="${(j:,:)_HOP_VIM_KEYS}"
	local unbind_all="unbind(${keys})+unbind(()+unbind())"
	local rebind_all="rebind(${keys})+rebind(()+rebind())"

	local nh sh
	nh=$(_hop_vim_header NORMAL)
	sh=$(_hop_vim_header SEARCH)

	local to_search="${unbind_all}+enable-search+change-prompt(/ )+change-header(${sh})+${prev_restore}"

	# Esc clears the query on the way back to NORMAL, exactly as it drops the filter in k9s.
	# - A query still displayed but no longer filtering anything is worse than no query at all.
	# - `clear-query+search()` is deliberately NOT here; it sits on the esc bind, statically.
	# - fzf does NOT honour `search()` emitted BY a `transform:`, and esc has to be a transform.
	# - Measured: from a transform the list stayed pos=0 count=0, from a static bind pos=1 count=4.
	# - Untreated, esc out of a query matching nothing left NORMAL holding a permanently dead list.
	HOP_VIM_TO_NORMAL="${rebind_all}+disable-search+change-prompt(> )+change-header(${nh})+${prev_restore}"

	# Esc has three meanings, resolved from fzf's own exported state rather than a file.
	# - In the kind menu it goes back to the view you came from, which is the k9s behaviour.
	# - In SEARCH it returns to NORMAL and drops the filter.
	# - In NORMAL it quits.
	local esc_act='transform:case "$FZF_PROMPT" in ": "*) printf %s "${HOP_VIM_MENU_BACK:-abort}" ;; *) if [ "$FZF_INPUT_STATE" = disabled ]; then printf abort; else printf %s "$HOP_VIM_TO_NORMAL"; fi ;; esac'

	# The preview label is the overlay's own state, so `?` needs no file and no counter either.
	HOP_VIM_HELP_ON="show-preview+change-preview(${help_cmd})+change-preview-label( keys )"
	HOP_VIM_HELP_OFF=$prev_restore
	local help_act='transform:if [ -n "$FZF_PREVIEW_LABEL" ]; then printf %s "$HOP_VIM_HELP_OFF"; else printf %s "$HOP_VIM_HELP_ON"; fi'

	# `:` switches the view IN PLACE, like k9s `:pods`, inside this one fzf process.
	# - The old design ran a nested fzf inside execute(), which was the reported bug.
	# - $FZF_PROMPT is the whole state: a ':' prompt means the list currently holds kinds.
	# - So there is no state file, and two hop instances cannot interfere with each other.
	local kind_act='' enter_act='' mh
	if [[ -n $root ]]; then
		mh='VIEW  enter switch  esc back  j/k move  / filter'
		HOP_VIM_TO_MENU="change-prompt(: )+change-header(${mh})+change-preview-label()+reload(${kinds_bin} menu ${(q)root})"
		kind_act="$HOP_VIM_TO_MENU"

		# {2} is the kind name, because hop-kinds menu puts it in field 2 for exactly this.
		HOP_VIM_PICK_KIND="reload(${kinds_bin} rows ${(q)root} {2})+change-prompt(> )+change-header(${nh})+${prev_restore}+first"

		# Esc out of the menu regenerates the view you came from, so cancelling is lossless.
		[[ -n $restore ]] && HOP_VIM_MENU_BACK="reload(${restore})+change-prompt(> )+change-header(${nh})+${prev_restore}+first"

		# Enter means "switch view" in the menu and "cd" everywhere else; accept keeps today's path.
		enter_act='transform:case "$FZF_PROMPT" in ": "*) printf %s "$HOP_VIM_PICK_KIND" ;; *) printf accept ;; esac'
	fi

	local conf_act=''
	[[ -n $reload ]] && conf_act="reload:${reload}"

	# Letter verbs ride print()+accept rather than --expect, which unbind cannot touch.
	# - An --expect key stays live after unbind, so it would accept in SEARCH instead of typing.
	# - That was probed on this machine, not assumed; see README.
	# - The name printed is the existing ctrl-/alt- key, so _hop_dispatch needs no new arms.
	local k act
	for k in "${_HOP_VIM_KEYS[@]}"; do
		act=''
		case $k in
			j) act="down+${prev_restore}" ;;
			k) act="up+${prev_restore}" ;;
			g) act="first+${prev_restore}" ;;
			G) act="last+${prev_restore}" ;;
			ctrl-d) act="half-page-down+${prev_restore}" ;;
			ctrl-u) act="half-page-up+${prev_restore}" ;;
			o) act='print(ctrl-o)+accept' ;;
			O) act='print(ctrl-t)+accept' ;;
			e) act='print(alt-o)+accept' ;;
			y) act='print(ctrl-y)+accept' ;;
			Y) act='print(alt-y)+accept' ;;
			b) act='print(ctrl-g)+accept' ;;
			p) act='toggle-preview' ;;
			q) act='abort' ;;
			# r re-runs the current view, for when the repo changed under you.
			r) [[ -n $restore ]] && act="reload(${restore})" ;;
			# l/h move between levels, matching ranger and lf rather than vim's cursor motion.
			l) [[ -n $drill ]] && act='print(ctrl-l)+accept' ;;
			h) [[ -n $up ]] && act='print(ctrl-h)+accept' ;;
			# `a` for +conf is gone: `:` now switches to conf properly, and alt-a still works in SEARCH.
			'/') act=$to_search ;;
			'?') act=$help_act ;;
			':') act=$kind_act ;;
		esac
		args+=(--bind="${k}:${act:-ignore}")
	done
	args+=(--bind='(:ignore' --bind='):ignore')
	# clear-query+search() runs unconditionally, BEFORE the transform picks one of esc's three jobs.
	# - It has to be static: fzf ignores a `search()` that a transform emits, which is the live bug.
	# - It has to come after clear-query, or search() re-runs the query that matched nothing.
	# - It is harmless in the two branches that abort or leave the menu, since both discard the list.
	# - `search()` needs fzf 0.59.0, which HOP_FZF_MIN covers; an unknown action makes fzf refuse.
	args+=(--bind="esc:clear-query+search()+${esc_act}")
	# Binding enter at all is new; the non-menu branch is a literal accept so cd is unchanged.
	[[ -n $enter_act ]] && args+=(--bind="enter:${enter_act}")

	# A CLI query means the user is already refining, so SEARCH is the start mode.
	# - No --disabled in that branch, because --select-1 has to see a FILTERED list.
	# - Otherwise `hop vpc prod` stops jumping straight to a unique match, hop's best trick.
	if [[ -n $query ]]; then
		_hop_vim_prompt='/ '
		_hop_vim_head=$sh
		args+=(--bind="start:${to_search}")
	else
		_hop_vim_prompt='> '
		_hop_vim_head=$nh
		args+=(--disabled)
	fi
}

# The oldest fzf that can run the picker below, and why it is this exact patch release.
# - 0.60.0 added `--accept-nth`, which is how a row's dir and preview reach the parent shell.
# - 0.60.3 made `--accept-nth` work alongside `--select-1`, and _hop_pick passes BOTH every call.
# - So 0.60.0 would break `hop vpc prod` jumping to a unique match, which is hop's best trick.
# - Debian and Ubuntu package 0.44.x, where the picker dies with `unknown option: --accept-nth`.
# - Sources: fzf CHANGELOG, "Added `--accept-nth`" under 0.60.0, and #4287 under 0.60.3.
# - Overridable, because a guard that locks out a working fzf is worse than the bug it prevents.
typeset -g HOP_FZF_MIN=${HOP_FZF_MIN:-0.60.3}

# _hop_ver_lt <a> <b> -> 0 when dotted version a is older than b, comparing three fields.
# - Non-digits are stripped per field rather than evaluated, because HOP_FZF_MIN is user-settable.
# - A bare `local -i` here made `0.60.3rc1` abort the caller with `bad math expression`.
_hop_ver_lt() {
	emulate -L zsh
	local -a x=(${(s:.:)1}) y=(${(s:.:)2})
	local -i i
	local a b
	for i in 1 2 3; do
		a=${${x[i]:-0}//[^0-9]/}
		b=${${y[i]:-0}//[^0-9]/}
		(( ${a:-0} < ${b:-0} )) && return 0
		(( ${a:-0} > ${b:-0} )) && return 1
	done
	return 1
}

# _hop_fzf_ver -> REPLY is fzf's dotted version, memoized so a shell forks for it at most once.
# - hop.zsh is sourced by EVERY interactive shell, so this must never run at source time.
# - An empty REPLY means "could not tell", and every caller treats that as permission to proceed.
_hop_fzf_ver() {
	emulate -L zsh
	if (( ${+_HOP_FZF_VER} )); then
		REPLY=$_HOP_FZF_VER
		return 0
	fi
	local out v
	out=$(fzf --version 2>/dev/null)
	# fzf prints `0.60.3 (abc1234)`, so only the leading run of digits and dots is ever read.
	v=${out%%[^0-9.]*}
	[[ $v == <->.<->(.<->|) ]] || v=''
	typeset -g _HOP_FZF_VER=$v
	REPLY=$v
	return 0
}

# _hop_fzf_ok -> 0 when the installed fzf can run the picker, else it explains and fails.
# - Called from hop(), never from this file's top level, so a shell that never hops never forks.
_hop_fzf_ok() {
	emulate -L zsh
	local REPLY
	_hop_fzf_ver
	local v=$REPLY
	[[ -n $v ]] || return 0
	_hop_ver_lt "$v" "$HOP_FZF_MIN" || return 0
	print -ru2 -- "hop: fzf ${v} is too old; hop needs ${HOP_FZF_MIN} or newer."
	print -ru2 -- 'hop: the picker passes --accept-nth with --select-1, which older fzf mishandles.'
	print -ru2 -- 'hop: a distro package is the usual cause; Debian and Ubuntu ship fzf 0.44.x.'
	print -ru2 -- 'hop: install an upstream release: https://github.com/junegunn/fzf/releases'
	return 1
}

# _hop_pick <label> <header> [query] [reload] [root] [drill] [restore] [up]  <targets on stdin
# - Emits the key line (empty for plain Enter) and then dir<TAB>preview.
# - Every verb rides --expect or print(), never become(), since only the parent shell can cd.
# - --preview must name a real executable: fzf spawns it in a fresh $SHELL -c with no functions.
# - No --exit-0: a typo'd query should open fzf so it can be fixed, not exit 1 with an error.
# - The <120 preview-window rule gives a narrow terminal a horizontal split and full row width.
# - alt-a rather than ctrl-a for the reload: ctrl-a is fzf's own beginning-of-line.
_hop_pick() {
	emulate -L zsh
	local label=$1 header=$2 query=${3:-} reload=${4:-} root=${5:-} drill=${6:-} restore=${7:-} up=${8:-}
	local prev_cmd="${(q)HOP_HOME}/bin/hop-preview {2} {3}"

	# Built once because repeated --expect flags have ambiguous merge semantics, and ctrl-l is gated on drill.
	local _hop_expect='ctrl-o,ctrl-t,ctrl-y,ctrl-g,alt-o,alt-y'
	[[ -n $drill ]] && _hop_expect+=',ctrl-l'
	[[ -n $up ]] && _hop_expect+=',ctrl-h'

	local -a args
	args=(
		--ansi
		--delimiter=$'\t'
		--with-nth=1
		--accept-nth='2,3'
		--no-multi
		--layout=reverse
		--height='80%'
		--min-height=18
		--info=inline
		--border=rounded
		--border-label=" $label "
		--header-first
		--header-border=bottom
		--pointer='▸'
		--tiebreak=begin,length
		# Substring, not subsequence, because the display line is ~90 columns wide.
		# - Measured on a 1k-row repo: a 3-word fuzzy query hit 13 rows where exact hit exactly 1.
		# - One service name fuzzy-matched 22 rows and exactly 3; 'eks staging' was 16 versus 6.
		# - fzf's ' prefix still opts one term back into fuzzy, so nothing is actually lost.
		--exact
		--select-1
		--expect="$_hop_expect"
		--preview="$prev_cmd"
		--preview-window='right,55%,border-left,wrap,<120(down,50%,border-top,wrap)'
		--bind='ctrl-/:toggle-preview'
		--bind='alt-p:toggle-preview'
		--bind='ctrl-r:refresh-preview'
	)
	[[ -n $query ]] && args+=(--query="$query")
	[[ -n $reload ]] && args+=(--bind="alt-a:reload:$reload")

	# No temp file any more: the view mode lives in $FZF_PROMPT, which fzf exports for us.
	local _hop_vim_prompt='hop ▸ ' _hop_vim_head=$header
	local -x HOP_VIM_TO_NORMAL='' HOP_VIM_HELP_ON='' HOP_VIM_HELP_OFF=''
	local -x HOP_VIM_TO_MENU='' HOP_VIM_PICK_KIND='' HOP_VIM_MENU_BACK=''
	if _hop_vim_on; then
		_hop_vim_binds "$prev_cmd" "$reload" "$root" "$restore" "$query" "$drill" "$up"
	fi
	args+=(--prompt="$_hop_vim_prompt" --header="$_hop_vim_head")

	fzf "${args[@]}"
	return $?
}

# _hop_reload_cmd <root> <kind...> -> a shell command string that regenerates the list.
# - alt-a's reload runs in a fresh shell, so it re-sources hop.zsh instead of calling a function.
# - Sourcing hop.zsh and not just providers.zsh is what gives the child the same kind registry.
# - `zsh -f` skips rc files; the args after the script become $1.. for _hop_generate.
_hop_reload_cmd() {
	emulate -L zsh
	local root=$1
	shift
	local script='source "$HOP_HOME/hop.zsh"; _hop_generate "$@"'
	local cmd="HOP_HOME=${(qq)HOP_HOME} zsh -f -c ${(qq)script} hop ${(qq)root}"
	local k
	for k in "$@"; do
		cmd+=" ${(qq)k}"
	done
	print -r -- "$cmd"
}

# _hop_parse_result <fzf-output> -> fills _hop_key, _hop_dir, _hop_preview.
# - Those three are `local` in _hop_run; zsh's dynamic scoping makes them writable here.
# - Assigning rather than `typeset -g` keeps hop from leaving state in the interactive shell.
# - The LAST line is always the --accept-nth fields; the lines before it are key lines.
# - A NORMAL-mode letter verb produces two of those, because --expect emits its own empty line.
# - So the real key is the first non-empty line, which also covers the plain two-line case.
_hop_parse_result() {
	emulate -L zsh
	local out=$1
	_hop_key='' _hop_dir='' _hop_preview=''
	local -a lines=("${(@f)out}")
	(( $#lines )) || return 1
	local l
	for l in "${(@)lines[1,-2]}"; do
		if [[ -n $l ]]; then
			_hop_key=$l
			break
		fi
	done
	IFS=$'\t' read -r _hop_dir _hop_preview <<< "${lines[-1]}"
	[[ -n $_hop_preview ]] || _hop_preview=$_hop_dir
	[[ -n $_hop_dir ]]
}
