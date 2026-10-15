#!/usr/bin/env zsh
# suite_completions: completions/_hop, its release-tag listing and the flag specs _hop hands _arguments.
# - Tested directly, not through a real Tab press: driving compinit is heavier than this needs.
# - `_describe` is stubbed to capture the array it was handed, the one thing the bug corrupts.
# - Sourcing the file also runs its trailing `_hop "$@"`, which needs the real `_arguments`
#   completion builtin; that one harmless "command not found" is swallowed along with it.
_describe() {
	emulate -L zsh
	print -rl -- "${(@P)argv[-1]}"
}
{ source "$HOP_HOME/completions/_hop" } 2>/dev/null

# ct_repo -> REPLY is a fixture repo carrying three release tags, oldest first.
ct_repo() {
	emulate -L zsh
	fixture_repo comptags || return 1
	local d=$REPLY
	fixture_write hop.zsh '# fixture' || return 1
	fixture_commit 'v1.0.0' || return 1
	_hop_fix_git -C "$d" tag v1.0.0 || return 1
	fixture_commit 'v1.1.0' || return 1
	_hop_fix_git -C "$d" tag v1.1.0 || return 1
	fixture_commit 'v2.0.0' || return 1
	_hop_fix_git -C "$d" tag v2.0.0 || return 1
	REPLY=$d
	return 0
}

typeset -g CT_REPO
ct_repo
CT_REPO=$REPLY

# ---------------------------------------------------------------------------
# The bug: `git tag --list` honours column.ui and joins every tag onto one line.
# ---------------------------------------------------------------------------
t '_hop_versions offers every tag, newest first, by default'
typeset out
out=$(HOP_HOME=$CT_REPO _hop_versions)
assert_eq $'v2.0.0\nv1.1.0\nv1.0.0' "$out"

t '_hop_versions still offers every tag as SEPARATE candidates under column.ui=always'
_hop_fix_git -C "$CT_REPO" config column.ui always
out=$(HOP_HOME=$CT_REPO _hop_versions)
_hop_fix_git -C "$CT_REPO" config --unset column.ui
assert_eq $'v2.0.0\nv1.1.0\nv1.0.0' "$out"

# ---------------------------------------------------------------------------
# No tags at all: nothing to offer, and _hop_versions must say so via its exit status.
# ---------------------------------------------------------------------------
t '_hop_versions has nothing to offer when the repo has no release tags'
fixture_repo comptags-empty
typeset empty=$REPLY
fixture_write hop.zsh '# fixture'
fixture_commit 'no releases yet'
out=$(HOP_HOME=$empty _hop_versions)
typeset -i st=$?
assert_empty "$out"
assert_eq '1' "$st"

# ---------------------------------------------------------------------------
# The flag specs, read by calling _hop with _arguments stubbed to capture them.
# ---------------------------------------------------------------------------
typeset -ga CT_SPECS
_arguments() {
	emulate -L zsh
	CT_SPECS=("$@")
}
_hop

# ct_spec <option> -> REPLY is the spec that defines <option>, whole; 1 when there is none.
# - A spec reads (excluded...)name, then [desc], = or + for its argument, so the name ends at the first of those.
ct_spec() {
	emulate -L zsh
	local s n
	REPLY=''
	for s in "${CT_SPECS[@]}"; do
		n=${s#\(*\)}
		n=${n%%[\[=+:]*}
		if [[ $n == "$1" ]]; then
			REPLY=$s
			return 0
		fi
	done
	return 1
}

# ct_excl <option> -> reply is the options its spec excludes.
ct_excl() {
	emulate -L zsh
	reply=()
	ct_spec "$1" || return 1
	[[ $REPLY == \(* ]] || return 0
	local g=${${REPLY#\(}%%\)*}
	reply=(${=g})
}

# Every option hop() parses has to complete, so a new flag cannot ship without its completion.
# - The labels come from hop's own case statement, so this list cannot drift from the parser.
# - `-*`, `--` and `/ | -` are the catch-all and the two literal targets, not options.
t 'every option hop parses has a completion spec'
typeset -a CT_OPTS CT_MISSING
typeset CT_LINE CT_W
for CT_LINE in "${(@f)$(hop_probe 'functions hop')}"; do
	CT_LINE=${CT_LINE#"${CT_LINE%%[^[:space:]]*}"}
	[[ $CT_LINE == \(-* ]] || continue
	CT_LINE=${${CT_LINE#\(}%%\)*}
	for CT_W in ${(s: | :)CT_LINE}; do
		CT_W=${${CT_W%%=*}%\*}
		[[ $CT_W == -?* && $CT_W != -- ]] && CT_OPTS+=("$CT_W")
	done
done
CT_OPTS=("${(@u)CT_OPTS}")
assert_ge "$#CT_OPTS" 1 'control: no option labels were read out of hop at all'
for CT_W in "${CT_OPTS[@]}"; do
	ct_spec "$CT_W" || CT_MISSING+=("$CT_W")
done
assert_empty "${(j:, :)CT_MISSING}" 'hop parses these but Tab never offers them'
assert_contains " ${CT_OPTS[*]} " ' --action ' 'control: the newest flags have to be among the labels read'
assert_contains " ${CT_OPTS[*]} " ' -o '

t '--action completes exactly the modes hop accepts, in the same order'
ct_spec --action
typeset CT_MODES=${${REPLY##*:\(}%\)}
assert_eq "$(hop_probe 'print -r -- "${_HOP_ACTIONS[*]}"')" "$CT_MODES" 'a mode hop accepts is missing from Tab, or Tab offers one hop refuses'
assert_contains "$REPLY" '--action=-' 'the mode rides in the same word, as --action=MODE, which is all hop parses'

# hop exits 2 on -o with -e and on --action with --cd, -o or -e, so Tab must not offer those pairs.
t '-o and -e exclude each other and --action, which is what hop refuses'
ct_excl -o
assert_eq '-o --open -e --reveal --action' "${reply[*]}"
ct_excl --reveal
assert_eq '-o --open -e --reveal --action' "${reply[*]}"

t '--action excludes --cd, -o and -e, and --cd excludes --action alone'
ct_excl --action
assert_eq '--cd -o --open -e --reveal --action' "${reply[*]}"
ct_excl --cd
assert_eq '--cd --action' "${reply[*]}" '--cd -o is cd+open, so --cd must never exclude -o or -e'

t '-p and --pick are one option'
ct_excl --pick
assert_eq '-p --pick' "${reply[*]}"

t '-v completes, and is described exactly as -V'
ct_spec -V
typeset CT_VSPEC=${REPLY/-V\[/-v[}
ct_spec -v
assert_eq "$CT_VSPEC" "$REPLY" '-v has to complete as the same option -V is'

t 'the header names every flag the specs define'
typeset CT_HEAD
CT_HEAD=$(sed -n '1,/^$/p' "$HOP_HOME/completions/_hop")
# Whole words, because a substring test let -p pass inside --pick and -c inside --cwd.
# - Split on whitespace, , and /, then cut at = or [, so --action=MODE and --doctor[=short] still name their flag.
typeset -a CT_HWORDS=(${=${CT_HEAD//[,\/]/ }})
CT_HWORDS=(${CT_HWORDS%%[=\[]*})
CT_MISSING=()
for CT_W in "${CT_OPTS[@]}"; do
	(( ${CT_HWORDS[(Ie)$CT_W]} )) || CT_MISSING+=("$CT_W")
done
assert_empty "${(j:, :)CT_MISSING}" 'the header comment is the only map of the flags, and it went stale before'
