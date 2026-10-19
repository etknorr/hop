# hx_runner <root> <cases>: suite_match.zsh's table runner, sourced after hop.zsh, one TSV line per case.
# - A case is query, cwd relative to root, action, jump, and `c` for -c or `-`.
# - Out: the case, verdict, tier, rule, dir, preview, rel, n, m, inj, every candidate rel, picker query, note, report.
# - The report is _hop_headless_report's stderr for a non-jump verdict, its lines joined by a literal \n.
# - T0 runs first, as hop() runs it: one word, and never under jump=never.
hx_runner() {
	emulate -L zsh
	setopt local_options extended_glob
	local root=$1 cases=$2 tab=$'\t'
	builtin cd -q -- "$root" || return 96
	local -a kinds=(${=${HOP_DEFAULT_KINDS//,/ }})
	local all
	all=$(_hop_generate "$root" "${kinds[@]}")
	all=$(_hop_rank "$all")
	local _hop_res_verdict _hop_res_tier _hop_res_rule _hop_res_query _hop_res_note _hop_res_target
	local -i _hop_res_n _hop_res_m _hop_res_inj
	local -a _hop_res_rows reply f w rels
	local line q cwd action jump under rows udir tdir tprev trel rep _hop_jump
	for line in "${(@f)$(<"$cases")}"; do
		f=("${(@ps:\t:)line}")
		q=${f[1]} cwd=${f[2]} action=${f[3]} jump=${f[4]} under=${f[5]}
		if ! builtin cd -q -- "$root/$cwd"; then
			print -r -- "${line}${tab}cd-failed"
			continue
		fi
		rows=$all udir=''
		if [[ $under == c ]]; then
			udir=${PWD:A}
			_hop_filter_under "$udir" "${(@f)all}"
			rows=${(F)reply}
		fi
		w=(${=q})
		if [[ $jump != never ]] && (( $#w == 1 )) && _hop_literal_target "$q" "$root"; then
			print -r -- "${line}${tab}jump${tab}T0${tab}path${tab}${reply[1]}${tab}${reply[2]}${tab}${reply[3]}${tab}1${tab}1${tab}0${tab}${tab}${tab}${tab}"
			continue
		fi
		_hop_resolve "$q" "$rows" "$root" "$action" "$jump" "$udir"
		tdir='' tprev='' trel=''
		if [[ -n $_hop_res_target ]]; then
			f=("${(@ps:\t:)_hop_res_target}")
			tdir=${f[1]} tprev=${f[2]} trel=${f[3]}
		fi
		rels=()
		if (( $#_hop_res_rows )); then
			_hop_rels_of "${_hop_res_rows[@]}"
			rels=("${reply[@]}")
		fi
		rep=''
		if [[ $_hop_res_verdict != jump ]]; then
			_hop_jump=$jump
			rep=$(_hop_headless_report "$q" label 2>&1)
			rep=${rep//$'\n'/\\n}
		fi
		print -r -- "${line}${tab}${_hop_res_verdict}${tab}${_hop_res_tier}${tab}${_hop_res_rule}${tab}${tdir}${tab}${tprev}${tab}${trel}${tab}${_hop_res_n}${tab}${_hop_res_m}${tab}${_hop_res_inj}${tab}${(j:,:)rels}${tab}${_hop_res_query}${tab}${_hop_res_note}${tab}${rep}"
	done
}
