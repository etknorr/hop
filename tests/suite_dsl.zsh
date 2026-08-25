#!/usr/bin/env zsh
# suite_dsl: lib/dsl.zsh, the hop_kind registry and the generic enumeration engine.
#
# - Every kind here is declared BY THIS FILE in a fixture config, never taken from presets/.
# - That is the point: a preset can change without this suite going quiet about the engine.
# - suite_providers.zsh covers the shipped declarations; this file covers the options themselves.
# - One synthetic repo carries every path shape, and each test declares the kinds it needs.
# - Nothing here can open a terminal: the engine is a pure function from a git repo to rows.

setopt local_options no_nomatch null_glob

typeset -g REPLY DSL_ERRTEXT DSL_ERRFILE
fixture_tmpdir dslerr
DSL_ERRFILE="$REPLY/stderr"

# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

# dsl_kinds <declaration...> -> write a fixture config holding exactly these hop_kind lines.
# - Each argument is one whole line, so a declaration may use a trailing backslash across two.
dsl_kinds() {
	emulate -L zsh
	fixture_config "$@"
}

# dsl_gen <root> <kind...> -> rows on stdout, from a child shell using the fixture config.
dsl_gen() {
	emulate -L zsh
	local root=$1
	shift
	hop_probe "_hop_generate ${(q)root} ${(j: :)${(@q)@}}" 2>"$DSL_ERRFILE"
	DSL_ERRTEXT=$(<"$DSL_ERRFILE")
	return 0
}

# dsl_names <root> <kind> -> REPLY is the name column of every row, one per line, in order.
dsl_names() {
	emulate -L zsh
	setopt extended_glob
	local rows
	rows=$(dsl_gen "$@")
	local r disp
	local -a out=()
	for r in ${(f)rows}; do
		[[ -n $r ]] || continue
		disp=${${r%%$'\t'*}//$'\e['[0-9;]##m/}
		out+=(${disp%% *})
	done
	REPLY=${(pj:\n:)out}
	return 0
}

# dsl_cols <root> <kind> <name> -> `reply` is that row's five plain words; 1 when there is no such row.
dsl_cols() {
	emulate -L zsh
	setopt extended_glob
	local root=$1 kind=$2 want=$3
	local rows
	rows=$(dsl_gen "$root" "$kind")
	local r disp
	for r in ${(f)rows}; do
		[[ -n $r ]] || continue
		disp=${${r%%$'\t'*}//$'\e['[0-9;]##m/}
		[[ ${disp%% *} == $want ]] || continue
		reply=(${=disp})
		return 0
	done
	reply=()
	return 1
}

# dsl_preview <root> <kind> <name> -> REPLY is that row's preview field.
dsl_preview() {
	emulate -L zsh
	setopt extended_glob
	local root=$1 kind=$2 want=$3
	local rows
	rows=$(dsl_gen "$root" "$kind")
	local r disp
	for r in ${(f)rows}; do
		[[ -n $r ]] || continue
		disp=${${r%%$'\t'*}//$'\e['[0-9;]##m/}
		[[ ${disp%% *} == $want ]] || continue
		REPLY=${r##*$'\t'}
		return 0
	done
	REPLY=''
	return 1
}

# dsl_declare <declaration...> -> REPLY is stderr, DSL_ST the status hop_kind returned.
# - Used for the rejection tests, where the interesting output is the diagnostic and the status.
typeset -gi DSL_ST=0
dsl_declare() {
	emulate -L zsh
	local -a lines=("$@")
	HOP_HOPRC='' HOP_CONFIG="$HOP_FIX_NOCONFIG" \
		zsh -f -c "source ${(q)HOP_HOME}/hop.zsh || exit 97
${(F)lines}
exit \$?" >/dev/null 2>"$DSL_ERRFILE"
	DSL_ST=$?
	REPLY=$(<"$DSL_ERRFILE")
	return 0
}

# ---------------------------------------------------------------------------
# The repo every declaration below is pointed at.
# ---------------------------------------------------------------------------
fixture_repo dsl
typeset -g R=$REPLY

fixture_write 'README.md' '# dsl fixture'

# A --dirs family, one level and two levels deep, plus a .gitkeep-only child.
fixture_write 'units/alpha/notes.md' '# alpha'
fixture_write 'units/beta/notes.md' '# beta'
fixture_write 'units/hollow/.gitkeep'
fixture_write 'nested/first/one/notes.md' '# one'
fixture_write 'nested/second/two/notes.md' '# two'

# A --marker family with a deep layout, a short layout, a nested unit, and a depth-1 include.
fixture_write 'infra/teamx/live/eu-west-1/gateway/Stack.yaml' 'name: gateway'
fixture_write 'infra/teamx/live/eu-west-1/gateway/README.md' '# gateway'
fixture_write 'infra/teamx/live/eu-west-1/roles/reader/Stack.yaml' 'name: reader'
fixture_write 'infra/teamy/cache/Stack.yaml' 'name: cache'
fixture_write 'infra/shared/Stack.yaml' 'name: shared-include'

# A --files family whose segments map onto columns, with an extension to strip.
fixture_write 'envs/teamx/config/api/live.conf' 'a = 1'
fixture_write 'envs/teamx/config/api/test.conf' 'a = 2'
fixture_write 'envs/teamy/config/worker/live.conf' 'a = 3'

# Preview material: a 0-byte first candidate, a skippable generated file, and a real fallback.
fixture_write 'previews/blank/main.tf'
fixture_write 'previews/blank/second.tf' 'resource "null_resource" "a" {}'
fixture_write 'previews/generated/generated_provider.tf' 'provider "aws" {}'
fixture_write 'previews/generated/real.tf' 'resource "null_resource" "b" {}'
fixture_write 'previews/docsonly/README.md' '# docs only'
fixture_write 'previews/nothing/.gitkeep'

# Exclusion material: one file that should be dropped by an --exclude glob.
fixture_write 'apps/keep/app.yaml' 'kind: App'
fixture_write 'apps/keep/tests/probe.yaml' 'kind: Test'

fixture_commit 'dsl fixture'

# ---------------------------------------------------------------------------
# --dirs, including --depth.
# ---------------------------------------------------------------------------
t '--dirs emits one row per child directory'
dsl_kinds "hop_kind u --dirs 'units' --desc 'units'"
dsl_names "$R" u
assert_eq $'alpha\nbeta' "$REPLY" 'a .gitkeep-only child is empty and must not be a target'

t '--dirs at --depth 2 names parent/child, and never the container alone'
dsl_kinds "hop_kind n --dirs 'nested' --depth 2 --desc 'nested'"
dsl_names "$R" n
assert_eq $'first/one\nsecond/two' "$REPLY"

t '--dirs at depth 1 over the same tree returns the containers instead'
# This is the contrast that shows --depth is doing the work, not the glob.
dsl_kinds "hop_kind n --dirs 'nested' --desc 'nested'"
dsl_names "$R" n
assert_eq $'first\nsecond' "$REPLY"

t '--dirs takes a comma-separated list of bases'
dsl_kinds "hop_kind multi --dirs 'units,apps' --desc 'two bases'"
dsl_names "$R" multi
assert_contains "$REPLY" 'alpha'
assert_contains "$REPLY" 'keep'

t '--dirs on an absent base emits nothing, silently'
dsl_kinds "hop_kind gone --dirs 'no-such-family' --desc 'absent'"
dsl_names "$R" gone
assert_empty "$REPLY"
assert_empty "$DSL_ERRTEXT"

# ---------------------------------------------------------------------------
# --marker, layouts, and the path that matches none of them.
# ---------------------------------------------------------------------------
typeset STACK_DECL="hop_kind st --marker 'Stack.yaml' --under 'infra' \
	--layout 'scope,env,region,name...' --layout 'scope,name...' --desc 'stacks'"

t '--marker maps path segments onto columns through the matching layout'
dsl_kinds "$STACK_DECL"
dsl_cols "$R" st gateway
assert_eq 'gateway st teamx live eu-west-1' "${(j: :)reply}"

t 'a shorter layout catches a shorter path'
dsl_cols "$R" st cache
assert_eq 'cache st teamy - -' "${(j: :)reply}"

t 'layouts are tried LONGEST first, so a deep path cannot fall into a shallow layout'
# reader is five segments; only the four-column greedy layout can absorb it.
dsl_cols "$R" 'roles/reader'
dsl_cols "$R" st 'roles/reader'
assert_eq 'roles/reader st teamx live eu-west-1' "${(j: :)reply}"

t 'a trailing ... joins every remaining segment into the name'
dsl_names "$R" st
assert_contains "$REPLY" 'roles/reader'
assert_not_contains "$REPLY" $'\nroles\n' 'the intermediate dir must not become its own target'

t 'a path matching NO layout is not a target, which is what excludes a shared include'
dsl_names "$R" st
assert_not_contains "$REPLY" 'shared'
assert_eq $'gateway\nroles/reader\ncache' "$REPLY" 'only the three real stacks may appear'

t 'with no --layout at all the name is the basename and the scope its parent'
dsl_kinds "hop_kind st --marker 'Stack.yaml' --under 'infra' --desc 'stacks'"
dsl_cols "$R" st gateway
assert_eq 'gateway st teamx/live/eu-west-1 - -' "${(j: :)reply}"

t 'a marker with no --under scans the whole repo'
dsl_kinds "hop_kind any --marker 'Stack.yaml' --desc 'anywhere'"
dsl_names "$R" any
assert_contains "$REPLY" 'gateway' 'without --under the infra prefix stays in the path but still matches'

# ---------------------------------------------------------------------------
# --files, --strip-ext, --name-template and --trim.
# ---------------------------------------------------------------------------
t '--files maps segments onto columns, and - discards one'
dsl_kinds "hop_kind ec --files 'envs/*/config/*/*.conf' --under 'envs' --strip-ext \
	--layout 'scope,-,name,env' --desc 'env config'"
dsl_cols "$R" ec api
assert_eq 'api ec teamx live -' "${(j: :)reply}" 'the config segment is discarded by the - column'

t '--strip-ext runs before the layout, so the extension never lands in a column'
dsl_cols "$R" ec api
assert_not_contains "${(j: :)reply}" '.conf'

t 'without --strip-ext the extension stays in the column it landed in'
dsl_kinds "hop_kind ec --files 'envs/*/config/*/*.conf' --under 'envs' \
	--layout 'scope,-,name,env' --desc 'env config'"
dsl_cols "$R" api
dsl_cols "$R" ec api
assert_contains "${(j: :)reply}" '.conf'

t '--files rows point at the file, with its directory as the cd target'
dsl_kinds "hop_kind ec --files 'envs/*/config/*/*.conf' --under 'envs' --strip-ext \
	--layout 'scope,-,name,env' --desc 'env config'"
typeset ecrows
ecrows=$(dsl_gen "$R" ec)
assert_contains "$ecrows" "$R/envs/teamx/config/api	$R/envs/teamx/config/api/live.conf"

t '--name-template composes a name out of other columns'
dsl_kinds "hop_kind tpl --files 'envs/*/config/*/*.conf' --under 'envs' --strip-ext \
	--layout 'scope,-,name,env' --name-template '{scope}/{env}' --desc 'templated'"
dsl_names "$R" tpl
assert_contains "$REPLY" 'teamx/live'
assert_contains "$REPLY" 'teamy/live'

t '--trim strips a naming prefix off a column'
dsl_kinds "hop_kind tr --marker 'Stack.yaml' --under 'infra' \
	--layout 'scope,env,region,name...' --layout 'scope,name...' \
	--trim 'scope:team' --desc 'trimmed'"
dsl_cols "$R" tr gateway
assert_eq 'gateway tr x live eu-west-1' "${(j: :)reply}" 'the team prefix must come off the scope'

t '--name-template runs AFTER --trim, so it sees the trimmed value'
dsl_kinds "hop_kind trtpl --marker 'Stack.yaml' --under 'infra' \
	--layout 'scope,env,region,name...' --layout 'scope,name...' \
	--trim 'scope:team' --name-template '{scope}-{env}' --desc 'trim then template'"
dsl_names "$R" trtpl
assert_contains "$REPLY" 'x-live' 'a template seeing the untrimmed scope would read teamx-live'
assert_not_contains "$REPLY" 'teamx-live'

t '--exclude drops a matching path before it becomes a row'
dsl_kinds "hop_kind ap --files 'apps/**/*.yaml' --under 'apps' --strip-ext \
	--exclude '*/tests/*' --desc 'apps'"
dsl_names "$R" ap
assert_contains "$REPLY" 'app'
assert_not_contains "$REPLY" 'probe' 'the tests path should have been excluded'

t 'without --exclude that same path IS a row, so the option is doing the work'
dsl_kinds "hop_kind ap --files 'apps/**/*.yaml' --under 'apps' --strip-ext --desc 'apps'"
dsl_names "$R" ap
assert_contains "$REPLY" 'probe'

# ---------------------------------------------------------------------------
# --scope-literal.
# ---------------------------------------------------------------------------
t '--scope-literal overrides the scope column on every row'
dsl_kinds "hop_kind lit --dirs 'units' --scope-literal 'fixed' --desc 'literal scope'"
dsl_cols "$R" lit alpha
assert_eq 'fixed' "${reply[3]}"

# ---------------------------------------------------------------------------
# --preview, its zero-byte skip, and --preview-skip.
# ---------------------------------------------------------------------------
t '--preview walks its candidate list in order'
dsl_kinds "hop_kind pv --dirs 'previews' --preview 'README.md,main.tf' --desc 'previews'"
dsl_preview "$R" pv docsonly
assert_eq "$R/previews/docsonly/README.md" "$REPLY"

t 'a 0-byte candidate is SKIPPED, because an empty pane is worse than the next candidate'
dsl_kinds "hop_kind pv --dirs 'previews' --preview 'main.tf,second.tf' --desc 'previews'"
dsl_preview "$R" pv blank
assert_eq "$R/previews/blank/second.tf" "$REPLY" 'main.tf is 0 bytes and must lose'

t 'a glob candidate expands alphabetically and also skips 0-byte files'
dsl_kinds "hop_kind pv --dirs 'previews' --preview '*.tf' --desc 'previews'"
dsl_preview "$R" pv blank
assert_eq "$R/previews/blank/second.tf" "$REPLY"

t '--preview-skip removes a generated file from a glob match'
dsl_kinds "hop_kind pv --dirs 'previews' --preview '*.tf' \
	--preview-skip 'generated_*.tf' --desc 'previews'"
dsl_preview "$R" pv generated
assert_eq "$R/previews/generated/real.tf" "$REPLY" 'generated_provider.tf sorts first and must be skipped'

t 'without --preview-skip that generated file wins, so the option is doing the work'
dsl_kinds "hop_kind pv --dirs 'previews' --preview '*.tf' --desc 'previews'"
dsl_preview "$R" pv generated
assert_eq "$R/previews/generated/generated_provider.tf" "$REPLY"

t 'a directory with no candidate at all falls back to the directory itself'
dsl_kinds "hop_kind pv --dirs 'previews' --preview 'nothing-matches.txt' --desc 'previews'"
dsl_preview "$R" pv docsonly
assert_eq "$R/previews/docsonly" "$REPLY" 'a row must never carry an unreadable preview path'

# ---------------------------------------------------------------------------
# Redeclaring a kind.
# ---------------------------------------------------------------------------
t 'redeclaring a kind REPLACES it rather than adding a second entry'
dsl_kinds "hop_kind one --dirs 'units' --desc 'first'" \
	"hop_kind two --dirs 'apps' --desc 'second'" \
	"hop_kind one --dirs 'previews' --desc 'redeclared'"
typeset order
order=$(hop_probe 'print -rl -- "${_HOP_ALL_KINDS[@]}"')
assert_eq $'one\ntwo' "$order" 'a redeclared kind must not appear twice'

t 'and it keeps its ORIGINAL position in the menu order'
assert_eq 'one' "${${(f)order}[1]}" 'the redeclaration must not move it to the end'

t 'the redeclaration is what takes effect'
dsl_names "$R" one
assert_contains "$REPLY" 'docsonly' 'the second declaration pointed at previews'
assert_not_contains "$REPLY" 'alpha' 'the first declaration pointed at units and is gone'

t 'a redeclaration can also change the default flag'
dsl_kinds "hop_kind one --default --dirs 'units' --desc 'first'" \
	"hop_kind one --dirs 'units' --desc 'no longer default'"
typeset defs
defs=$(hop_probe '_hop_default_kinds')
assert_empty "$defs" 'dropping --default on redeclare must clear it, not merge with the old value'

# ---------------------------------------------------------------------------
# hop_kind rejects a bad declaration with status 2 and a diagnostic.
# ---------------------------------------------------------------------------
# A silent no-op here would look exactly like a working kind that matches nothing.

t 'hop_kind with no shape option is rejected'
dsl_declare "hop_kind broken --desc 'no shape'"
assert_eq 2 $DSL_ST
assert_contains "$REPLY" 'needs one of'

t 'hop_kind with an unknown option is rejected, and the option is named'
dsl_declare "hop_kind broken --dirs 'units' --frobnicate 'x'"
assert_eq 2 $DSL_ST
assert_contains "$REPLY" 'unknown option'
assert_contains "$REPLY" 'frobnicate'

t 'a value-taking option with no value is rejected rather than eating the next flag'
dsl_declare "hop_kind broken --dirs"
assert_eq 2 $DSL_ST
assert_contains "$REPLY" 'needs a value'

t '--fn naming an undefined function is rejected'
dsl_declare "hop_kind broken --fn _hop_no_such_function_anywhere"
assert_eq 2 $DSL_ST
assert_contains "$REPLY" 'not a defined function'

t '--fn naming a real function is accepted'
dsl_declare '_hop_provider_ok() { : }' "hop_kind fine --fn _hop_provider_ok --desc 'ok'"
assert_eq 0 $DSL_ST
assert_empty "$REPLY"

t 'a non-numeric --depth is rejected'
dsl_declare "hop_kind broken --dirs 'units' --depth two"
assert_eq 2 $DSL_ST
assert_contains "$REPLY" 'positive integer'

t 'a zero --depth is rejected, since depth 0 would name the base itself'
dsl_declare "hop_kind broken --dirs 'units' --depth 0"
assert_eq 2 $DSL_ST
assert_contains "$REPLY" 'positive integer'

t 'a missing kind name is rejected'
dsl_declare "hop_kind --dirs 'units'"
assert_eq 2 $DSL_ST
assert_contains "$REPLY" 'must be a kind name'

# ---------------------------------------------------------------------------
# hop_preset.
# ---------------------------------------------------------------------------
t 'hop_preset on an unknown name fails loudly rather than loading nothing'
dsl_declare "hop_preset definitely-not-a-preset"
assert_ne 0 $DSL_ST 'loading nothing looks exactly like a typo working'
assert_contains "$REPLY" 'no such preset'

t 'hop_preset loads the kinds a shipped preset declares'
dsl_declare "hop_preset puppet"
assert_eq 0 $DSL_ST
assert_empty "$REPLY"

# ---------------------------------------------------------------------------
# An unregistered kind.
# ---------------------------------------------------------------------------
t 'asking for a kind nobody declared says so on stderr'
dsl_kinds "hop_kind u --dirs 'units' --desc 'units'"
dsl_gen "$R" nosuchkind >/dev/null
assert_contains "$DSL_ERRTEXT" 'unknown kind: nosuchkind'

t 'a bare _hop_provider_<name> function still works without any registration'
# This fallback is what lets an opt-in .hoprc add a kind without touching the registry.
dsl_kinds "hop_kind u --dirs 'units' --desc 'units'" \
	'_hop_provider_loose() { _hop_row loose - - - handmade "$1" "$1/README.md" }'
typeset loose
loose=$(dsl_gen "$R" loose)
assert_contains "$loose" 'handmade'

fixture_config_reset
