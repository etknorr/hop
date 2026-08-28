#!/usr/bin/env zsh
# suite_workspaces: lib/workspaces.zsh, the level ABOVE a repo.
# - The config file lives in the user's dotfiles, so a parser that EVALS it is code execution.
# - Every payload here tries to create a sentinel file, and the test is that the sentinel is absent.
# - One control test evals a payload of the same shape, so a real breach is provably detectable.
# - Only providers.zsh and workspaces.zsh are sourced, so an edit to lib/ui.zsh cannot mask a failure.
# - Nothing here can start fzf: no picker is ever called, and no code path reaches one.

# ---------------------------------------------------------------------------
# Probe plumbing.
# ---------------------------------------------------------------------------

typeset -g WS_OUT='' WS_ERR=''
typeset -gi WS_ST=0

# ws_probe [VAR=VALUE...] -- <zsh-code> -> run the code in a fresh shell with the two libs loaded.
# - Every variable the parser reads is unset first, so a test declares its whole environment.
# - The assignments come before the source lines, because workspaces.zsh reads its default at load.
# - The code arrives as a variable, so a `$` inside it is never expanded by THIS shell.
# - HOME and XDG_CONFIG_HOME are PINNED, not unset, and this is load-bearing rather than tidiness.
# - The config path defaults to ${XDG_CONFIG_HOME:-$HOME/.config}/hop/workspaces, a real file here.
# - Leaving either one alone let a probe read the actual user's dotfiles and pass only on one laptop.
ws_probe() {
	emulate -L zsh
	local -a pre=("export HOME=${(q)WS_FAKE_HOME}" "export XDG_CONFIG_HOME=${(q)WS_FAKE_HOME}/.config")
	while (( $# )) && [[ $1 != '--' ]]; do
		pre+=("export ${(q)1}")
		shift
	done
	shift
	local code=$1 setup=${(F)pre}
	zsh -f -c "unset HOP_WORKSPACES HOP_WORKSPACES_FILE HOP_HOME
${setup}
source ${(q)HOP_HOME}/lib/providers.zsh || exit 97
source ${(q)HOP_HOME}/lib/workspaces.zsh || exit 97
${code}"
}

# ws_run [VAR=VALUE...] -- <zsh-code> -> WS_OUT, WS_ERR and WS_ST from one probe.
# - stderr is captured rather than printed, because "skipped silently" is half of the spec.
# - Letting it through would also inject stray lines into the runner's own report.
ws_run() {
	emulate -L zsh
	WS_OUT=$(ws_probe "$@" 2>"$WS_TMP/stderr")
	WS_ST=$?
	WS_ERR=$(<"$WS_TMP/stderr")
	return 0
}

# The parse probe re-raises _hop_ws_parse's own status, so WS_ST is the function's answer.
typeset -g WS_PARSE_CODE='_hop_ws_parse
integer st=$?
print -rl -- "${reply[@]}"
exit $st'

# ws_parse <config-file> [VAR=VALUE...] -> parse that file into WS_OUT, WS_ERR and WS_ST.
ws_parse() {
	emulate -L zsh
	local f=$1
	shift
	ws_run "HOP_WORKSPACES_FILE=${f}" "$@" -- "$WS_PARSE_CODE"
}

# ws_cfg <label> <content> -> REPLY is a config file holding exactly <content>, byte for byte.
# - printf, not print, so a test can leave the trailing newline off deliberately.
ws_cfg() {
	emulate -L zsh
	REPLY="$WS_TMP/cfg-$1"
	printf '%s' "$2" > "$REPLY"
}

# ws_entry <name> <path> -> REPLY is the exact `name<TAB>path` line _hop_ws_parse emits.
ws_entry() {
	emulate -L zsh
	REPLY="$1"$'\t'"$2"
}

# ws_dirs <rows> -> the second TAB field of every row, which is the directory hop would cd to.
ws_dirs() {
	emulate -L zsh
	local -a out=()
	local row
	for row in "${(@f)1}"; do
		[[ -n $row ]] || continue
		out+=("${${row#*$'\t'}%$'\t'*}")
	done
	print -rl -- "${out[@]}"
}

# ws_plain <text> -> the same text with every ANSI escape removed, so an assert reads clearly.
ws_plain() {
	emulate -L zsh
	setopt local_options extended_glob
	print -r -- "${1//$'\e'\[[0-9;]##m/}"
}

# ws_sentinels -> the name of every sentinel file a payload managed to create.
# - An empty result is the whole security claim of this suite.
ws_sentinels() {
	emulate -L zsh
	setopt local_options null_glob
	local -a hit=("$WS_SENT"/*(N))
	print -rl -- "${hit[@]:t}"
}

# ---------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------

typeset REPLY
fixture_tmpdir ws || return 1
typeset -g WS_TMP=$REPLY

typeset -g WS_SENT="$WS_TMP/sentinels"
typeset -g WS_CTL="$WS_TMP/control"
typeset -g WS_OK="$WS_TMP/ok"
typeset -g WS_HOME="$WS_TMP/home"
typeset -g WS_BARE_HOME="$WS_TMP/bare-home"
typeset -g WS_NEST="$WS_TMP/nest"
typeset -g WS_WEIRD="$WS_TMP/weird = name"
typeset -g WS_HASH="$WS_TMP/has#hash"
typeset -g WS_TILDE="$WS_TMP/tilde~mid"
typeset -g WS_REPOS="$WS_TMP/repos"
typeset -g WS_TWO="$WS_TMP/two-repos"
typeset -g WS_ONE="$WS_TMP/one-repo"
typeset -g WS_NONE="$WS_TMP/no-repos"
typeset -g WS_NOPERM="$WS_TMP/noperm"
typeset -g WS_AFILE="$WS_TMP/a-file"
typeset -g WS_DANGLE="$WS_TMP/dangling"
typeset -g WS_GONE="$WS_TMP/not-created"

# The HOME every probe runs under, so no default can reach the real user's dotfiles.
# - Deliberately holds no .config/hop/workspaces, which is what makes "missing file" testable.
typeset -g WS_FAKE_HOME="$WS_TMP/fake-home"

# The default set workspaces.zsh falls back to with no config, relative to whatever HOME is.
typeset -ga WS_DEFAULT_DIRS=(src code projects dev work)

mkdir -p -- \
	"$WS_SENT" "$WS_CTL" "$WS_OK" "$WS_FAKE_HOME/.config" \
	"$WS_HOME/inhome" "$WS_HOME/code" "$WS_BARE_HOME" \
	"$WS_NEST/deep/inner" "$WS_NEST/beside" "$WS_NEST/deep-elsewhere" \
	"$WS_WEIRD" "$WS_HASH" "$WS_TILDE" \
	"$WS_REPOS/plain" "$WS_REPOS/fake-repo/.git" "$WS_REPOS/deep/inner/.git" \
	"$WS_TWO/first/.git" "$WS_TWO/second/.git" \
	"$WS_ONE/only/.git" "$WS_NONE/not-a-repo" \
	"$WS_NOPERM"
: > "$WS_AFILE"
ln -s "$WS_TMP/nowhere-at-all" "$WS_DANGLE"

# A real worktree, because in one of those `.git` is a FILE and a -d test would miss it.
# - The parent repo is kept OUT of $WS_REPOS so it cannot be counted as a repo there.
typeset -g WS_MAIN=''
typeset -gi WS_WT_OK=0
if fixture_repo wsmain; then
	WS_MAIN=$REPLY
	fixture_write 'seed.txt' 'seed'
	fixture_commit 'seed' >/dev/null 2>&1
	if _hop_fix_git -C "$WS_MAIN" worktree add -q -b hop-ws-test "$WS_REPOS/wt" >/dev/null 2>&1; then
		WS_WT_OK=1
	fi
fi

# ---------------------------------------------------------------------------
# Security: a config file is data, never code.
# ---------------------------------------------------------------------------
# Each payload names its own sentinel, so a failure says WHICH metacharacter got through.
# - The last two use only a redirection and a builtin, which fire even when $PATH is empty.
# - That matters because `local path` inside _hop_ws_parse blanks $PATH for the whole function.
typeset -ga WS_SENT_NAMES=(
	backtick dollar-paren semicolon and pipe continuation newline-escape
	redirect builtin-subst
)

typeset -a WS_PAYLOADS=(
	"\`touch ${WS_SENT}/backtick\`"
	"\$(touch ${WS_SENT}/dollar-paren)"
	"semi = ${WS_OK}; touch ${WS_SENT}/semicolon"
	"andand = ${WS_OK} && touch ${WS_SENT}/and"
	"piped = ${WS_OK} | touch ${WS_SENT}/pipe"
	"trailing = ${WS_OK}\\"
	"touch ${WS_SENT}/continuation"
	"newline = ${WS_OK}\\ntouch ${WS_SENT}/newline-escape"
	"redirected = ${WS_OK} > ${WS_SENT}/redirect"
	"builtin = \$(print -rn -- x >! ${WS_SENT}/builtin-subst)"
	"good = ${WS_OK}"
)

typeset WS_EVIL
ws_cfg evil "${(F)WS_PAYLOADS}"$'\n'
WS_EVIL=$REPLY

t 'a config full of shell payloads yields only the legitimate entry'
ws_parse "$WS_EVIL"
ws_entry good "$WS_OK"
assert_eq "$REPLY" "$WS_OUT" 'a payload line must be skipped, not honoured'
assert_eq 0 $WS_ST

t 'parsing a payload config says nothing on stderr'
assert_empty "$WS_ERR"

typeset s
for s in "${WS_SENT_NAMES[@]}"; do
	t "nothing executes from the ${s} payload"
	assert_status 1 test -e "${WS_SENT}/${s}"
done

t 'no payload of any shape reached a shell'
assert_empty "$(ws_sentinels)" 'a workspaces config was EXECUTED, not parsed'

t 'the sentinel mechanism can actually detect execution'
# The same payloads, aimed at a second sentinel dir, are eval'd here to prove the trap is armed.
ws_cfg evil-control "${${(F)WS_PAYLOADS}//${WS_SENT}/${WS_CTL}}"$'\n'
zsh -f -c 'eval "$(<$1)"; exit 0' hop-ws-control "$REPLY" >/dev/null 2>&1
assert_file "$WS_CTL/backtick" 'a backtick payload must fire under eval, or its absence proves nothing'
assert_file "$WS_CTL/dollar-paren" 'a $() payload must fire under eval, or its absence proves nothing'
assert_file "$WS_CTL/semicolon" 'a ; payload must fire under eval, or its absence proves nothing'
assert_file "$WS_CTL/redirect" 'the > payload is the one that fires with an empty $PATH'
assert_file "$WS_CTL/builtin-subst" 'the builtin payload is the one that fires with an empty $PATH'

t '_hop_ws_for over a payload config executes nothing'
ws_run "HOP_WORKSPACES_FILE=${WS_EVIL}" -- '_hop_ws_for '"${(q)WS_OK}"'
print -r -- "$REPLY"'
assert_eq "$WS_OK" "$WS_OUT"
assert_empty "$WS_ERR"
assert_empty "$(ws_sentinels)"

t '_hop_ws_repos and _hop_provider_ws over a payload config execute nothing'
ws_run "HOP_WORKSPACES_FILE=${WS_EVIL}" -- '_hop_ws_repos '"${(q)WS_OK}"'
_hop_provider_ws
exit 0'
assert_empty "$WS_ERR"
assert_empty "$(ws_sentinels)"

t 'a payload in the NAME field is inert text, not a command'
# The name reaches printf as an argument, so a metacharacter there has to stay a character.
ws_cfg evilname "\`touch ${WS_SENT}/name-field\` = ${WS_OK}"$'\n'
ws_run "HOP_WORKSPACES_FILE=${REPLY}" -- '_hop_provider_ws'
assert_contains "$(ws_plain "$WS_OUT")" 'touch'
assert_status 1 test -e "$WS_SENT/name-field"
assert_empty "$(ws_sentinels)"

# ---------------------------------------------------------------------------
# Parsing.
# ---------------------------------------------------------------------------

t 'name = path, a bare path, tab separators and no spaces all parse'
ws_cfg shapes "spaced = ${WS_OK}
tabbed	=	${WS_OK}
tight=${WS_OK}
${WS_OK}
"
ws_parse "$REPLY"
assert_eq "spaced	${WS_OK}
tabbed	${WS_OK}
tight	${WS_OK}
ok	${WS_OK}" "$WS_OUT" 'a bare path is named after its basename'

t 'a RUN of leading and trailing spaces is stripped, not a single space'
# ${var## } strips exactly one space, which is the bug this asserts against.
ws_cfg spaces "     runs      =      ${WS_OK}     "$'\n'
ws_parse "$REPLY"
ws_entry runs "$WS_OK"
assert_eq "$REPLY" "$WS_OUT"

t 'the first = splits, so a path may contain = itself'
ws_cfg equals "w = ${WS_WEIRD}"$'\n'
ws_parse "$REPLY"
ws_entry w "$WS_WEIRD"
assert_eq "$REPLY" "$WS_OUT"

t 'a full-line comment and an indented one are dropped'
ws_cfg comments "# a header comment
     # an indented comment
kept = ${WS_OK}
"
ws_parse "$REPLY"
ws_entry kept "$WS_OK"
assert_eq "$REPLY" "$WS_OUT"

t 'a trailing comment is dropped but a # inside a path survives'
ws_cfg hashes "trail = ${WS_OK}  # why this one exists
hashy = ${WS_HASH}
"
ws_parse "$REPLY"
assert_eq "trail	${WS_OK}
hashy	${WS_HASH}" "$WS_OUT"

t 'CRLF line endings parse'
ws_cfg crlf "a = ${WS_OK}"$'\r\n'"b = ${WS_HASH}"$'\r\n'
ws_parse "$REPLY"
assert_eq "a	${WS_OK}
b	${WS_HASH}" "$WS_OUT"
assert_not_contains "$WS_OUT" $'\r' 'a stray CR would break every path comparison downstream'

t 'a file with no trailing newline parses its last line'
ws_cfg nonl "nonl = ${WS_OK}"
ws_parse "$REPLY"
ws_entry nonl "$WS_OK"
assert_eq "$REPLY" "$WS_OUT"

t 'an empty file means no workspaces, not the built-in default'
ws_cfg empty ''
ws_parse "$REPLY" "HOME=${WS_HOME}"
assert_empty "$WS_OUT"
assert_eq 1 $WS_ST 'an empty config must report failure so the caller can say so'
assert_empty "$WS_ERR"

t 'a comments-only file means no workspaces'
ws_cfg onlycomments "# nothing here yet"$'\n\n'"# still nothing"$'\n'
ws_parse "$REPLY" "HOME=${WS_HOME}"
assert_empty "$WS_OUT"
assert_eq 1 $WS_ST

t 'a missing file falls back to the built-in default, and only to the dirs that exist'
# $WS_HOME holds `code` but none of the other candidates, so the default list gets filtered.
ws_parse "$WS_TMP/no-such-config" "HOME=${WS_HOME}"
ws_entry code "$WS_HOME/code"
assert_eq "$REPLY" "$WS_OUT" 'the built-in default is a candidate LIST, filtered by what exists'
assert_eq 0 $WS_ST

t 'the built-in default offers every conventional checkout directory'
# All five exist here, so this is the assertion that the candidate list itself has not shrunk.
typeset wsd
for wsd in "${WS_DEFAULT_DIRS[@]}"; do
	mkdir -p -- "$WS_BARE_HOME/$wsd"
done
ws_parse "$WS_TMP/no-such-config" "HOME=${WS_BARE_HOME}"
typeset -a wsgot=(${${(f)WS_OUT}%%$'\t'*})
assert_eq "${(j: :)WS_DEFAULT_DIRS}" "${(j: :)wsgot}" 'the default candidate list changed shape'
for wsd in "${WS_DEFAULT_DIRS[@]}"; do
	rmdir -- "$WS_BARE_HOME/$wsd"
done

t 'a missing file with no default directory reports nothing, silently'
ws_parse "$WS_TMP/no-such-config" "HOME=${WS_BARE_HOME}"
assert_empty "$WS_OUT"
assert_eq 1 $WS_ST
assert_empty "$WS_ERR"

t 'duplicate names: the first occurrence wins'
ws_cfg dupes "dup = ${WS_OK}
dup = ${WS_HASH}
"
ws_parse "$REPLY"
ws_entry dup "$WS_OK"
assert_eq "$REPLY" "$WS_OUT" 'a later line must never silently override an earlier one'

# ---------------------------------------------------------------------------
# Expansion.
# ---------------------------------------------------------------------------

t 'a leading ~ expands, and a bare ~ is $HOME itself'
ws_cfg tilde "sub = ~/inhome
whole = ~
"
ws_parse "$REPLY" "HOME=${WS_HOME}"
assert_eq "sub	${WS_HOME}/inhome
whole	${WS_HOME}" "$WS_OUT"

t '$HOME and ${HOME} both expand'
ws_cfg homevar 'plainvar = $HOME/inhome
bracedvar = ${HOME}/inhome
'
ws_parse "$REPLY" "HOME=${WS_HOME}"
assert_eq "plainvar	${WS_HOME}/inhome
bracedvar	${WS_HOME}/inhome" "$WS_OUT"

t 'an unset variable expands to empty, the way a shell would treat it'
ws_cfg unsetvar "gone = \$HOP_WS_NO_SUCH_VAR${WS_OK}"$'\n'
ws_parse "$REPLY"
ws_entry gone "$WS_OK"
assert_eq "$REPLY" "$WS_OUT"
assert_empty "$WS_ERR" 'an unset variable must not trip a nounset-style error'

t 'a mid-path ~ stays literal, because it is a legal filename character'
ws_cfg midtilde "mid = ${WS_TILDE}"$'\n'
ws_parse "$REPLY"
ws_entry mid "$WS_TILDE"
assert_eq "$REPLY" "$WS_OUT"
assert_contains "$WS_OUT" 'tilde~mid'

# ---------------------------------------------------------------------------
# A path that cannot be used is skipped, and skipped quietly.
# ---------------------------------------------------------------------------

t 'a missing dir, a file, a dangling symlink and an unreadable dir are all skipped'
ws_cfg unusable "missing = ${WS_GONE}
plainfile = ${WS_AFILE}
dangling = ${WS_DANGLE}
noperm = ${WS_NOPERM}
good = ${WS_OK}
"
typeset WS_UNUSABLE=$REPLY
chmod 000 "$WS_NOPERM"
ws_parse "$WS_UNUSABLE"
# Restored at once, because fixture_cleanup cannot rm -rf a directory it may not read.
chmod 755 "$WS_NOPERM"
ws_entry good "$WS_OK"
assert_eq "$REPLY" "$WS_OUT"

t 'an unusable path is skipped with nothing on stderr'
assert_empty "$WS_ERR" 'listing a directory that does not exist yet is normal, not an error'

t 'a config of nothing but unusable paths reports failure'
ws_cfg allbad "missing = ${WS_GONE}
plainfile = ${WS_AFILE}
"
ws_parse "$REPLY"
assert_empty "$WS_OUT"
assert_eq 1 $WS_ST
assert_empty "$WS_ERR"

# ---------------------------------------------------------------------------
# Precedence: $HOP_WORKSPACES, then the file, then the built-in default.
# ---------------------------------------------------------------------------

t '$HOP_WORKSPACES beats the file'
ws_cfg precedence "fromfile = ${WS_HASH}"$'\n'
ws_parse "$REPLY" "HOP_WORKSPACES=${WS_OK}" "HOME=${WS_HOME}"
ws_entry ok "$WS_OK"
assert_eq "$REPLY" "$WS_OUT" 'an ad-hoc override must replace the file, not merge with it'
assert_not_contains "$WS_OUT" 'fromfile'

t '$HOP_WORKSPACES splits on colons'
ws_run "HOP_WORKSPACES=${WS_OK}:${WS_HASH}" -- "$WS_PARSE_CODE"
assert_eq "ok	${WS_OK}
has#hash	${WS_HASH}" "$WS_OUT"

t 'the file beats the built-in default'
ws_cfg beatsdefault "fromfile = ${WS_HASH}"$'\n'
ws_parse "$REPLY" "HOME=${WS_HOME}"
ws_entry fromfile "$WS_HASH"
assert_eq "$REPLY" "$WS_OUT"
assert_not_contains "$WS_OUT" "$WS_HOME/code" 'the default must not be merged in alongside the file'

t 'the default config path is derived from $XDG_CONFIG_HOME, not from the code directory'
# The config lives beside the user's other config, never inside the checkout hop is installed from.
mkdir -p -- "$WS_HOME/.config/hop"
print -r -- "derived = ${WS_OK}" > "$WS_HOME/.config/hop/workspaces"
ws_run "XDG_CONFIG_HOME=${WS_HOME}/.config" -- "$WS_PARSE_CODE"
ws_entry derived "$WS_OK"
assert_eq "$REPLY" "$WS_OUT"

t 'and it falls back to ~/.config when XDG_CONFIG_HOME is unset'
mkdir -p -- "$WS_FAKE_HOME/.config/hop"
print -r -- "fallback = ${WS_OK}" > "$WS_FAKE_HOME/.config/hop/workspaces"
ws_run 'XDG_CONFIG_HOME=' -- "$WS_PARSE_CODE"
ws_entry fallback "$WS_OK"
assert_eq "$REPLY" "$WS_OUT"
command rm -f -- "$WS_FAKE_HOME/.config/hop/workspaces"

# ---------------------------------------------------------------------------
# _hop_ws_for: the LONGEST configured prefix wins.
# ---------------------------------------------------------------------------
# Getting this backwards is the named design risk: ~/work and ~/work/code are both wanted.

typeset WS_SHALLOW_FIRST WS_DEEP_FIRST
ws_cfg shallowfirst "outer = ${WS_NEST}
inner = ${WS_NEST}/deep
"
WS_SHALLOW_FIRST=$REPLY
ws_cfg deepfirst "inner = ${WS_NEST}/deep
outer = ${WS_NEST}
"
WS_DEEP_FIRST=$REPLY

typeset -g WS_FOR_CODE='_hop_ws_for "$1"
integer st=$?
print -r -- "$REPLY"
exit $st'

# ws_for <config> <dir> -> resolve one directory against one config.
# - The dir arrives as $1 in the child, so a path holding a space cannot be re-split.
ws_for() {
	emulate -L zsh
	local code="$WS_FOR_CODE"
	ws_run "HOP_WORKSPACES_FILE=$1" -- "set -- ${(q)2}
${code}"
}

t 'a dir inside nested workspaces resolves to the DEEPER one'
ws_for "$WS_SHALLOW_FIRST" "$WS_NEST/deep/inner"
assert_eq "$WS_NEST/deep" "$WS_OUT" 'longest prefix wins, so the shallow workspace must lose'
assert_eq 0 $WS_ST

t 'the deeper workspace still wins when it is listed first'
ws_for "$WS_DEEP_FIRST" "$WS_NEST/deep/inner"
assert_eq "$WS_NEST/deep" "$WS_OUT" 'config order must not decide the answer'

t 'a dir under only the shallow workspace resolves to it'
ws_for "$WS_SHALLOW_FIRST" "$WS_NEST/beside"
assert_eq "$WS_NEST" "$WS_OUT"

t 'a workspace directory resolves to itself'
ws_for "$WS_SHALLOW_FIRST" "$WS_NEST/deep"
assert_eq "$WS_NEST/deep" "$WS_OUT"

t 'a dir in no workspace fails and leaves REPLY empty'
ws_for "$WS_SHALLOW_FIRST" "$WS_OK"
assert_empty "$WS_OUT"
assert_eq 1 $WS_ST
assert_empty "$WS_ERR"

t 'a sibling whose name merely starts with the workspace name is not inside it'
ws_cfg prefixonly "deep = ${WS_NEST}/deep"$'\n'
ws_for "$REPLY" "$WS_NEST/deep-elsewhere"
assert_empty "$WS_OUT" 'the match must be on a path boundary, not on characters'
assert_eq 1 $WS_ST

# ---------------------------------------------------------------------------
# _hop_ws_repos: depth 1, and a worktree counts.
# ---------------------------------------------------------------------------

typeset -g WS_REPOS_CODE='_hop_ws_repos "$1"
integer st=$?
print -rl -- "${reply[@]}"
exit $st'

# ws_repos <workspace> -> the repos found directly inside it.
ws_repos() {
	emulate -L zsh
	local code="$WS_REPOS_CODE"
	ws_run -- "set -- ${(q)1}
${code}"
}

if (( WS_WT_OK )); then
	t 'a .git directory and a git WORKTREE both count as a repo'
	ws_repos "$WS_REPOS"
	assert_eq "${WS_REPOS}/fake-repo
${WS_REPOS}/wt" "$WS_OUT" 'in a worktree .git is a FILE, so a -d test would miss it'
	assert_eq 0 $WS_ST

	t 'the worktree fixture really does have a FILE at .git'
	assert_file "$WS_REPOS/wt/.git" 'the fixture stopped testing what it claims to test'
else
	skip_cap 'a .git directory and a git WORKTREE both count as a repo' 'git worktree add failed'
	skip 'the worktree fixture really does have a FILE at .git' 'git worktree add failed; the line above reports it'
fi

t 'depth 1 only: a repo one level deeper is not found'
ws_repos "$WS_REPOS"
assert_not_contains "$WS_OUT" 'deep/inner' 'recursing would enumerate every worktree in a workspace'
assert_not_contains "$WS_OUT" "${WS_REPOS}/deep"

t 'a directory with no .git is not a repo'
ws_repos "$WS_REPOS"
assert_not_contains "$WS_OUT" 'plain'

t 'a workspace holding no repos fails'
ws_repos "$WS_NONE"
assert_empty "$WS_OUT"
assert_eq 1 $WS_ST
assert_empty "$WS_ERR"

t 'a workspace that does not exist fails, silently'
ws_repos "$WS_GONE"
assert_empty "$WS_OUT"
assert_eq 1 $WS_ST
assert_empty "$WS_ERR"

# ---------------------------------------------------------------------------
# _hop_provider_ws: one row per workspace.
# ---------------------------------------------------------------------------

typeset WS_PROVIDER_CFG
# The counted workspaces are plain .git directories, so the worktree fixture cannot skew a count.
ws_cfg provider "two = ${WS_TWO}
one = ${WS_ONE}
none = ${WS_NONE}
"
WS_PROVIDER_CFG=$REPLY

t 'one row per workspace, with the absolute dir in field 2'
ws_run "HOP_WORKSPACES_FILE=${WS_PROVIDER_CFG}" -- '_hop_provider_ws'
assert_eq "${WS_TWO}
${WS_ONE}
${WS_NONE}" "$(ws_dirs "$WS_OUT")" 'rows must stay in config order'
assert_empty "$WS_ERR"

t 'every row carries the ws kind and its own name'
typeset WS_PLAIN
WS_PLAIN=$(ws_plain "$WS_OUT")
assert_contains "$WS_PLAIN" 'two'
assert_contains "$WS_PLAIN" 'one'
assert_contains "$WS_PLAIN" 'none'
assert_contains "$WS_PLAIN" ' ws '

t 'the repo count is pluralised per row'
assert_contains "$WS_PLAIN" '2 repos'
assert_contains "$WS_PLAIN" ' 1 repo '
assert_contains "$WS_PLAIN" '0 repos'
assert_not_contains "$WS_PLAIN" '1 repos'

t '$HOME is collapsed to ~ in the displayed path'
ws_cfg homerow "inh = ~/inhome"$'\n'
ws_run "HOP_WORKSPACES_FILE=${REPLY}" "HOME=${WS_HOME}" -- '_hop_provider_ws'
assert_contains "$(ws_plain "$WS_OUT")" '~/inhome'
assert_eq "$WS_HOME/inhome" "$(ws_dirs "$WS_OUT")" 'the cd target stays absolute'

t 'no workspaces means no rows, and still exits 0'
ws_cfg emptyprovider ''
ws_run "HOP_WORKSPACES_FILE=${REPLY}" -- '_hop_provider_ws'
assert_empty "$WS_OUT"
assert_eq 0 $WS_ST 'the picker prints its own hint, so the provider must not fail here'
assert_empty "$WS_ERR"

# ---------------------------------------------------------------------------
# A last look at the sentinels, after every function has run.
# ---------------------------------------------------------------------------

t 'no test in this suite executed anything from a config file'
assert_empty "$(ws_sentinels)" 'a workspaces config was EXECUTED, not parsed'

# The worktree lives in a fixture dir cleanup removes wholesale, so its registration goes first.
[[ -n $WS_MAIN ]] && _hop_fix_git -C "$WS_MAIN" worktree prune >/dev/null 2>&1
