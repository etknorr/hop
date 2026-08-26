#!/usr/bin/env zsh
# suite_providers: the kinds hop SHIPS, end to end, through the real registry.
#
# - Behaviour is asserted against SYNTHETIC fixture repos, never a checkout on this machine.
# - Every probe pins $HOP_CONFIG at a path that cannot exist, so hop.zsh loads the shipped presets.
# - Without that pin the suite would assert against whatever kinds the LOCAL config declares.
# - A real checkout is exercised only when $HOP_TEST_REPO names one, and skipped otherwise.
# - Nothing here can open a terminal: a kind is a pure function from a git repo to rows.
# - Interactive fzf and preview RENDERING are manual checks and live in ../SMOKE.md.
# - The DSL's own options get suite_dsl.zsh; this file is about the shipped declarations.

setopt local_options no_nomatch null_glob

# The kinds the repo ships presets for, in the order hop.zsh loads them.
typeset -ga SHIPPED=(tg mod helm serverless puppet backstage dir file)

# Which of those are on by default, which is a claim the presets make with --default.
typeset -ga SHIPPED_DEFAULT=(tg mod helm dir)

# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

# gen <root> <kind...> -> the raw rows on stdout, from a child shell with hop.zsh sourced.
gen() {
	emulate -L zsh
	local root=$1
	shift
	hop_probe "_hop_generate ${(q)root} ${(j: :)${(@q)@}}"
}

# gen_err <root> <kind...> -> REPLY is the stderr BYTE count, HOP_ERRTEXT the stderr itself.
# - Byte count, not the captured string: $(...) eats trailing newlines and would hide a lone "\n".
gen_err() {
	emulate -L zsh
	local root=$1
	shift
	gen "$root" "$@" >/dev/null 2>"$HOP_ERRFILE"
	REPLY=$(command wc -c <"$HOP_ERRFILE")
	REPLY=${REPLY//[[:space:]]/}
	HOP_ERRTEXT=$(<"$HOP_ERRFILE")
	return 0
}

# nrows <rows> -> REPLY is how many non-empty rows the text holds.
nrows() {
	emulate -L zsh
	local -a r=(${(f)1})
	REPLY=${#${r:#}}
}

# rf <row> <n> -> REPLY is the row's n-th TAB field: 1 display, 2 dir, 3 preview.
rf() {
	emulate -L zsh
	local -a f=("${(@ps:\t:)1}")
	REPLY=${f[$2]}
}

# cols_of <row> -> `reply` is the display column's five plain words: name kind scope env region.
# - IFS splitting, not (z): (z) tokenises `<root>` as a redirection and loses the name.
cols_of() {
	emulate -L zsh
	setopt extended_glob
	local disp=${${1%%$'\t'*}//$'\e['[0-9;]##m/}
	reply=(${=disp})
	return 0
}

# names_of <rows> -> REPLY is the name column of every row, one per line, in emission order.
# - A name never contains a space, so the first word of the padded display column is the whole name.
names_of() {
	emulate -L zsh
	setopt extended_glob
	local r disp
	local -a out=()
	for r in ${(f)1}; do
		[[ -n $r ]] || continue
		disp=${${r%%$'\t'*}//$'\e['[0-9;]##m/}
		out+=(${disp%% *})
	done
	REPLY=${(pj:\n:)out}
}

# row_for <rows> <name> -> REPLY is the row whose name column is exactly <name>; '' when absent.
row_for() {
	emulate -L zsh
	setopt extended_glob
	local rows=$1 want=$2 r disp
	REPLY=''
	for r in ${(f)rows}; do
		[[ -n $r ]] || continue
		disp=${${r%%$'\t'*}//$'\e['[0-9;]##m/}
		[[ ${disp%% *} == $want ]] || continue
		REPLY=$r
		return 0
	done
	return 1
}

# check_rows <label> <rows> [zero-ok] -> the five invariants every row of every kind must satisfy.
# - Each complaint list is asserted empty, so a failure names the offending paths, not just a count.
# - A 0-byte preview gets its own assertion: a 0-byte main.tf renders as a blank pane.
# - zero-ok is for `file` alone, whose row IS a file, so an empty tracked file is a valid answer.
# - The row set itself is asserted non-empty FIRST, because every loop below is over "${rows[@]}".
# - Measured: check_rows LABEL '' reported 4 passed and 0 failed, having examined nothing at all.
# - That mattered in the HOP_TEST_REPO block, whose own comment says row counts are never asserted.
# - Sabotage: _hop_generate returning immediately left 6 of the 7 real-checkout tests green.
check_rows() {
	emulate -L zsh
	local label=$1
	local -a rows=(${(f)2})
	rows=(${rows:#})

	t "${label}: the row set is not empty"
	assert_ge $#rows 1 'four invariants over zero rows all pass while examining nothing'

	local r dir prev
	local -a f
	local -a bad_fields=() bad_dir=() bad_prev=() zero_prev=()
	for r in "${rows[@]}"; do
		f=("${(@ps:\t:)r}")
		if (( $#f != 3 )) || [[ -z ${f[2]} || -z ${f[3]} ]]; then
			bad_fields+=("${#f} fields: ${r}")
			continue
		fi
		dir=${f[2]}
		prev=${f[3]}
		[[ -d $dir ]] || bad_dir+=("$dir")
		if [[ -d $prev ]]; then
			continue
		elif [[ -f $prev ]]; then
			[[ -s $prev ]] || zero_prev+=("$prev")
		else
			bad_prev+=("$prev")
		fi
	done

	t "${label}: every row has exactly 3 non-empty tab-separated fields"
	assert_empty "${(pj:\n:)bad_fields}"

	t "${label}: every dir field exists on disk"
	assert_empty "${(pj:\n:)bad_dir}"

	t "${label}: every preview field is an existing file or directory"
	assert_empty "${(pj:\n:)bad_prev}"

	if [[ ${3:-} == 'zero-ok' ]]; then
		skip "${label}: no preview resolves to a zero-byte file" 'an empty tracked file is a valid file target'
	else
		t "${label}: no preview resolves to a zero-byte file"
		assert_empty "${(pj:\n:)zero_prev}"
	fi
	return 0
}

typeset -g REPLY HOP_ERRTEXT HOP_ERRFILE
fixture_tmpdir errcap
HOP_ERRFILE="$REPLY/stderr"

# ---------------------------------------------------------------------------
# The registry, which is what --help, the `:` menu and the completions all read.
# ---------------------------------------------------------------------------
typeset registry
registry=$(hop_probe 'print -rl -- "${_HOP_ALL_KINDS[@]}"')

t 'the shipped presets register exactly the kinds the repo ships'
assert_eq "${(pj:\n:)SHIPPED}" "$registry" 'a preset was added or dropped without updating this list'

t 'every registered kind declares both a shape and a description'
typeset shapes
shapes=$(hop_probe 'for k in "${_HOP_ALL_KINDS[@]}"; do
	print -r -- "${k} ${_HOP_K_SHAPE[$k]:-MISSING} ${${_HOP_K_DESC[$k]:+ok}:-MISSING}"
done')
assert_not_contains "$shapes" 'MISSING' 'a kind with no shape or no description is half-declared'

t 'the default kind set comes from --default, not from a hardcoded list'
typeset defaults
defaults=$(hop_probe '_hop_default_kinds')
assert_eq "${(j: :)SHIPPED_DEFAULT}" "$defaults"

# The guard on hermeticity itself: were HOP_CONFIG ignored, no kind assertion below would mean anything.
t 'a fixture config REPLACES the shipped presets, so this suite is hermetic'
fixture_config 'hop_kind solo --dirs "things" --desc "only kind"'
typeset solo
solo=$(hop_probe 'print -rl -- "${_HOP_ALL_KINDS[@]}"')
assert_eq 'solo' "$solo" 'HOP_CONFIG is not honoured, so this suite would be testing the local machine'
fixture_config_reset

t 'and clearing the fixture config brings the shipped presets back'
registry=$(hop_probe 'print -rl -- "${_HOP_ALL_KINDS[@]}"')
assert_eq "${(pj:\n:)SHIPPED}" "$registry"

# ---------------------------------------------------------------------------
# A repo with no config at all, which is what makes hop usable in a fresh clone.
# ---------------------------------------------------------------------------
# Only README.md is tracked, so every family a kind probes for is absent.
fixture_repo bare
typeset -g BARE=$REPLY
fixture_write 'README.md' '# bare repo'
fixture_commit 'bare'

typeset k rows
for k in tg mod helm serverless puppet backstage; do
	rows=$(gen "$BARE" "$k")
	nrows "$rows"
	t "${k}: emits zero rows when its family is absent"
	assert_eq 0 $REPLY "${k} invented a target in a repo that has none"
	gen_err "$BARE" "$k"
	t "${k}: emits zero stderr bytes when its family is absent"
	assert_eq 0 $REPLY "${HOP_ERRTEXT:-stderr was not empty}"
done

# dir and file have no family to probe for: the repo itself is the family.
t 'dir: a config-free repo yields exactly the <root> row'
rows=$(gen "$BARE" dir)
nrows "$rows"
assert_eq 1 $REPLY 'dir emitted more than the root row in a repo with no tracked directories'
names_of "$rows"
assert_eq '<root>' "$REPLY"

t 'file: a config-free repo yields exactly its one tracked file'
rows=$(gen "$BARE" file)
nrows "$rows"
assert_eq 1 $REPLY
names_of "$rows"
assert_eq 'README.md' "$REPLY"

t 'every shipped kind together emits zero stderr bytes in a config-free repo'
gen_err "$BARE" "${SHIPPED[@]}"
assert_eq 0 $REPLY "${HOP_ERRTEXT:-stderr was not empty}"

# ---------------------------------------------------------------------------
# One synthetic repo holding every family the shipped presets know about.
# ---------------------------------------------------------------------------
# Every shape below is one a real repo exhibits, reduced to the smallest form that shows it.
# - All names are invented. Nothing here is copied from any real checkout.
fixture_repo allfamilies
typeset -g REPO=$REPLY

fixture_write 'README.md' '# every family'

# tg: the deep layout, the short layout, a nested unit, a shared include, and a .tf with no unit.
fixture_write 'terraform/platform/production/us-west-2/network/terragrunt.hcl' 'include {}'
fixture_write 'terraform/platform/production/us-west-2/network/main.tf' 'resource "null_resource" "a" {}'
fixture_write 'terraform/platform/production/us-west-2/access/reader/terragrunt.hcl' 'include {}'
fixture_write 'terraform/platform/production/us-west-2/access/reader/README.md' '# nested unit'
fixture_write 'terraform/sandbox/dns/terragrunt.hcl' 'include {}'
fixture_write 'terraform/sandbox/dns/main.tf' 'resource "null_resource" "b" {}'
# A shared include sits at depth 1, matches NEITHER layout, and must not become a target.
fixture_write 'terraform/common/terragrunt.hcl' 'include {}'
fixture_write 'terraform/platform/production/us-west-2/orphan/main.tf' 'resource "null_resource" "c" {}'

# The 0-byte main.tf case, which previewed as an empty pane before the size test went in.
fixture_write 'terraform/platform/production/us-west-2/blank/terragrunt.hcl' 'include {}'
fixture_write 'terraform/platform/production/us-west-2/blank/main.tf'
fixture_write 'terraform/platform/production/us-west-2/blank/queue.tf' 'resource "null_resource" "d" {}'

# provider_aws.tf sorts before queue.tf, so this only passes if --preview-skip is honoured.
fixture_write 'terraform/platform/production/us-west-2/generated/terragrunt.hcl' 'include {}'
fixture_write 'terraform/platform/production/us-west-2/generated/provider_aws.tf' 'provider "aws" {}'
fixture_write 'terraform/platform/production/us-west-2/generated/queue.tf' 'resource "null_resource" "e" {}'

# mod: two levels down, which --depth 2 finds and a one-level listing would miss entirely.
fixture_write 'terraform/modules/cloud/network/main.tf' 'variable "x" {}'
fixture_write 'terraform/modules/internal/logging/README.md' '# logging module'

# helm: a .gitkeep-only dir, a chart one level deeper, a file-per-app family, and a tests dir.
fixture_write 'kubernetes/values/widget/values.yaml' 'image: widget'
fixture_write 'kubernetes/values/placeholder/.gitkeep'
fixture_write 'kubernetes/charts/mychart/Chart.yaml' 'name: mychart'
fixture_write 'kubernetes/charts/scaffolds/base/Chart.yaml' 'name: base'
fixture_write 'kubernetes/services/group/app.yaml' 'kind: Application'
fixture_write 'kubernetes/services/group/tests/probe.yaml' 'kind: Test'
fixture_write 'services/gizmo/Chart.yaml' 'name: gizmo'
fixture_write 'charts/sprocket/Chart.yaml' 'name: sprocket'
fixture_write 'cluster-apps/charts/cluster-apps/templates/frontdoor.yaml' 'kind: Application'

# A 0-byte values.yaml beside a real README, a shape real repos genuinely have.
# - values.yaml comes earlier in the helm chain than README.md, so only a size test can skip it.
fixture_write 'kubernetes/values/blankvals/values.yaml'
fixture_write 'kubernetes/values/blankvals/README.md' '# blank vals'

# puppet: a top-level modules/, which is unrelated to terraform/modules.
fixture_write 'modules/basetools/README.md' '# basetools'

# serverless: one Serverless Framework unit, one SAM unit, and a family-root README.
fixture_write 'serverless/README.md' '# serverless'
fixture_write 'serverless/collector/serverless.yml' 'service: collector'
fixture_write 'serverless/uploader/template.yaml' 'Transform: x'

# backstage: one entity whose metadata.name differs from its filename, one with no metadata.
fixture_write 'backstage/comp-a.yaml' 'apiVersion: v1' 'metadata:' '  name: real-name' 'spec:' '  owner: nobody'
fixture_write 'backstage/comp-b.yaml' 'apiVersion: v1' 'spec: {}'

# dir: the two tracked top-level dirs that are never destinations.
fixture_write 'target/thing.jar' 'jar bytes'
fixture_write 'tmp/.gitkeep'

fixture_commit 'every family'

# ---------------------------------------------------------------------------
# The row contract, asserted for every shipped kind against the fixture.
# ---------------------------------------------------------------------------
# Counts are exact here because the repo is synthetic: nothing can move under the suite.
typeset -A WANT_ROWS=(
	tg 5 mod 2 helm 8 serverless 2 puppet 1 backstage 2 dir 9
)
WANT_ROWS[file]=$(_hop_fix_git -C "$REPO" ls-files | command wc -l)
WANT_ROWS[file]=${WANT_ROWS[file]//[[:space:]]/}

typeset -A ROWS=()
for k in "${SHIPPED[@]}"; do
	ROWS[$k]=$(gen "$REPO" "$k")
	nrows "${ROWS[$k]}"
	t "${k}: emits the expected number of rows from the fixture"
	assert_eq ${WANT_ROWS[$k]} $REPLY
	if [[ $k == file ]]; then
		check_rows "$k" "${ROWS[$k]}" zero-ok
	else
		check_rows "$k" "${ROWS[$k]}"
	fi
	gen_err "$REPO" "$k"
	t "${k}: emits zero stderr bytes from the fixture"
	assert_eq 0 $REPLY "${HOP_ERRTEXT:-stderr was not empty}"
done

# ---------------------------------------------------------------------------
# tg, the --marker shape with two layouts.
# ---------------------------------------------------------------------------
typeset tg=${ROWS[tg]}
typeset -a reply

t 'tg: the four-segment layout fills scope, env and region'
row_for "$tg" network
assert_nonempty "$REPLY" 'no row named network'
cols_of "$REPLY"
assert_eq 'network' "${reply[1]}"
assert_eq 'tg' "${reply[2]}"
assert_eq 'platform' "${reply[3]}"
assert_eq 'us-west-2' "${reply[5]}"

t 'tg: an env wider than its column is clipped with an ellipsis, never overflowed'
# _HOP_W_ENV is 9 and `production` is 10, so this row is the clipping case.
# - Overflow rather than clipping is what shifted every later column out of alignment.
assert_eq 'producti…' "${reply[4]}" 'the env column must clip to its declared width'

t 'tg: the row still carries the FULL path, so clipping is display-only'
row_for "$tg" network
rf "$REPLY" 2
assert_eq "$REPO/terraform/platform/production/us-west-2/network" "$REPLY"

t 'tg: the two-segment layout renders env and region as -'
row_for "$tg" dns
assert_nonempty "$REPLY" 'no row named dns'
cols_of "$REPLY"
assert_eq 'dns tg sandbox - -' "${(j: :)reply}"

t 'tg: a trailing ... renders a nested unit as parent/child'
names_of "$tg"
assert_contains "$REPLY" 'access/reader'
assert_not_contains "$REPLY" $'\naccess\n' 'the parent dir must not become a target of its own'

t 'tg: a shared include at depth 1 matches no layout and is excluded'
names_of "$tg"
assert_not_contains "$REPLY" 'common'
assert_not_contains "$tg" 'terraform/common'

t 'tg: a dir with a .tf but no terragrunt.hcl is not a target'
names_of "$tg"
assert_not_contains "$REPLY" 'orphan'

t 'tg: a 0-byte main.tf loses to a real .tf beside it'
row_for "$tg" blank
assert_nonempty "$REPLY" 'no row named blank'
rf "$REPLY" 3
assert_eq "$REPO/terraform/platform/production/us-west-2/blank/queue.tf" "$REPLY"

t 'tg: a --preview-skip pattern loses to a real .tf that sorts after it'
row_for "$tg" generated
assert_nonempty "$REPLY" 'no row named generated'
rf "$REPLY" 3
assert_eq "$REPO/terraform/platform/production/us-west-2/generated/queue.tf" "$REPLY"

t 'tg: a unit with no .tf at all falls back to its terragrunt.hcl'
row_for "$tg" 'access/reader'
rf "$REPLY" 3
assert_eq "$REPO/terraform/platform/production/us-west-2/access/reader/terragrunt.hcl" "$REPLY"

# ---------------------------------------------------------------------------
# mod, the --dirs shape at --depth 2.
# ---------------------------------------------------------------------------
typeset mod=${ROWS[mod]}

t 'mod: --depth 2 names a module namespace/module, never the namespace alone'
names_of "$mod"
assert_eq $'cloud/network\ninternal/logging' "$REPLY"

t 'mod: a module with no .tf falls back to its README'
row_for "$mod" 'internal/logging'
rf "$REPLY" 3
assert_eq "$REPO/terraform/modules/internal/logging/README.md" "$REPLY"

# ---------------------------------------------------------------------------
# helm, the --fn escape hatch, which spans four different family shapes.
# ---------------------------------------------------------------------------
typeset helm=${ROWS[helm]}

t 'helm: a dir whose only tracked file is .gitkeep is skipped'
names_of "$helm"
assert_not_contains "$REPLY" 'placeholder'

t 'helm: a chart one level deeper renders as parent/child'
names_of "$helm"
assert_contains "$REPLY" 'scaffolds/base'
assert_not_contains "$REPLY" $'\nscaffolds\n' 'the scaffolds container is not itself a chart'

t 'helm: the file-per-app family is one row per FILE, with the dir as the cd target'
row_for "$helm" 'group/app'
assert_nonempty "$REPLY" 'no row named group/app'
rf "$REPLY" 2
assert_eq "$REPO/kubernetes/services/group" "$REPLY"
row_for "$helm" 'group/app'
rf "$REPLY" 3
assert_eq "$REPO/kubernetes/services/group/app.yaml" "$REPLY"

t 'helm: a tests/ dir under the app family is not an app'
assert_not_contains "$helm" 'group/tests'

t 'helm: a 0-byte values.yaml loses to a real file beside it'
row_for "$helm" blankvals
assert_nonempty "$REPLY" 'no row named blankvals'
rf "$REPLY" 3
assert_eq "$REPO/kubernetes/values/blankvals/README.md" "$REPLY" \
	'a 0-byte candidate must lose to the next one in the chain'

t 'helm: the one-chart-plus-templates family emits one row per template'
row_for "$helm" frontdoor
assert_nonempty "$REPLY" 'no row named frontdoor'
rf "$REPLY" 3
assert_eq "$REPO/cluster-apps/charts/cluster-apps/templates/frontdoor.yaml" "$REPLY"

# ---------------------------------------------------------------------------
# serverless and puppet, both plain --dirs kinds with their own preview chains.
# ---------------------------------------------------------------------------
typeset serverless=${ROWS[serverless]}

t 'serverless: a README at the family root is a file, not a unit'
names_of "$serverless"
assert_eq $'collector\nuploader' "$REPLY"

t 'serverless: a unit with no serverless.yml falls through to template.yaml'
row_for "$serverless" uploader
rf "$REPLY" 3
assert_eq "$REPO/serverless/uploader/template.yaml" "$REPLY"

t 'puppet: top-level modules/ is the family, not terraform/modules'
row_for "${ROWS[puppet]}" basetools
assert_nonempty "$REPLY" 'no row named basetools'
rf "$REPLY" 2
assert_eq "$REPO/modules/basetools" "$REPLY"
assert_not_contains "${ROWS[puppet]}" 'terraform/modules'

# ---------------------------------------------------------------------------
# backstage, the --files shape with a --name-fn.
# ---------------------------------------------------------------------------
typeset backstage=${ROWS[backstage]}

t 'backstage: --name-fn takes the name from metadata.name, not the filename'
names_of "$backstage"
assert_contains "$REPLY" 'real-name'
assert_not_contains "$REPLY" 'comp-a'

t 'backstage: a file with no metadata.name falls back to its basename'
names_of "$backstage"
assert_contains "$REPLY" 'comp-b'

t 'backstage: a key nested under something other than metadata cannot win'
assert_not_contains "$backstage" 'nobody'

t 'backstage: dir is the containing dir and preview is the file'
row_for "$backstage" real-name
rf "$REPLY" 2
assert_eq "$REPO/backstage" "$REPLY"
row_for "$backstage" real-name
rf "$REPLY" 3
assert_eq "$REPO/backstage/comp-a.yaml" "$REPLY"

t 'backstage: --scope-literal puts the same scope on every row'
row_for "$backstage" real-name
cols_of "$REPLY"
assert_eq 'backstage' "${reply[3]}"

# ---------------------------------------------------------------------------
# dir.
# ---------------------------------------------------------------------------
typeset dirrows=${ROWS[dir]}

t 'dir: the root row comes first and previews the README'
typeset firstrow=${${(f)dirrows}[1]}
cols_of "$firstrow"
assert_eq '<root> dir - - -' "${(j: :)reply}"
rf "$firstrow" 2
assert_eq "$REPO" "$REPLY"
rf "$firstrow" 3
assert_eq "$REPO/README.md" "$REPLY"

t 'dir: build output and scratch space are not destinations'
names_of "$dirrows"
assert_not_contains "$REPLY" 'target'
assert_not_contains "$REPLY" 'tmp'

t 'dir: every tracked top-level directory is offered'
names_of "$dirrows"
typeset -a want=(backstage charts cluster-apps kubernetes modules serverless services terraform)
typeset d
for d in "${want[@]}"; do
	assert_contains "$REPLY" "$d"
done

# ---------------------------------------------------------------------------
# file.
# ---------------------------------------------------------------------------
typeset filerows=${ROWS[file]}

t 'file: dir is the containing directory and preview is the file itself'
row_for "$filerows" 'comp-a.yaml'
assert_nonempty "$REPLY" 'no row for backstage/comp-a.yaml'
rf "$REPLY" 2
assert_eq "$REPO/backstage" "$REPLY"
row_for "$filerows" 'comp-a.yaml'
rf "$REPLY" 3
assert_eq "$REPO/backstage/comp-a.yaml" "$REPLY"

t 'file: a root-level file has the repo root as its dir'
row_for "$filerows" 'README.md'
rf "$REPLY" 2
assert_eq "$REPO" "$REPLY"

t 'file: even a 0-byte tracked file is offered, because the question is "which file"'
assert_contains "$filerows" "$REPO/kubernetes/values/blankvals/values.yaml"

# ---------------------------------------------------------------------------
# .hoprc is OPT-IN, because sourcing it runs code from whatever repo you happen to be in.
# ---------------------------------------------------------------------------
# The fixture .hoprc does two observable things: it declares a kind and it touches a sentinel.
# - So "not sourced" and "sourced" are each provable, rather than inferred from an empty row set.

fixture_repo hoprc
typeset -g HOPRC_REPO=$REPLY
typeset -g HOPRC_SENT="$HOPRC_REPO/.hoprc-ran"
typeset -g HOPRC_OUT="${HOP_ERRFILE:h}/hoprc-out"

fixture_write 'README.md' '# hoprc repo'
fixture_write '.hoprc' \
	"command touch ${(q)HOPRC_SENT}" \
	'_hop_provider_extra() { _hop_row extra - - - injected "$1" "$1/README.md" }'
fixture_commit 'hoprc'

# hoprc_gen [VAR=VALUE...] -> REPLY is the rows, HOP_ERRTEXT the stderr, sentinel reset first.
# - This bypasses hop_probe on purpose: hop_probe forces HOP_HOPRC empty for every other test.
# - It still takes the full pin set, or an exported HOP_HOPRC=1 opts the security test IN and it fails.
# - The caller's own pairs come last, because `env A=1 A=2` keeps the last one and that is the override.
# - No $(...) capture, because a subshell would throw away the HOP_ERRTEXT this sets.
hoprc_gen() {
	emulate -L zsh
	command rm -f -- "$HOPRC_SENT"
	local -a pins=("${(@f)$(fixture_pin_pairs "$HOP_FIX_HOME")}")
	hop_bound 20 env "${pins[@]}" "$@" \
		zsh -f -c "source ${(q)HOP_HOME}/hop.zsh || exit 97
_hop_generate ${(q)HOPRC_REPO} extra" >"$HOPRC_OUT" 2>"$HOP_ERRFILE"
	REPLY=$(<"$HOPRC_OUT")
	HOP_ERRTEXT=$(<"$HOP_ERRFILE")
	return 0
}

t 'a repo-root .hoprc is not sourced when HOP_HOPRC is unset'
hoprc_gen
assert_empty "$REPLY" 'a .hoprc kind must not exist unless the user opted in'
assert_status 1 test -e "$HOPRC_SENT"

t 'the unopted kind is genuinely undefined, not silently empty'
assert_contains "$HOP_ERRTEXT" 'unknown kind: extra' 'no kind means hop says so'

t 'HOP_HOPRC=1 sources .hoprc, so the opt-in really is the only difference'
hoprc_gen HOP_HOPRC=1
assert_contains "$REPLY" 'injected' 'the .hoprc kind should now be defined'
assert_file "$HOPRC_SENT" 'without this the guard test above proves nothing'
assert_empty "$HOP_ERRTEXT"

# ---------------------------------------------------------------------------
# The git enumeration invariant, read straight out of the source.
# ---------------------------------------------------------------------------
# A bare '*' crosses '/' in git, and _hop_ls is the one place that injects :(glob) to stop it.
# - Scanning for un-prefixed pathspec LITERALS is deliberately no longer the check here.
# - A preset's --files value carries no prefix by design, so that scan would flag correct code.
# - The durable invariant is instead that the funnel has no bypass at all.

# scan_ls_callsites <file...> -> `reply` is every line running git ls-files outside _hop_ls.
# - The error path inside _hop_ls names `git ls-files` in a message, which is prose, not a call site.
scan_ls_callsites() {
	emulate -L zsh
	setopt extended_glob
	local src line code
	reply=()
	for src in "$@"; do
		[[ -r $src ]] || continue
		for line in ${(f)"$(<$src)"}; do
			code=${line##[[:space:]]##}
			[[ $code == '#'* ]] && continue
			[[ $code == *ls-files* ]] || continue
			[[ $code == (print|printf|echo)[[:space:]]* ]] && continue
			[[ $code == *'"${specs[@]}"'* ]] && continue
			reply+=("${src:t}: ${code}")
		done
	done
	return 0
}

fixture_sources enum
typeset -a ENUMSRC=("${reply[@]}")

# This runs FIRST, and no longer names a number: the old floor of 10 sat well below the real count.
t 'every component of the enumeration-source list found files'
assert_empty "$REPLY" 'a mistyped glob would make the ls-files funnel check vacuous'

t 'only _hop_ls talks to git ls-files, across lib, bin and presets'
scan_ls_callsites "${ENUMSRC[@]}"
assert_empty "${(pj:\n:)reply}" 'a direct git ls-files bypasses the :(glob) and the NUL handling'

t '_hop_ls adds :(glob), so a * in a magic-free spec cannot cross /'
typeset four
four=$(hop_probe "local -a reply; _hop_ls ${(q)REPO} 'terraform/*/*/terragrunt.hcl'; print -rl -- \${reply[@]}")
assert_contains "$four" 'terraform/sandbox/dns/terragrunt.hcl'
assert_not_contains "$four" 'us-west-2/network/terragrunt.hcl' 'a bare * crossed / and swept in the deep units'

t '_hop_ls still matches at the depth a spec actually names'
typeset five
five=$(hop_probe "local -a reply; _hop_ls ${(q)REPO} 'terraform/*/*/*/*/terragrunt.hcl'; print -rl -- \${reply[@]}")
assert_contains "$five" 'terraform/platform/production/us-west-2/network/terragrunt.hcl'
assert_not_contains "$five" 'sandbox/dns/terragrunt.hcl'

# ---------------------------------------------------------------------------
# A real checkout, only when one is named. No path here may be hardcoded.
# ---------------------------------------------------------------------------
# This answers one question: do the shipped kinds still hold their contract on real data.
# - Row COUNTS are never asserted, because $HOP_TEST_REPO could legitimately be any repo.
# - Set HOP_TEST_REPO=/path/to/a/checkout to turn these on.
typeset -g TESTREPO=${HOP_TEST_REPO:-}

if [[ -n $TESTREPO && -d $TESTREPO/.git ]]; then
	t 'real checkout: enumerating every shipped kind is silent on stderr'
	gen_err "$TESTREPO" "${SHIPPED[@]}"
	assert_eq 0 $REPLY "${HOP_ERRTEXT:-stderr was not empty}"

	t 'real checkout: the dir kind always finds at least the root row'
	rows=$(gen "$TESTREPO" dir)
	nrows "$rows"
	assert_ge $REPLY 1

	# The row contract on real data, which is where the 0-byte preview turned up in the first place.
	# - file is left out on purpose: tens of thousands of stat calls buys nothing the others miss.
	check_rows 'real checkout' "$(gen "$TESTREPO" tg mod helm serverless puppet backstage dir)"

	t 'real checkout: every row points inside the repo it was asked about'
	rows=$(gen "$TESTREPO" tg mod helm serverless puppet backstage dir)
	# The loop below is over these rows, so zero of them would satisfy the assertion having read nothing.
	assert_nonempty "$rows" 'no rows at all makes the escape check vacuous, not clean'
	typeset bad='' rowdir r
	for r in ${(f)rows}; do
		[[ -n $r ]] || continue
		rowdir=${${r#*$'\t'}%$'\t'*}
		[[ $rowdir == $TESTREPO || $rowdir == $TESTREPO/* ]] || bad=$rowdir
	done
	assert_empty "$bad" 'a row escaped the repo root it was generated from'
else
	skip 'real checkout: the shipped kinds hold their contract on real data' \
		'set HOP_TEST_REPO to a git checkout to enable these'
fi

# ---------------------------------------------------------------------------
# What this suite deliberately does not do.
# ---------------------------------------------------------------------------
skip 'a preview pane actually renders its file' 'needs a real terminal; see SMOKE.md section 3'
skip 'the : kind picker adds a kind and the count goes up' 'needs a real terminal; see SMOKE.md section 3'
