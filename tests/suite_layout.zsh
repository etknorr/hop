#!/usr/bin/env zsh
# suite_layout: every list hop draws starts each column at the same offset on every row.
# - A row is measured as fzf draws it: field 1 with its colour stripped, then the TAB, then rel.
# - One table case per list hop builds: the main picker, a reload, a long name, repos, workspaces, and a resolve's injected rows.
# - Nothing draws a picker: rows come from the functions that build them, and the injected rows from a selecting stub.

stub_bin

# lay_plain <row> -> REPLY is the row's display field with its colour stripped.
lay_plain() {
	emulate -L zsh
	setopt local_options extended_glob
	REPLY=${${1%%$'\t'*}//$'\e['[0-9;]#m/}
}

# lay_shape <row> <words> -> REPLY is "<offset of word 2>,...,<offset of word n>|<width>" for the row's plain display.
# - Offsets are 1-based characters, which is where fzf draws each column; width is where the TAB before rel falls.
# - A name holding a space would read as two words, and no fixture name holds one.
lay_shape() {
	emulate -L zsh
	lay_plain "$1"
	local plain=$REPLY
	local -i i k=1 n=$2
	local -a offs
	for (( i = 2; i <= ${#plain} && k < n; i++ )); do
		if [[ ${plain[i-1]} == ' ' && ${plain[i]} != ' ' ]]; then
			(( k++ ))
			offs+=($i)
		fi
	done
	REPLY="${(j:,:)offs}|${#plain}"
}

# lay_shapes <words> <rows> -> REPLY is the distinct shapes, one per line, so an aligned list has exactly one.
lay_shapes() {
	emulate -L zsh
	local r
	local -a shapes
	for r in ${(f)2}; do
		lay_shape "$r" "$1"
		shapes+=("$REPLY")
	done
	REPLY=${(F)${(u)shapes}}
}

# lay_row <rows> <name> -> REPLY is the row whose plain display starts with <name> and a space.
lay_row() {
	emulate -L zsh
	local r want=$2
	for r in ${(f)1}; do
		lay_plain "$r"
		if [[ $REPLY == "$want "* ]]; then
			REPLY=$r
			return 0
		fi
	done
	REPLY=''
	return 1
}

# lay_clip <name> -> REPLY is the name as the 56-column cap clips it: its first 28 characters, …, its last 27.
lay_clip() {
	emulate -L zsh
	REPLY="${1[1,28]}…${1[-27,-1]}"
}

typeset -A LAY_ROWS LAY_WORDS LAY_DESC
typeset -a LAY_CASES=()

# ---------------------------------------------------------------------------
# The main picker, a reload, and a resolve's injected rows, all over the resolver's fixture.
# ---------------------------------------------------------------------------
typeset LY_REPO
match_fixture || return 1
LY_REPO=$REPLY

LAY_CASES+=(main)
LAY_DESC[main]='main picker'
LAY_WORDS[main]=5
LAY_ROWS[main]=$(hop_probe "builtin cd -q ${(q)LY_REPO} && _hop_rows ${(q)LY_REPO} '' \${=HOP_DEFAULT_KINDS//,/ }")

LAY_CASES+=(reload)
LAY_DESC[reload]='hop-kinds reload'
LAY_WORDS[reload]=5
LAY_ROWS[reload]=$(hop_probe "\${HOP_HOME}/bin/hop-kinds rows ${(q)LY_REPO} tg helm dir")

# ly_pickrun <stubdir> <hop-code> -> run hop with a terminal assumed and the selecting stub as fzf.
ly_pickrun() {
	emulate -L zsh
	local stub=$1 code=$2
	hop_bound 30 zsh -f -c "$(fixture_pins)
export PATH=${(q)stub}:\$PATH
source ${(q)HOP_HOME}/hop.zsh || exit 97
_hop_tty_ok() { return 0 }
builtin cd -q -- ${(q)LY_REPO} || exit 96
${code}" >/dev/null 2>&1
}

typeset LY_SP=terraform/acct-security-tooling-prod
if [[ -n $IT_REAL_FZF ]]; then
	stub_fzf_select '' 1
	typeset LY_STUB=$REPLY
	ly_pickrun "$LY_STUB" 'hop acct sec prod'
	LAY_CASES+=(injected)
	LAY_DESC[injected]='resolver pick, injected ancestor included,'
	LAY_WORDS[injected]=5
	[[ -r $LY_STUB/stdin ]] && LAY_ROWS[injected]=$(<"$LY_STUB/stdin")
else
	skip_cap 'layout: a resolve injects ancestor rows aligned with its list' 'fzf is not installed'
fi

# ---------------------------------------------------------------------------
# A list holding one 73-character name, which the 56-column cap has to clip.
# ---------------------------------------------------------------------------
typeset LY_LONG=service-with-a-very-long-name-that-keeps-going-right-past-the-cap-in-prod
typeset LY_LONG_MID=that-keeps-going
fixture_repo layoutlong || return 1
typeset LY_LREPO=$REPLY
typeset n
for n in api db "$LY_LONG"; do
	fixture_write "sandbox/$n/README.md" "# $n" || return 1
done
fixture_commit 'long names' || return 1
fixture_config "hop_kind sbx --default --dirs sandbox --desc 'sandbox dirs'" || return 1

LAY_CASES+=(long)
LAY_DESC[long]='list with one 73-character name, a'
LAY_WORDS[long]=3
LAY_ROWS[long]=$(hop_probe "builtin cd -q ${(q)LY_LREPO} && _hop_rows ${(q)LY_LREPO} '' sbx")
fixture_config_reset

# ---------------------------------------------------------------------------
# The repo picker, with the retired copies that once pushed their rows out of line.
# ---------------------------------------------------------------------------
typeset LY_RETIRED=platform-configuration.retired-2026-09-14
typeset -a LY_REPOS=()
for n in configuration configuration.retired-2026-09-14 platform-configuration "$LY_RETIRED" web; do
	mkdir -p -- "$HOP_FIX_HOME/strava/$n" || return 1
	LY_REPOS+=("$HOP_FIX_HOME/strava/$n")
done

LAY_CASES+=(repo)
LAY_DESC[repo]='repo picker'
LAY_WORDS[repo]=2
LAY_ROWS[repo]=$(hop_probe "_hop_provider_repo ${(j: :)${(@q)LY_REPOS}}")

# A row built after the list, from _hop_row_like, takes that list's widths and drops what it drops.
LAY_CASES+=(like)
LAY_DESC[like]='repo picker, plus a row built later from _hop_row_like,'
LAY_WORDS[like]=2
LAY_ROWS[like]=$(hop_probe "rows=\$(_hop_provider_repo ${(j: :)${(@q)LY_REPOS}})
print -r -- \"\$rows\"
_hop_row_like=\${rows%%\$'\\n'*}
_hop_row repo - - - x /elsewhere/x /elsewhere/x")

# ---------------------------------------------------------------------------
# The workspace picker, whose region is - on every row and whose names are short.
# ---------------------------------------------------------------------------
typeset -a LY_WS=("$HOP_FIX_HOME/ws-one" "$HOP_FIX_HOME/ws-second" "$HOP_FIX_HOME/w3")
mkdir -p -- "$HOP_FIX_HOME/ws-one/r1/.git" "$HOP_FIX_HOME/ws-one/r2/.git" "$HOP_FIX_HOME/ws-second" \
	"$HOP_FIX_HOME/w3/only/.git" || return 1

LAY_CASES+=(ws)
LAY_DESC[ws]='workspace picker'
LAY_WORDS[ws]=4
LAY_ROWS[ws]=$(hop_probe "HOP_WORKSPACES=${(q)${(j.:.)LY_WS}}; _hop_provider_ws")

# ---------------------------------------------------------------------------
# The table: every list is aligned.
# ---------------------------------------------------------------------------
typeset k
typeset -a rows
for k in "${LAY_CASES[@]}"; do
	t "layout: every ${LAY_DESC[$k]} row starts each column at the same offset"
	rows=(${(f)LAY_ROWS[$k]})
	assert_ge $#rows 3 "control: the ${k} case needs rows of different lengths to prove anything"
	lay_shapes "${LAY_WORDS[$k]}" "${LAY_ROWS[$k]}"
	rows=(${(f)REPLY})
	assert_eq 1 $#rows "rows drawn at more than one shape: ${(j:; :)rows}"
done

# ---------------------------------------------------------------------------
# Widths, dropped columns and the clip.
# ---------------------------------------------------------------------------
t 'layout: the main picker keeps every column, because each holds a value on some row'
lay_row "${LAY_ROWS[main]}" vpc
lay_plain "$REPLY"
assert_eq 5 ${#${=REPLY}} "a tg row shows name, kind, scope, env and region: ${REPLY}"

t 'layout: a 73-character name is clipped to 56, keeping its start and its end'
lay_clip "$LY_LONG"
typeset LY_CLIPPED=$REPLY
lay_row "${LAY_ROWS[long]}" "$LY_CLIPPED"
assert_nonempty "$REPLY" "no row shows ${LY_CLIPPED}"
lay_shape "$REPLY" 2
assert_eq '58' "${REPLY%%|*}" 'the kind column starts after the 56-column name and one space'

t 'layout: the clipped row keeps its full path in rel, so the hidden middle of its name still matches'
if [[ -n $IT_REAL_FZF ]]; then
	typeset LY_HITS
	LY_HITS=$(print -r -- "${LAY_ROWS[long]}" | fzf_filter "$LY_LONG_MID")
	rows=(${(f)LY_HITS})
	assert_eq 1 $#rows "exactly the clipped row must match ${LY_LONG_MID}"
	assert_contains "${rows[1]}" $'\t'"$LY_LREPO/sandbox/$LY_LONG"$'\t'
else
	skip 'layout: the clipped row matches through rel' 'fzf is not installed (see the injected-row skip)'
fi

t 'layout: a list whose env and region are always - drops both columns'
lay_row "${LAY_ROWS[long]}" api
lay_plain "$REPLY"
assert_eq 'api sbx sandbox' "${(j: :)${=REPLY}}"

t 'layout: a repo row is only its name and kind, because scope, env and region are always -'
lay_row "${LAY_ROWS[repo]}" configuration
lay_plain "$REPLY"
assert_eq 'configuration repo' "${(j: :)${=REPLY}}"

t 'layout: a 41-character retired copy fits under the cap, so it shows whole beside the live repo'
lay_row "${LAY_ROWS[repo]}" "$LY_RETIRED"
assert_nonempty "$REPLY" 'no repo row shows the whole retired name'
typeset -a LY_F=("${(@ps:\t:)REPLY}")
lay_plain "${LY_F[4]}"
assert_eq "~/strava/${LY_RETIRED}/" "$REPLY" 'rel still carries the whole name'

t 'layout: a row built from _hop_row_like drops the same columns as its list'
rows=(${(f)LAY_ROWS[like]})
lay_plain "${rows[-1]}"
assert_eq 'x repo' "${(j: :)${=REPLY}}"

t 'layout: a list of short names is padded to the 20-column floor'
lay_row "${LAY_ROWS[ws]}" ws-one
lay_shape "$REPLY" 2
assert_eq '22' "${REPLY%%|*}" 'the kind column starts after the 20-column floor and one space'

t 'layout: a workspace row drops region, which is - on every one, and keeps its path and repo count'
lay_row "${LAY_ROWS[ws]}" ws-one
lay_plain "$REPLY"
assert_eq 'ws-one ws ~/ws-one 2 repos' "${(j: :)${=REPLY}}"

t 'layout: the injected account dir is the first row the picker gets'
if (( ${+LAY_ROWS[injected]} )); then
	rows=(${(f)LAY_ROWS[injected]})
	assert_contains "${rows[1]}" $'\t'"$LY_REPO/$LY_SP"$'\t' 'row 1 must be the injected account dir'
else
	skip 'layout: the injected account dir is row 1' 'fzf is not installed (see the injected-row skip)'
fi

t 'layout: a row with no raw display, as a legacy provider prints, passes through untouched'
typeset LY_LEGACY=$'legacy display\t/x\t/x\t\e[2mx/\e[0m'
typeset LY_OUT
LY_OUT=$(hop_probe "typeset _hop_gen_raw=1 rows
rows=\$(_hop_row tg a prod us-east-1 one /r/one /r/one; _hop_row tg bb - - two-longer /r/two /r/two)
_hop_layout \"\$rows\"\$'\\n'${(q)LY_LEGACY}
print -r -- \"\$REPLY\"")
rows=(${(f)LY_OUT})
assert_eq 3 $#rows
assert_eq "$LY_LEGACY" "${rows[3]}" 'a legacy row has no columns to align'
lay_shapes 5 "${(F)rows[1,2]}"
rows=(${(f)REPLY})
assert_eq 1 $#rows "the raw rows beside it still align: ${(j:; :)rows}"

t 'layout: a separator byte inside a name reads as ?, so it adds no cell and shifts no column'
LY_OUT=$(hop_probe "typeset REPLY r1
_hop_row_raw dir sc - - \$'we\\x1fird' /r/x /r/x
r1=\$REPLY
_hop_row_raw dir sc - - normal /r/y /r/y
_hop_layout \"\$r1\"\$'\\n'\"\$REPLY\"
print -r -- \"\$REPLY\"")
rows=(${(f)LY_OUT})
lay_plain "${rows[1]}"
assert_eq 'we?ird dir sc' "${(j: :)${=REPLY}}" 'the part after the separator landed in the kind column'
lay_shapes 3 "$LY_OUT"
rows=(${(f)REPLY})
assert_eq 1 $#rows "rows drawn at more than one shape: ${(j:; :)rows}"

t 'layout: a dir row added to a tg-only list shows its kind whole, not as d…'
LY_OUT=$(hop_probe "typeset _hop_gen_raw=1 rows REPLY
rows=\$(_hop_row tg a prod us-east-1 one /r/one /r/one; _hop_row tg bb - - two /r/two /r/two)
unset _hop_gen_raw
_hop_layout \"\$rows\"
typeset _hop_row_like=\${REPLY%%\$'\\n'*}
print -r -- \"\$_hop_row_like\"
_hop_row dir a - - three /r/three /r/three")
rows=(${(f)LY_OUT})
lay_plain "${rows[2]}"
assert_eq 'three dir a - -' "${(j: :)${=REPLY}}"
lay_shapes 5 "$LY_OUT"
rows=(${(f)REPLY})
assert_eq 1 $#rows "the added row is out of line with the list: ${(j:; :)rows}"
