#!/usr/bin/env zsh
# suite_keymap: the modal fzf layer's bind table and mode transitions, with no fzf UI.
# - Tier 1 calls _hop_vim_binds directly and inspects the resulting --bind strings.
# - Tier 1b pipes the real full argument list _hop_pick would hand to fzf through the real, installed `fzf --filter`, which still parses every option even in headless mode.
# - That is the exact check that would have caught apt's fzf 0.44.1 rejecting --accept-nth with "unknown option": a parse error at the source, not a terminal.
# - Tier 2 extracts the three transform: action bodies (plain sh programs) and runs them directly with the fzf state variables they read, set by hand.
# - NOTHING here may launch interactive fzf; `fzf --filter` is the only permitted mode.
# - fzf's own --height mode emits a cursor-position query and blocks forever waiting for a reply that never arrives without a real terminal, so a bare fzf call here would hang the whole suite, not just fail it.
# - lib/ui.zsh is never modified by this file: every check here is read-only.

# - Pinning HOME and XDG_CONFIG_HOME keeps every probe below from reading this machine's real ~/.config/hop.
# - hop_probe already forces HOP_CONFIG to a nonexistent path, but a leaked $HOME would still show up verbatim in a failure message.
typeset REPLY
fixture_tmpdir km-home
export HOME=$REPLY
fixture_tmpdir km-xdg
export XDG_CONFIG_HOME=$REPLY
unset REPLY

# ---------------------------------------------------------------------------
# Shared parsing helpers. None of these touch lib/ui.zsh; they only decode strings.
# ---------------------------------------------------------------------------

# - _km_strip_named <comma-list> <token> -> the list with the named multi-char token removed.
# - The token is one of ctrl-d, ctrl-u, space, removed along with the one separator that went with it.
# - Unchanged if the token isn't present.
_km_strip_named() {
	emulate -L zsh
	local s=$1 tok=$2
	if [[ $s == "$tok" ]]; then
		print -rn -- ''
	elif [[ $s == "${tok},"* ]]; then
		print -rn -- "${s#${tok},}"
	elif [[ $s == *",${tok}" ]]; then
		print -rn -- "${s%,${tok}}"
	elif [[ $s == *",${tok},"* ]]; then
		print -rn -- "${s/,${tok},/,}"
	else
		print -rn -- "$s"
	fi
}

# - _km_key_tokens <comma-joined-key-list> -> one key per line.
# - A plain split on "," is ambiguous: "," is itself one of the keys in this list, so a run like "+,,,-" is the three tokens '+' ',' '-', not four empty ones.
# - Proven while building this suite: a naive ${(s:,:)} split gives the SAME token count whether the "," key is present or missing, so it cannot tell the two apart.
# - Fix: strip the three multi-char names (ctrl-d, ctrl-u, space) first, which leaves a string where every remaining token and separator is exactly one character.
# - The tokens are then just the even-indexed characters of what's left: no delimiter splitting, so no ambiguity, whatever the "," key's neighbours happen to be.
_km_key_tokens() {
	emulate -L zsh
	local rest=$1
	local -a toks=()
	local n before
	for n in ctrl-d ctrl-u space; do
		before=$rest
		rest=$(_km_strip_named "$rest" "$n")
		[[ $rest != $before ]] && toks+=("$n")
	done
	local -i len=${#rest} i
	for (( i = 0; i < len; i += 2 )); do
		toks+=("${rest[i+1]}")
	done
	print -rl -- "${toks[@]}"
}

# - _km_split_bind <action> <verb> -> REPLY is the comma bulk list inside "<verb>(BULK)".
# - Only set when BULK is immediately followed by "+<verb>(()+<verb>())", the fixed pair covering the two keys ( and ) the bulk list structurally can't hold.
# - fzf balances parens inside a single unbind()/rebind() call, so a literal one in the comma list would split it (see the _HOP_VIM_KEYS comment in lib/ui.zsh).
# - Returns 1 if that shape isn't found.
# - Gotcha hit while writing this: the pattern operand of a parameter-expansion removal is ALWAYS glob-active, even where the surrounding code looks quoted.
# - An unquoted literal "(" typed directly in a pattern, as opposed to one arriving via a variable's value, is an unbalanced glob group, and zsh errors "bad pattern" rather than matching it.
# - ${action#"${verb}("}, with the paren inside its own quotes, is what avoids that.
_km_split_bind() {
	emulate -L zsh
	local action=$1 verb=$2
	[[ $action == "${verb}("* ]] || return 1
	local rest=${action#"${verb}("}
	local bulk=${rest%%)*}
	local tail=${rest#*)}
	[[ $tail == "+${verb}(()+${verb}())"* ]] || return 1
	REPLY=$bulk
	return 0
}

# - _km_dump_get <\x1e-dump> <prefix> -> the first item starting with $prefix, sans prefix.
# - \x1e (record separator) rather than a newline: several actions embed a change-header(...) that legitimately contains real newlines.
# - A newline-joined dump would misalign; forcing COLUMNS=200 in every probe keeps every header single-line anyway, but \x1e makes the transport correct regardless.
_km_dump_get() {
	emulate -L zsh
	local dump=$1 prefix=$2
	local -a items=("${(@ps:\x1e:)dump}")
	local it
	for it in "${items[@]}"; do
		[[ $it == "${prefix}"* ]] && { print -rn -- "${it#$prefix}"; return 0; }
	done
	return 1
}

# _km_bind_action <\x1e-dump> <key> -> the action string bound to this exact key.
_km_bind_action() {
	emulate -L zsh
	_km_dump_get "$1" "--bind=${2}:"
}

# ---------------------------------------------------------------------------
# Tier 1: _hop_vim_binds called directly, its --bind strings inspected as text.
# ---------------------------------------------------------------------------

# - _km_binds_probe <root> <restore> <drill> <up> -> \x1e-joined dump of every entry in the real --bind args array, plus HOP_VIM_TO_NORMAL and _HOP_VIM_KEYS tagged on the end.
# - "local -a args" here, with no enclosing function, mirrors _hop_pick's own "local -a args" one call frame up from _hop_vim_binds.
# - The whole file relies on that dynamic scoping (see its own header comment); this is the same trick, one frame further out again.
_km_binds_probe() {
	emulate -L zsh
	local -x KM_ROOT=$1 KM_RESTORE=$2 KM_DRILL=$3 KM_UP=$4
	hop_probe '
		COLUMNS=200
		local -a args
		_hop_vim_binds "preview-cmd" "" "$KM_ROOT" "$KM_RESTORE" "" "$KM_DRILL" "$KM_UP"
		args+=("KM_TO_NORMAL=${HOP_VIM_TO_NORMAL}")
		args+=("KM_KEYS=${(j:,:)_HOP_VIM_KEYS}")
		print -rn -- "${(pj:\x1e:)args}"
	'
}

typeset KM_FULL
KM_FULL=$(_km_binds_probe /some/root RESTORECMD 1 1)

# --- every NORMAL-mode key maps to its documented action ---
t 'j is down, restoring the preview'
assert_eq 'down+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_FULL" j)"

t 'k is up, restoring the preview'
assert_eq 'up+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_FULL" k)"

t 'g is first, restoring the preview'
assert_eq 'first+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_FULL" g)"

t 'G is last, restoring the preview'
assert_eq 'last+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_FULL" G)"

t 'ctrl-d is half-page-down, restoring the preview'
assert_eq 'half-page-down+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_FULL" ctrl-d)"

t 'ctrl-u is half-page-up, restoring the preview'
assert_eq 'half-page-up+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_FULL" ctrl-u)"

t 'o prints ctrl-o and accepts (open in code)'
assert_eq 'print(ctrl-o)+accept' "$(_km_bind_action "$KM_FULL" o)"

t 'O prints ctrl-t and accepts (open folder)'
assert_eq 'print(ctrl-t)+accept' "$(_km_bind_action "$KM_FULL" O)"

t 'e prints alt-o and accepts (edit)'
assert_eq 'print(alt-o)+accept' "$(_km_bind_action "$KM_FULL" e)"

t 'y prints ctrl-y and accepts (copy)'
assert_eq 'print(ctrl-y)+accept' "$(_km_bind_action "$KM_FULL" y)"

t 'Y prints alt-y and accepts (copy file)'
assert_eq 'print(alt-y)+accept' "$(_km_bind_action "$KM_FULL" Y)"

t 'b prints ctrl-g and accepts (browse/github)'
assert_eq 'print(ctrl-g)+accept' "$(_km_bind_action "$KM_FULL" b)"

t 'p toggles the preview'
assert_eq 'toggle-preview' "$(_km_bind_action "$KM_FULL" p)"

t 'q aborts'
assert_eq 'abort' "$(_km_bind_action "$KM_FULL" q)"

t 'r reloads the restore command, when one was given'
assert_eq 'reload(RESTORECMD)' "$(_km_bind_action "$KM_FULL" r)"

t 'l prints ctrl-l and accepts, when a drill target was given'
assert_eq 'print(ctrl-l)+accept' "$(_km_bind_action "$KM_FULL" l)"

t 'h prints ctrl-h and accepts, when an up-level target was given'
assert_eq 'print(ctrl-h)+accept' "$(_km_bind_action "$KM_FULL" h)"

t '? toggles the keys overlay, reading its own state from FZF_PREVIEW_LABEL'
assert_eq 'transform:if [ -n "$FZF_PREVIEW_LABEL" ]; then printf %s "$HOP_VIM_HELP_OFF"; else printf %s "$HOP_VIM_HELP_ON"; fi' \
	"$(_km_bind_action "$KM_FULL" '?')"

t 'esc resolves from FZF_PROMPT and FZF_INPUT_STATE, never a file'
# The clear-query+search() prefix is STATIC and has to stay ahead of the transform.
# - fzf ignores `search()` emitted by a transform:, so folding it in brings the dead list back.
assert_eq 'clear-query+search()+transform:case "$FZF_PROMPT" in ": "*) printf %s "${HOP_VIM_MENU_BACK:-abort}" ;; *) if [ "$FZF_INPUT_STATE" = disabled ]; then printf abort; else printf %s "$HOP_VIM_TO_NORMAL"; fi ;; esac' \
	"$(_km_bind_action "$KM_FULL" esc)"

t '/ switches to SEARCH: unbinds the vim keys, enables search, re-prompts'
typeset slash
slash=$(_km_bind_action "$KM_FULL" /)
assert_contains "$slash" 'enable-search'
assert_contains "$slash" 'change-prompt(/ )'
assert_contains "$slash" 'unbind('

t ': switches to the kind menu in place, reloading from hop-kinds'
typeset colon
colon=$(_km_bind_action "$KM_FULL" :)
assert_contains "$colon" 'change-prompt(: )'
assert_contains "$colon" 'reload('
assert_contains "$colon" '/some/root'

# --- unmapped printable keys default to ignore ---
t 'unmapped letters, digits and symbols default to ignore'
typeset -a plain=(a c d f i m n s t u v w x z A C D F H I J K L M N P Q R S T U V W X Z 0 1 5 9 space '!' '@' '#' '_' '~' '`' ',' '+')
typeset pk
for pk in "${plain[@]}"; do
	assert_eq 'ignore' "$(_km_bind_action "$KM_FULL" "$pk")" "key '${pk}' should default to ignore"
done

# --- l, h and r are gated on whether _hop_run actually gave them something to do ---
typeset KM_NONE KM_DRILL_ONLY KM_UP_ONLY KM_RESTORE_ONLY
KM_NONE=$(_km_binds_probe /some/root '' '' '')
KM_DRILL_ONLY=$(_km_binds_probe /some/root '' 1 '')
KM_UP_ONLY=$(_km_binds_probe /some/root '' '' 1)
KM_RESTORE_ONLY=$(_km_binds_probe /some/root RESTORECMD '' '')

t 'with no drill, up or restore target, l, h and r all fall back to ignore'
assert_eq 'ignore' "$(_km_bind_action "$KM_NONE" l)"
assert_eq 'ignore' "$(_km_bind_action "$KM_NONE" h)"
assert_eq 'ignore' "$(_km_bind_action "$KM_NONE" r)"

t 'l is live only when a drill target was actually given'
assert_eq 'print(ctrl-l)+accept' "$(_km_bind_action "$KM_DRILL_ONLY" l)"
assert_eq 'ignore' "$(_km_bind_action "$KM_DRILL_ONLY" h)" 'h must not fire without its own up-level target'
assert_eq 'ignore' "$(_km_bind_action "$KM_DRILL_ONLY" r)" 'r must not fire without its own restore command'

t 'h is live only when an up-level target was actually given'
assert_eq 'print(ctrl-h)+accept' "$(_km_bind_action "$KM_UP_ONLY" h)"
assert_eq 'ignore' "$(_km_bind_action "$KM_UP_ONLY" l)" 'l must not fire without its own drill target'
assert_eq 'ignore' "$(_km_bind_action "$KM_UP_ONLY" r)" 'r must not fire without its own restore command'

t 'r is live only when a restore command was actually given'
assert_eq 'reload(RESTORECMD)' "$(_km_bind_action "$KM_RESTORE_ONLY" r)"
assert_eq 'ignore' "$(_km_bind_action "$KM_RESTORE_ONLY" l)" 'l must not fire without its own drill target'
assert_eq 'ignore' "$(_km_bind_action "$KM_RESTORE_ONLY" h)" 'h must not fire without its own up-level target'

# --- with no root, the menu never activates ---
typeset KM_NOROOT
KM_NOROOT=$(_km_binds_probe '' '' '' '')

t 'with no root, : falls back to ignore (no menu to switch into)'
assert_eq 'ignore' "$(_km_bind_action "$KM_NOROOT" :)"

t 'with no root, enter is never bound at all (plain accept needs no help)'
typeset -a noroot_items=("${(@ps:\x1e:)KM_NOROOT}")
typeset -i enter_seen=0
typeset ni
for ni in "${noroot_items[@]}"; do
	[[ $ni == --bind=enter:* ]] && enter_seen=1
done
assert_eq 0 "$enter_seen" 'enter must be unbound (falling through to fzf default accept) when there is no menu'

# --- the round-trip invariant: unbind, rebind and the owned-key list are the same set ---
# - This is the highest-value check in this tier.
# - If a key is unbound entering SEARCH but never rebound coming back to NORMAL, that key is silently dead for the rest of the session, and nothing else in this suite (or in production) would notice.
t 'every key unbound entering SEARCH is rebound returning to NORMAL, and both match the owned key list'
typeset km_slash km_to_normal km_keys_joined
km_slash=$(_km_bind_action "$KM_FULL" /)
km_to_normal=$(_km_dump_get "$KM_FULL" 'KM_TO_NORMAL=')
km_keys_joined=$(_km_dump_get "$KM_FULL" 'KM_KEYS=')

typeset unbind_bulk rebind_bulk
if _km_split_bind "$km_slash" unbind; then
	unbind_bulk=$REPLY
else
	unbind_bulk=''
	assert_eq 1 0 'could not find the unbind(...)+unbind(()+unbind()) shape in the / action'
fi
if _km_split_bind "$km_to_normal" rebind; then
	rebind_bulk=$REPLY
else
	rebind_bulk=''
	assert_eq 1 0 'could not find the rebind(...)+rebind(()+rebind()) shape in HOP_VIM_TO_NORMAL'
fi

typeset -a unbind_keys rebind_keys owned_keys
unbind_keys=("${(f)$(_km_key_tokens "$unbind_bulk")}" '(' ')')
rebind_keys=("${(f)$(_km_key_tokens "$rebind_bulk")}" '(' ')')
owned_keys=("${(f)$(_km_key_tokens "$km_keys_joined")}" '(' ')')

# - Compared as sets (zsh's :| set-difference), never as ordered strings.
# - Reordering _HOP_VIM_KEYS in the source is harmless, since fzf's comma list doesn't care about order, and this comparison can never turn red because of it.
typeset -a missing_from_rebind extra_in_rebind missing_from_owned extra_vs_owned
missing_from_rebind=("${(@)unbind_keys:|rebind_keys}")
extra_in_rebind=("${(@)rebind_keys:|unbind_keys}")
missing_from_owned=("${(@)owned_keys:|unbind_keys}")
extra_vs_owned=("${(@)unbind_keys:|owned_keys}")

assert_eq '' "${(j:,:)missing_from_rebind}" 'key(s) unbound entering SEARCH but never rebound back to NORMAL'
assert_eq '' "${(j:,:)extra_in_rebind}" 'key(s) rebound to NORMAL that were never unbound entering SEARCH'
assert_eq '' "${(j:,:)missing_from_owned}" 'key(s) in _HOP_VIM_KEYS never unbound entering SEARCH'
assert_eq '' "${(j:,:)extra_vs_owned}" 'key(s) unbound entering SEARCH that are not in _HOP_VIM_KEYS'
assert_ge $#unbind_keys 90 'sanity floor: the modal layer should own at least 90 keys'

# ---------------------------------------------------------------------------
# Tier 1b: the real, full bind set validated against the real, installed fzf.
# ---------------------------------------------------------------------------

# - _km_pick_filter <mutate> -> "<exit status>\x1e<stderr>" from feeding the real _hop_pick argument list into the REAL fzf binary in --filter mode.
# - fzf itself is shadowed by a function here, so it's captured rather than launched.
# - $mutate is zsh code, eval'd against the captured KM_CAPTURED array before the real fzf call: empty for the unmodified baseline, or a one-line corruption for sanity.
_km_pick_filter() {
	emulate -L zsh
	local -x KM_MUTATE=${1:-}
	local -x KM_ROWS=$'vpc  tg\t/a/vpc\t/a/vpc/main.tf\nsqs  tg\t/a/sqs\t/a/sqs/main.tf'
	hop_probe '
		COLUMNS=200
		typeset -ga KM_CAPTURED
		fzf() { KM_CAPTURED=("$@"); return 0; }
		_hop_pick "label" "header" "" "reloadcmd" "/some/root" "1" "restorecmd" "1"
		[[ -n $KM_MUTATE ]] && eval "$KM_MUTATE"
		local errfile
		errfile=$(mktemp)
		print -rn -- "$KM_ROWS" | command fzf "${KM_CAPTURED[@]}" --filter=vpc >/dev/null 2>"$errfile"
		local -i st=$?
		local err
		err=$(<"$errfile")
		rm -f -- "$errfile"
		local -a out=("$st" "$err")
		print -rn -- "${(pj:\x1e:)out}"
	'
}

if (( ${+commands[fzf]} )); then
	t "the real, full bind set parses against this machine's installed fzf"
	typeset base
	base=$(_km_pick_filter)
	typeset -a baseitems=("${(@ps:\x1e:)base}")
	assert_eq 0 "${baseitems[1]}" "fzf rejected hop's own args: ${baseitems[2]:-}"

	# - Sanity #1, mirroring a real bug this check caught.
	# - A leading comma makes ",:ignore" not a valid action name.
	t 'sanity: a bind action with a stray leading comma is rejected, not silently accepted'
	typeset saboteur1
	saboteur1='local i; for ((i = 1; i <= $#KM_CAPTURED; i++)); do [[ ${KM_CAPTURED[i]} == --bind=j:* ]] && KM_CAPTURED[i]="--bind=j:,:ignore"; done'
	typeset sab1
	sab1=$(_km_pick_filter "$saboteur1")
	typeset -a sab1items=("${(@ps:\x1e:)sab1}")
	assert_ne 0 "${sab1items[1]}" 'a malformed action string was silently accepted'
	assert_contains "${sab1items[2]:-}" 'unknown action'

	# - Sanity #2, mirroring the other real bug this check caught.
	# - A backslash-escaped comma inside unbind(...) leaves fzf trying to bind the unsupported key "a\".
	t 'sanity: a backslash-escaped comma inside unbind(...) is rejected, not silently accepted'
	typeset saboteur2
	saboteur2='local i; for ((i = 1; i <= $#KM_CAPTURED; i++)); do [[ ${KM_CAPTURED[i]} == --bind=esc:* ]] && KM_CAPTURED[i]="--bind=esc:unbind(a\,b)"; done'
	typeset sab2
	sab2=$(_km_pick_filter "$saboteur2")
	typeset -a sab2items=("${(@ps:\x1e:)sab2}")
	assert_ne 0 "${sab2items[1]}" 'a malformed unbind() call was silently accepted'
	assert_contains "${sab2items[2]:-}" 'unsupported key'
else
	skip "the real, full bind set parses against this machine's installed fzf" 'fzf is not installed'
	skip 'sanity: a bind action with a stray leading comma is rejected, not silently accepted' 'fzf is not installed'
	skip 'sanity: a backslash-escaped comma inside unbind(...) is rejected, not silently accepted' 'fzf is not installed'
fi

# ---------------------------------------------------------------------------
# Tier 2: the transform: action bodies, extracted and run directly as sh.
# ---------------------------------------------------------------------------

# - _km_transform_probe -> \x1e-joined dump of the esc, enter and ? action bodies, with everything up to and including "transform:" stripped, plus every HOP_VIM_* string those bodies read.
# - Captured from inside the real fzf-shadow, before _hop_pick's locals go out of scope.
# - esc strips up to `transform:` rather than a leading one, because it carries a static prefix.
# - Tier 1 is what asserts that prefix is present and ordered; here it is only in the way.
_km_transform_probe() {
	emulate -L zsh
	hop_probe '
		COLUMNS=200
		typeset -ga KM_CAPTURED
		fzf() {
			KM_CAPTURED=("$@")
			KM_TO_NORMAL=$HOP_VIM_TO_NORMAL
			KM_MENU_BACK=$HOP_VIM_MENU_BACK
			KM_PICK_KIND=$HOP_VIM_PICK_KIND
			KM_HELP_ON=$HOP_VIM_HELP_ON
			KM_HELP_OFF=$HOP_VIM_HELP_OFF
			return 0
		}
		_hop_pick "label" "header" "" "reloadcmd" "/some/root" "1" "restorecmd" "1"
		local esc_body enter_body help_body a
		for a in "${KM_CAPTURED[@]}"; do
			case $a in
				--bind=esc:*transform:*) esc_body=${a#*transform:} ;;
				--bind=enter:transform:*) enter_body=${a#--bind=enter:transform:} ;;
				"--bind=?:transform:"*) help_body=${a#"--bind=?:transform:"} ;;
			esac
		done
		export HOP_VIM_TO_NORMAL=$KM_TO_NORMAL HOP_VIM_MENU_BACK=$KM_MENU_BACK
		export HOP_VIM_PICK_KIND=$KM_PICK_KIND HOP_VIM_HELP_ON=$KM_HELP_ON HOP_VIM_HELP_OFF=$KM_HELP_OFF
		local -a out=()
		out+=("ESC_MENU=$(FZF_PROMPT=": " FZF_INPUT_STATE=disabled sh -c "$esc_body")")
		out+=("ESC_SEARCH=$(FZF_PROMPT="/ " FZF_INPUT_STATE=enabled sh -c "$esc_body")")
		out+=("ESC_NORMAL=$(FZF_PROMPT="> " FZF_INPUT_STATE=disabled sh -c "$esc_body")")
		out+=("ENTER_MENU=$(FZF_PROMPT=": " sh -c "$enter_body")")
		out+=("ENTER_NORMAL=$(FZF_PROMPT="> " sh -c "$enter_body")")
		out+=("HELP_ON=$(FZF_PREVIEW_LABEL="" sh -c "$help_body")")
		out+=("HELP_OFF=$(FZF_PREVIEW_LABEL=" keys " sh -c "$help_body")")
		out+=("EXPECT_MENU_BACK=${KM_MENU_BACK}")
		out+=("EXPECT_TO_NORMAL=${KM_TO_NORMAL}")
		out+=("EXPECT_PICK_KIND=${KM_PICK_KIND}")
		out+=("EXPECT_HELP_ON=${KM_HELP_ON}")
		out+=("EXPECT_HELP_OFF=${KM_HELP_OFF}")
		print -rn -- "${(pj:\x1e:)out}"
	'
}

typeset KM_TF
KM_TF=$(_km_transform_probe)

t 'esc in the kind menu goes back to the view you came from'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_MENU_BACK=')" "$(_km_dump_get "$KM_TF" 'ESC_MENU=')"

t 'esc in SEARCH (input enabled) returns to NORMAL and drops the filter'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_TO_NORMAL=')" "$(_km_dump_get "$KM_TF" 'ESC_SEARCH=')"

t 'esc in NORMAL (input disabled) quits'
assert_eq 'abort' "$(_km_dump_get "$KM_TF" 'ESC_NORMAL=')"

t 'enter in the kind menu switches to the picked kind'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_PICK_KIND=')" "$(_km_dump_get "$KM_TF" 'ENTER_MENU=')"

t 'enter outside the menu is a plain accept'
assert_eq 'accept' "$(_km_dump_get "$KM_TF" 'ENTER_NORMAL=')"

t '? opens the keys overlay when it is not already showing'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_HELP_ON=')" "$(_km_dump_get "$KM_TF" 'HELP_ON=')"

t '? closes the keys overlay and restores the real preview when it is showing'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_HELP_OFF=')" "$(_km_dump_get "$KM_TF" 'HELP_OFF=')"
