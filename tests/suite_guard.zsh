#!/usr/bin/env zsh
# suite_guard: bin/hop-guard on its own, with no fzf and no terminal anywhere near it.
# - The guard decides whether a keystroke was the user's or a terminal's, from when it arrived.
# - Its whole contract is "print an action or print ignore", so it is testable as a plain binary.
# - suite_pty_escape.zsh proves the guard works through fzf; this proves it works at all.
# - Every fail-open path is asserted, because failing CLOSED would swallow real keypresses.

typeset -g G_BIN="$HOP_HOME/bin/hop-guard"

t 'bin/hop-guard is executable'
assert_exec "$G_BIN"

typeset REPLY
fixture_tmpdir guard-state
typeset -g G_DIR=$REPLY
typeset -g G_MARK="$G_DIR/mark"

# g_check [env-assignments...] -> what `check` prints for a fixed action, run as a real process.
# - The action is the exact string lib/ui.zsh wraps, so a quoting regression shows up here.
typeset -g G_ACT='print(ctrl-o)+accept'
g_check() {
	emulate -L zsh
	env "$@" "$G_BIN" check "$G_MARK" "$G_ACT"
}

# ---------------------------------------------------------------------------
# mark, and the window it opens.
# ---------------------------------------------------------------------------
t 'mark writes a clock reading a check can compare against'
rm -f -- "$G_MARK"
"$G_BIN" mark "$G_MARK"
typeset g_stamp=''
[[ -r $G_MARK ]] && read -r g_stamp < "$G_MARK"
assert_nonempty "$g_stamp" 'mark wrote nothing, so every check below would fail open and prove nothing'
assert_eq '' "${g_stamp//[0-9.]/}" 'the mark must be a bare clock reading, digits and one dot only'

t 'a verb landing inside the window is refused'
"$G_BIN" mark "$G_MARK"
assert_eq 'ignore' "$(g_check)" 'a verb microseconds after an unparsed escape must not run'

t 'the same verb outside the window runs untouched'
"$G_BIN" mark "$G_MARK"
sleep 0.3
assert_eq "$G_ACT" "$(g_check)" 'a real keypress 300ms later was swallowed, which is the worse failure'

# The window is what separates the two populations, so it has to be the thing under test.
t 'the window is a real threshold, not a constant answer'
"$G_BIN" mark "$G_MARK"
assert_eq 'ignore' "$(g_check HOP_GUARD_WINDOW=5)" 'a 5s window must refuse a verb that lands immediately'
"$G_BIN" mark "$G_MARK"
sleep 0.1
assert_eq "$G_ACT" "$(g_check HOP_GUARD_WINDOW=0.01)" 'a 10ms window must let a verb 100ms later through'

# ---------------------------------------------------------------------------
# Re-arming, which is what makes one mark cover a payload of any length.
# ---------------------------------------------------------------------------
# Measured under a pty: payload letters arrive 15-22ms apart, each costing this script one fork.
# - Measured from the introducer alone, a 20-letter payload reaches 380ms and breaks through.
# - So a refusal has to push the window forward, and that is asserted here rather than assumed.
t 'a refused verb pushes the window forward, so a long payload cannot outlast it'
"$G_BIN" mark "$G_MARK"
typeset g_first g_second
read -r g_first < "$G_MARK"
assert_eq 'ignore' "$(g_check)" 'the first payload letter was not refused'
read -r g_second < "$G_MARK"
assert_eq 1 $(( g_second > g_first )) 'a refusal left the mark untouched, so the window never re-arms'

t 'a verb that RUNS does not re-arm, so the chain ends at the first real keypress'
"$G_BIN" mark "$G_MARK"
sleep 0.3
typeset g_before g_after
read -r g_before < "$G_MARK"
assert_eq "$G_ACT" "$(g_check)" 'the verb outside the window did not run'
read -r g_after < "$G_MARK"
assert_eq "$g_before" "$g_after" 'a passing verb moved the mark, which could quarantine the next key'

# ---------------------------------------------------------------------------
# Every fail-open path, because failing CLOSED loses real keypresses.
# ---------------------------------------------------------------------------
t 'no mark at all means no escape arrived, so the verb runs'
rm -f -- "$G_MARK"
assert_eq "$G_ACT" "$(g_check)" 'a picker that has seen no escape must not guard anything'

t 'an unreadable state file fails open rather than closed'
assert_eq "$G_ACT" "$("$G_BIN" check "$G_DIR/nonexistent/mark" "$G_ACT")" 'a bad path must not swallow the verb'

t 'a corrupt mark fails open instead of aborting'
print -rn -- 'notanumber' > "$G_MARK"
assert_eq "$G_ACT" "$(g_check)" 'a garbage mark must be treated as no mark'

t 'a mark from the future fails open, so a backwards clock cannot quarantine the verbs'
print -rn -- '99999999999.0' > "$G_MARK"
assert_eq "$G_ACT" "$(g_check)" 'a negative age must pass, or a clock change disables hop until it catches up'

t 'a malformed window falls back to the default instead of aborting'
"$G_BIN" mark "$G_MARK"
assert_eq 'ignore' "$(g_check HOP_GUARD_WINDOW=abc)" 'a garbage window must fall back, not crash or disable'
assert_eq 'ignore' "$(g_check HOP_GUARD_WINDOW=0.1.5)" 'a two-dot window must fall back, not abort the caller'

t 'HOP_GUARD_WINDOW=0 is the off switch a timing heuristic has to have'
"$G_BIN" mark "$G_MARK"
assert_eq "$G_ACT" "$(g_check HOP_GUARD_WINDOW=0)" 'the escape hatch did not disable the guard'

t 'check with no action prints nothing, rather than inventing an ignore'
"$G_BIN" mark "$G_MARK"
assert_empty "$("$G_BIN" check "$G_MARK")" 'a missing action must not become a bind that does something'

t 'an unknown subcommand is silent and successful, since fzf shows a bind error as a dead key'
assert_status 0 "$G_BIN" nonsense "$G_MARK"
assert_empty "$("$G_BIN" nonsense "$G_MARK" 2>&1)" 'a typo in a bind string must not paint an error into the picker'
