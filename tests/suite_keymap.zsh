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
# - The fifth argument is the escape-guard state file, and EVERY probe below leaves it empty.
# - That is deliberate: with no guard file the keymap must fall back to the plain, unguarded actions.
# - So every assertion in this tier doubles as proof of that fallback, and the guarded shape has its own probe.
_km_binds_probe() {
	emulate -L zsh
	local -x KM_ROOT=$1 KM_RESTORE=$2 KM_DRILL=$3 KM_UP=$4 KM_GUARD=${5:-}
	hop_probe '
		COLUMNS=200
		local -a args
		_hop_vim_binds "preview-cmd" "" "$KM_ROOT" "$KM_RESTORE" "" "$KM_DRILL" "$KM_UP" "$KM_GUARD"
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
typeset esc_bind
esc_bind=$(_km_bind_action "$KM_FULL" esc)
assert_eq 'clear-query+search()+transform:case "$FZF_PROMPT" in ": "*) printf %s "${HOP_VIM_MENU_BACK:-abort}" ;; *) if [ "$FZF_INPUT_STATE" = disabled ]; then printf abort; else printf %s "$HOP_VIM_TO_NORMAL"; fi ;; esac' \
	"$esc_bind"

# Named separately from the equality above, so a regression says WHICH property broke.
t 'esc re-matches from a STATIC prefix, because fzf ignores search() from a transform'
assert_eq 'clear-query+search()+' "${esc_bind%%transform:*}" 'clear-query then search() must run BEFORE the transform, statically'
assert_not_contains "${esc_bind#*transform:}" 'search()' 'a search() inside the transform body is silently ignored by fzf'

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
# Tier 1d: the escape guard, which is a SECOND keymap layered over the one above.
# ---------------------------------------------------------------------------

# The whole mechanism in one paragraph, because none of it is guessable from the bind strings.
# - fzf cannot decode every inbound escape sequence, and what it cannot parse arrives as keystrokes.
# - It DOES turn the unrecognised introducer into a bindable key, so `\e]` from an OSC reply is alt-].
# - So every alt-<char> hop does not own writes a timestamp, and every verb checks it before running.
# - A forged letter follows its introducer by ~20ms, a real one by however long the user took.
typeset KM_GUARDED
KM_GUARDED=$(_km_binds_probe /some/root RESTORECMD 1 1 /tmp/kmguard/mark)

typeset -g KM_GPRE='transform:'
typeset -g KM_GMID=' check /tmp/kmguard/mark '

# _km_guarded <action> -> the exact bind string a guarded action must produce.
# - Built from the same pieces lib/ui.zsh uses, so the test names the SHAPE and not one literal.
_km_guarded() {
	emulate -L zsh
	print -rn -- "${KM_GPRE}${HOP_HOME}/bin/hop-guard${KM_GMID}'${1}'"
}

# Asserted first: a probe that captured nothing would make every check below vacuous.
t 'the guarded probe produced a bind set at all'
assert_nonempty "$(_km_bind_action "$KM_GUARDED" j)" 'the guarded probe captured no j bind, so it captured nothing'

# Nine keys, not six: every action that LEAVES the picker, so a stray letter cannot exit it either.
t 'every action that leaves the picker is wrapped in the guard'
assert_eq "$(_km_guarded 'print(ctrl-o)+accept')" "$(_km_bind_action "$KM_GUARDED" o)"
assert_eq "$(_km_guarded 'print(ctrl-t)+accept')" "$(_km_bind_action "$KM_GUARDED" O)"
assert_eq "$(_km_guarded 'print(alt-o)+accept')" "$(_km_bind_action "$KM_GUARDED" e)"
assert_eq "$(_km_guarded 'print(ctrl-y)+accept')" "$(_km_bind_action "$KM_GUARDED" y)"
assert_eq "$(_km_guarded 'print(alt-y)+accept')" "$(_km_bind_action "$KM_GUARDED" Y)"
assert_eq "$(_km_guarded 'print(ctrl-g)+accept')" "$(_km_bind_action "$KM_GUARDED" b)"
assert_eq "$(_km_guarded 'print(ctrl-l)+accept')" "$(_km_bind_action "$KM_GUARDED" l)"
assert_eq "$(_km_guarded 'print(ctrl-h)+accept')" "$(_km_bind_action "$KM_GUARDED" h)"
assert_eq "$(_km_guarded abort)" "$(_km_bind_action "$KM_GUARDED" q)"

# A fork on j is a fork on every cursor move, which is the one cost the picker cannot absorb.
t 'the navigation keys stay fork-free, exactly as they were'
assert_eq 'down+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_GUARDED" j)"
assert_eq 'up+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_GUARDED" k)"
assert_eq 'first+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_GUARDED" g)"
assert_eq 'last+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_GUARDED" G)"
assert_eq 'half-page-down+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_GUARDED" ctrl-d)"
assert_eq 'half-page-up+change-preview(preview-cmd)+change-preview-label()' "$(_km_bind_action "$KM_GUARDED" ctrl-u)"

# `r` reloads and stays unguarded: its action embeds a shell command holding $HOP_HOME and "$@".
# - Re-quoting that through a transform body is a real hazard, and a redrawn list is not a side effect.
t 'the in-picker actions are left alone, r included'
assert_eq 'reload(RESTORECMD)' "$(_km_bind_action "$KM_GUARDED" r)" 'r must not be re-quoted through a transform'
assert_eq 'toggle-preview' "$(_km_bind_action "$KM_GUARDED" p)"
assert_not_contains "$(_km_bind_action "$KM_GUARDED" '?')" 'hop-guard' 'the help overlay is reversible, so it needs no guard'
assert_not_contains "$(_km_bind_action "$KM_GUARDED" '/')" 'hop-guard' 'entering SEARCH is reversible with esc'
assert_not_contains "$(_km_bind_action "$KM_GUARDED" ':')" 'hop-guard' 'the view menu is reversible with esc'

# A gated-off key stays a plain ignore: guarding a dead key would be a fork that decides nothing.
t 'a key gated off by its own missing target is never guarded'
typeset KM_GUARDED_NONE
KM_GUARDED_NONE=$(_km_binds_probe /some/root '' '' '' /tmp/kmguard/mark)
assert_eq 'ignore' "$(_km_bind_action "$KM_GUARDED_NONE" l)" 'l has no drill target, so it must stay a bare ignore'
assert_eq 'ignore' "$(_km_bind_action "$KM_GUARDED_NONE" h)" 'h has no up target, so it must stay a bare ignore'
assert_eq 'ignore' "$(_km_bind_action "$KM_GUARDED_NONE" r)" 'r has no restore command, so it must stay a bare ignore'

# The mark half. One rule over every alt-<char>, because fzf accepts ANY char after an unparsed ESC.
# - Enumerating today's five introducers would leave the next one uncovered for no saving at all.
t 'every escape introducer fzf can surface as alt-<char> writes a mark'
typeset KM_MARK
KM_MARK="execute-silent(${HOP_HOME}/bin/hop-guard mark /tmp/kmguard/mark)"
typeset mk
for mk in ']' 'P' '_' '^' 'X' '\' '[' '@' '(' ')' '*' '?' 'Q' '0' 'space'; do
	if [[ $mk == '(' || $mk == ')' ]]; then
		assert_empty "$(_km_bind_action "$KM_GUARDED" "alt-${mk}")" "alt-${mk} is skipped: a charset designation has a one-byte payload"
	else
		assert_eq "$KM_MARK" "$(_km_bind_action "$KM_GUARDED" "alt-${mk}")" "alt-${mk} must arm the guard"
	fi
done

# An (I) subscript is a PATTERN, and this key list is indexed by ? * [ and \ among others.
# - Measured: ${guard_keys[(I)?]} returns 9, so (I) would have wrapped `?` and skipped alt-*.
t 'the guard lists are matched exactly, not as globs'
assert_eq "$KM_MARK" "$(_km_bind_action "$KM_GUARDED" 'alt-*')" 'alt-* was skipped, so an (I) subscript matched it as a glob'
assert_eq "$KM_MARK" "$(_km_bind_action "$KM_GUARDED" 'alt-?')" 'alt-? was skipped, so an (I) subscript matched it as a glob'
assert_not_contains "$(_km_bind_action "$KM_GUARDED" '?')" 'hop-guard check' 'the ? overlay got guarded, so an (I) subscript matched it as a glob'

# Marking a key hop or fzf already owns would either shadow a verb or cost a user their next keystroke.
t 'the alt- keys hop and fzf already own are never turned into marks'
typeset ok
for ok in a o p y B b c d f g; do
	assert_not_contains "$(_km_bind_action "$KM_GUARDED" "alt-${ok}")" 'hop-guard mark' "alt-${ok} is already taken and must not be a mark"
done

# Exact, never a floor: a count that only has to exceed something passes when half the set vanishes.
# - Derived from the owned key list rather than hardcoded, so a key added to it must be marked too.
# - The twelve taken keys are a o p y B b c d f g and the two ctrl- entries, which are not chars.
t 'the mark set is exactly the owned key list minus the twelve already-taken keys'
typeset -a km_items=("${(@ps:\x1e:)KM_GUARDED}")
typeset -i km_marks=0 km_checks=0
typeset ki
for ki in "${km_items[@]}"; do
	[[ $ki == --bind=alt-*'hop-guard mark'* ]] && (( km_marks++ ))
	[[ $ki == *'hop-guard check'* ]] && (( km_checks++ ))
done
typeset -a km_owned=("${(f)$(_km_key_tokens "$(_km_dump_get "$KM_GUARDED" 'KM_KEYS=')")}")
assert_eq $(( $#km_owned - 12 )) "$km_marks" 'the mark set is not the owned key list minus the twelve taken keys'
assert_eq 83 "$km_marks" 'the mark count changed, so either the key list or the taken list moved'
assert_eq 9 "$km_checks" 'exactly nine actions leave the picker and so exactly nine must be guarded'

# ---------------------------------------------------------------------------
# Tier 1c: the picker's OWN flags, one call frame further out than _hop_vim_binds.
# ---------------------------------------------------------------------------

# - _km_pick_probe <vim> -> \x1e-joined dump of the FULL argument list _hop_pick hands fzf.
# - Tier 1's probe sees only what _hop_vim_binds appends, and --expect is not there.
# - Every check below runs at HOP_VIM=1 AND at HOP_VIM=0, because --expect is passed unconditionally.
# - An --expect key ignores the modal layer, so --no-vim never protected against one the way it does a letter.
# - fixture_pins does not pin HOP_VIM, so exporting it here genuinely varies what the probe sees.
_km_pick_probe() {
	emulate -L zsh
	local -x KM_VIM=$1
	hop_probe '
		COLUMNS=200
		export HOP_VIM=$KM_VIM
		typeset -ga KM_CAPTURED
		fzf() { KM_CAPTURED=("$@"); return 0; }
		_hop_pick "label" "header" "" "reloadcmd" "/some/root" "1" "restorecmd" "1"
		print -rn -- "${(pj:\x1e:)KM_CAPTURED}"
	'
}

typeset KM_PICK KM_PICK_NOVIM
KM_PICK=$(_km_pick_probe 1)
KM_PICK_NOVIM=$(_km_pick_probe 0)

# Asserted first, because a probe that captured nothing would make every check below vacuous.
t 'both picker probes captured a real argument list'
assert_nonempty "$(_km_dump_get "$KM_PICK" '--expect=')" 'the HOP_VIM=1 probe captured no --expect at all'
assert_nonempty "$(_km_dump_get "$KM_PICK_NOVIM" '--expect=')" 'the HOP_VIM=0 probe captured no --expect at all'

# A single BEL byte (0x07) in anything the terminal prints arrives at fzf AS ctrl-g.
# - Measured under a pty: a bare \a ran `gh browse`, at HOP_VIM=1 and at HOP_VIM=0 alike.
# - `ignore` and not merely absent: unbound, fzf's own default for ctrl-g is `abort`.
# - So leaving it out would make the same bell CLOSE the picker, which is a worse trade than a no-op.
t 'ctrl-g is inert, so a bare BEL byte cannot reach the browse verb'
assert_eq 'ignore' "$(_km_bind_action "$KM_PICK" ctrl-g)" 'ctrl-g must be bound to ignore, not left to fzf abort'
assert_eq 'ignore' "$(_km_bind_action "$KM_PICK_NOVIM" ctrl-g)" 'the ctrl-g guard must not depend on the modal layer'

# Exact lists, never a "does not contain ctrl-g" check, which would also pass on a key silently ADDED.
t 'ctrl-g is gone from --expect, in both modes, because --expect outranks every bind'
assert_eq 'ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y,ctrl-l,ctrl-h' "$(_km_dump_get "$KM_PICK" '--expect=')"
assert_eq 'ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y,ctrl-l,ctrl-h' "$(_km_dump_get "$KM_PICK_NOVIM" '--expect=')"

# print(ctrl-g)+accept rather than --expect=alt-B, which keeps _hop_dispatch's existing ctrl-g arm.
# - A bind is also something a guard could wrap later, which an --expect key can never be.
t 'browse moved to alt-B, printing the key _hop_dispatch already knows'
assert_eq 'print(ctrl-g)+accept' "$(_km_bind_action "$KM_PICK" alt-B)"
assert_eq 'print(ctrl-g)+accept' "$(_km_bind_action "$KM_PICK_NOVIM" alt-B)"

# alt-g is the SHELL widget that launches hop, and alt-b is fzf's own backward-word.
t 'browse did not land on alt-g or alt-b, which are both already taken'
assert_empty "$(_km_bind_action "$KM_PICK" alt-g)" 'alt-g inside the picker would shadow the launcher key'
assert_empty "$(_km_bind_action "$KM_PICK" alt-b)" 'alt-b is fzf backward-word and SEARCH needs it'

# ---------------------------------------------------------------------------
# Tier 1e: the picker must not advertise a key it left bound to `ignore`.
# ---------------------------------------------------------------------------

# Five keys are gated on a _hop_run argument, so a given picker may bind none of them.
# - r on restore, : on root, l on drill, h on up, and M-a on reload.
# - The repo picker (hop -R) passes only up, and the workspace picker (hop -w) only drill.
# - So four of the five were dead in both, while the NORMAL legend and the `?` overlay named them all.
# - Pressing the key the header just told you to press, and getting no error and no beep, is the bug.

# - _km_overlay_probe <reload> <root> <drill> <restore> <up> -> "ADV=<keys>\x1eBOUND=<keys>\x1eHDR=<legend>".
# - ADV is read by actually RUNNING bin/hop-preview with the argument the `?` bind hands it.
# - Nothing is inferred from the bind string: the overlay's real rendered text is what a user reads.
# - BOUND is read from the same call's captured bind table, and from --bind=alt-a for M-a.
# - Comparing the two sets IS the property, and neither side is written down twice.
# - Argument order mirrors _hop_pick's, so a callsite in hop.zsh can be transcribed straight in.
_km_overlay_probe() {
	emulate -L zsh
	local -x KM_RELOAD=$1 KM_ROOT=$2 KM_DRILL=$3 KM_RESTORE=$4 KM_UP=$5
	hop_probe '
		COLUMNS=200
		typeset -ga KM_CAPTURED
		typeset -g KM_HELP_ON="" KM_HEAD=""
		fzf() {
			KM_CAPTURED=("$@")
			KM_HELP_ON=$HOP_VIM_HELP_ON
			return 0
		}
		# NO pipeline: the last element of one runs in a subshell, so the captures would not survive.
		_hop_pick "label" "header" "" "$KM_RELOAD" "$KM_ROOT" "$KM_DRILL" "$KM_RESTORE" "$KM_UP"

		# The header fzf was actually given, which is the legend the user reads in the list pane.
		local a
		for a in "${KM_CAPTURED[@]}"; do
			[[ $a == --header=* ]] && KM_HEAD=${a#--header=}
		done

		# The ? overlay command lives inside HOP_VIM_HELP_ON, which is where the transform reads it.
		# - Both parens are QUOTED inside the pattern, which is not optional; see _km_split_bind above.
		# - A literal ( typed straight into a pattern operand is an unbalanced glob group, not a paren.
		# - Unquoted, this failed with `bad pattern` and every assertion below compared empty to empty.
		local hc=${KM_HELP_ON#*"change-preview("}
		hc=${hc%%")"*}
		local out=""
		[[ -n $hc ]] && out=$(eval "$hc" 2>/dev/null)
		# Strip SGR so the key column is at a fixed offset regardless of colour.
		# - extended_glob is needed for the # closure, and zsh -f does not set it.
		setopt extended_glob
		out=${out//$'"'"'\e'"'"'\[[0-9;]##m/}

		# Columns 1-17 are the key field on every line of the overlay, and 18 on is prose.
		# - Splitting that field on / is what makes the shared `l / h` line report BOTH keys.
		local -a adv=()
		local line tok
		for line in ${(f)out}; do
			[[ $line == "  "* ]] || continue
			for tok in ${(s:/:)line[1,17]}; do
				tok=${tok//[[:space:]]/}
				[[ -n $tok ]] && adv+=("$tok")
			done
		done

		# Only the five gated keys are compared; the always-bound ones are asserted elsewhere.
		local -a want=(r : l h M-a) adv5=() bnd=()
		local k
		for k in "${want[@]}"; do
			(( ${adv[(Ie)$k]} )) && adv5+=("$k")
		done

		# A key is BOUND when the picker gave it an action that is not `ignore`.
		for k in r : l h; do
			for a in "${KM_CAPTURED[@]}"; do
				[[ $a == "--bind=${k}:"* ]] || continue
				[[ $a == "--bind=${k}:ignore" ]] || bnd+=("$k")
			done
		done
		# M-a is bound by _hop_pick itself rather than by the modal layer, so it is read separately.
		for a in "${KM_CAPTURED[@]}"; do
			[[ $a == --bind=alt-a:* ]] && bnd+=(M-a)
		done

		local -a out2=("ADV=${(j:,:)adv5}" "BOUND=${(j:,:)bnd}" "HDR=${KM_HEAD}")
		print -rn -- "${(pj:\x1e:)out2}"
	'
}

# The three real callsites, transcribed from hop.zsh rather than invented.
# - _hop_run:        _hop_pick label header query reload root ''    restore up
# - _hop_ws_picker:  _hop_pick label header query ''     ''   drill ''      ''
# - _hop_repo_picker goes through _hop_run with reload, root and restore all empty, and up set.
typeset KM_OV_MAIN KM_OV_REPO KM_OV_WS
KM_OV_MAIN=$(_km_overlay_probe RELOADCMD /some/root '' RESTORECMD _hop_ws_picker)
KM_OV_REPO=$(_km_overlay_probe '' '' '' '' _hop_ws_picker)
KM_OV_WS=$(_km_overlay_probe '' '' drill '' '')

# Asserted first: an overlay that rendered nothing would make every comparison below vacuous.
t 'the overlay probe actually rendered the keys overlay'
assert_eq 'r,:,h,M-a' "$(_km_dump_get "$KM_OV_MAIN" 'ADV=')" 'the main picker advertises four: _hop_run passes no drill target'
assert_nonempty "$(_km_dump_get "$KM_OV_MAIN" 'HDR=')" 'no header reached fzf, so the legend checks prove nothing'

# The invariant, stated once and checked per picker: advertised is exactly bound.
t 'the ? overlay names exactly the gated keys the picker actually bound'
assert_eq "$(_km_dump_get "$KM_OV_MAIN" 'BOUND=')" "$(_km_dump_get "$KM_OV_MAIN" 'ADV=')" 'main picker'
assert_eq "$(_km_dump_get "$KM_OV_REPO" 'BOUND=')" "$(_km_dump_get "$KM_OV_REPO" 'ADV=')" 'repo picker (hop -R)'
assert_eq "$(_km_dump_get "$KM_OV_WS" 'BOUND=')" "$(_km_dump_get "$KM_OV_WS" 'ADV=')" 'workspace picker (hop -w)'

# Exact lists as well as set equality, so a regression that drops BOTH sides at once still fails.
t 'the repo and workspace pickers advertise only the one gated key each really has'
assert_eq 'h' "$(_km_dump_get "$KM_OV_REPO" 'ADV=')" 'hop -R has only h: r, :, l and M-a are all dead there'
assert_eq 'l' "$(_km_dump_get "$KM_OV_WS" 'ADV=')" 'hop -w has only l: r, :, h and M-a are all dead there'

# The NORMAL legend in the list pane, which is the line a user reads before ever pressing `?`.
t 'the NORMAL legend names : view only where a root makes the kind menu real'
assert_contains "$(_km_dump_get "$KM_OV_MAIN" 'HDR=')" ': view'
assert_not_contains "$(_km_dump_get "$KM_OV_REPO" 'HDR=')" ': view' 'hop -R has no root, so : falls through to ignore'
assert_not_contains "$(_km_dump_get "$KM_OV_WS" 'HDR=')" ': view' 'hop -w has no root, so : falls through to ignore'

# The rest of the legend has to survive the edit that removed one token from the middle of it.
t 'dropping : view leaves the rest of the NORMAL legend intact'
assert_eq 'NORMAL  j/k move  g/G top/bot  / search  : view  ? help  enter cd  q quit' \
	"$(_km_dump_get "$KM_OV_MAIN" 'HDR=')"
assert_eq 'NORMAL  j/k move  g/G top/bot  / search  ? help  enter cd  q quit' \
	"$(_km_dump_get "$KM_OV_REPO" 'HDR=')"

# ---------------------------------------------------------------------------
# Tier 2: the transform: action bodies, extracted and run directly as sh.
# ---------------------------------------------------------------------------

# - _km_transform_probe -> \x1e-joined dump of the esc, enter and ? action bodies, with their leading "transform:" stripped, plus every HOP_VIM_* string those bodies read.
# - Captured from inside the real fzf-shadow, before _hop_pick's locals go out of scope.
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
			# Strip UP TO transform:, never from position 0: esc carries static actions in front of it.
			# - esc is clear-query+search()+transform:..., because fzf ignores search() from a transform.
			# - Assuming position 0 left every esc body EMPTY, and an empty body still passed 3 tests.
			case $a in
				--bind=esc:*transform:*) esc_body=${a#*transform:} ;;
				--bind=enter:*transform:*) enter_body=${a#*transform:} ;;
				"--bind=?:"*transform:*) help_body=${a#*transform:} ;;
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
		# Byte counts, so a body the case arms failed to find is named directly, not inferred.
		out+=("LEN_ESC=${#esc_body}")
		out+=("LEN_ENTER=${#enter_body}")
		out+=("LEN_HELP=${#help_body}")
		print -rn -- "${(pj:\x1e:)out}"
	'
}

typeset KM_TF
KM_TF=$(_km_transform_probe)

# This runs FIRST, because sh -c "" exits 0 and prints nothing, so an unextracted body is silent.
# - Every assertion below compares against a body's OUTPUT, which is empty either way.
# - Without this the three esc tests fail with a bare empty diff and never name the real cause.
t 'all three transform bodies were actually extracted from the bind set'
assert_ge "$(_km_dump_get "$KM_TF" 'LEN_ESC=')" 1 'the esc transform body was not found in the bind set'
assert_ge "$(_km_dump_get "$KM_TF" 'LEN_ENTER=')" 1 'the enter transform body was not found in the bind set'
assert_ge "$(_km_dump_get "$KM_TF" 'LEN_HELP=')" 1 'the ? transform body was not found in the bind set'

# Every EXPECT_* below is asserted non-empty BEFORE it is compared, and that is not belt-and-braces.
# - Each pair compares a transform's OUTPUT against the HOP_VIM_* the transform reads, one probe.
# - lib/ui.zsh declares all six as `local -x NAME=''`, so emptying one empties BOTH sides.
# - Measured: blanking HOP_VIM_HELP_ON, HELP_OFF or PICK_KIND each left the suite at 446 passed, 0 failed.
# - So `?` not opening the overlay, `?` not closing it, and enter in `:` not switching kinds all shipped green.
# - TO_NORMAL and MENU_BACK were caught anyway, but by luck elsewhere rather than by these two assertions.
# - TO_NORMAL by the rebind-shape test above; MENU_BACK by esc_act's `:-abort`, which made the sides differ.
# - LEN_* above does NOT cover this: it proves the BODY was extracted, not that it prints anything.

t 'esc in the kind menu goes back to the view you came from'
assert_nonempty "$(_km_dump_get "$KM_TF" 'EXPECT_MENU_BACK=')" 'HOP_VIM_MENU_BACK is empty, so this comparison proves nothing'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_MENU_BACK=')" "$(_km_dump_get "$KM_TF" 'ESC_MENU=')"

t 'esc in SEARCH (input enabled) returns to NORMAL and drops the filter'
assert_nonempty "$(_km_dump_get "$KM_TF" 'EXPECT_TO_NORMAL=')" 'HOP_VIM_TO_NORMAL is empty, so this comparison proves nothing'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_TO_NORMAL=')" "$(_km_dump_get "$KM_TF" 'ESC_SEARCH=')"

t 'esc in NORMAL (input disabled) quits'
assert_eq 'abort' "$(_km_dump_get "$KM_TF" 'ESC_NORMAL=')"

t 'enter in the kind menu switches to the picked kind'
assert_nonempty "$(_km_dump_get "$KM_TF" 'EXPECT_PICK_KIND=')" 'HOP_VIM_PICK_KIND is empty, so this comparison proves nothing'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_PICK_KIND=')" "$(_km_dump_get "$KM_TF" 'ENTER_MENU=')"

t 'enter outside the menu is a plain accept'
assert_eq 'accept' "$(_km_dump_get "$KM_TF" 'ENTER_NORMAL=')"

t '? opens the keys overlay when it is not already showing'
assert_nonempty "$(_km_dump_get "$KM_TF" 'EXPECT_HELP_ON=')" 'HOP_VIM_HELP_ON is empty, so this comparison proves nothing'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_HELP_ON=')" "$(_km_dump_get "$KM_TF" 'HELP_ON=')"

t '? closes the keys overlay and restores the real preview when it is showing'
assert_nonempty "$(_km_dump_get "$KM_TF" 'EXPECT_HELP_OFF=')" 'HOP_VIM_HELP_OFF is empty, so this comparison proves nothing'
assert_eq "$(_km_dump_get "$KM_TF" 'EXPECT_HELP_OFF=')" "$(_km_dump_get "$KM_TF" 'HELP_OFF=')"
