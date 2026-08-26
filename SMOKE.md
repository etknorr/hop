# hop manual smoke checklist

`tests/run` covers everything that can be checked without eyes on a screen, and that is now more
than this file used to claim. `tests/suite_pty.zsh` drives the real picker through a `zsh/zpty`
pseudo-terminal and sends real keystrokes, so the items marked **[auto]** below are asserted on
every run and only need a human when one of them fails.

Two earlier attempts at scripting this hung, and the diagnosis in this file used to be that fzf
cannot paint into a synthetic pty. That was wrong twice over. In `--height` mode fzf emits a
cursor-position request and blocks forever on a reply `zsh/zpty` never sends, which is why
`HOP_FZF_HEIGHT=` and fullscreen are mandatory there. Separately, nothing was draining the pty's
output side, so fzf filled the buffer, blocked in `write()` and silently dropped every later
keystroke. Neither problem is fzf refusing to run.

What is genuinely still manual is what has no machine-readable outcome. `zsh/zpty` cannot set a
window size, so nothing automated can judge whether a header wrapped, a column got clipped, or the
layout is readable at all. That is the list below.

Run after any change to `lib/ui.zsh`, `bin/hop-kinds`, or the keymap. Start clean, because the
modal layer is built from `bind`/`unbind` and a half-reloaded shell hides a restore bug:

Substitute a checkout of your own wherever `$REPO` appears below. Pick a large one: several of
these checks are about what happens when the list is longer than the window.

```zsh
exec zsh && cd "$REPO" && hop
```

## NORMAL mode navigation

- [ ] **[auto]** `j` `j` `k` moves the selection down twice and up once, query line still empty.
- [ ] `g` jumps to the first row, `G` to the last.
- [ ] `^d` then `^u` move a half page down then back.
- [ ] `x` `z` `w` `1` do nothing at all: no insert, no bell, no movement.
- [ ] `l` drills in a level, `h` comes back out to the list you started from.

## The mode boundary, and the rebind that restores it

- [ ] **[auto]** `/` switches the header to `SEARCH` and the prompt to `/`.
- [ ] **[auto]** Type `vpc`: all three letters appear in the query and the list filters.
- [ ] `q` types a literal `q` in SEARCH instead of quitting.
- [ ] **[auto]** `esc` returns the header to `NORMAL` and clears the query.
- [ ] **After that round trip, every verb still works**: `j` `k` `g` `G` `^d` `^u` `p` `r` all act,
      and `o` `O` `e` `y` `Y` `b` each fire once and exit. This is the whole unbind/rebind restore.
      `j` and `o` are **[auto]**; the other twelve keys are still yours to check.
- [ ] Do `/` `abc` `esc` twice in a row, then confirm `j` still moves rather than typing.
- [ ] `/` `zzz` `esc` leaves a list you can still navigate, rather than a dead empty one.

## Overlays and the view switch

- [ ] `?` fills the preview with the keymap; `j` closes it and the real file preview comes back.
- [ ] `?` `?` toggles the overlay off without leaving a stale `keys` label.
- [ ] `:` opens the kind list in place, `j`/`k` move in it, `enter` switches the view.
- [ ] **[auto]** `:` then `esc` returns to the list you came from, and `enter` still `cd`s.
- [ ] `:` then `/` filters the kind list, and `esc` still goes back rather than quitting.

## Layout

- [ ] At 80 columns the header shows three short lines and no line wraps or is clipped mid-word.
- [ ] At 80 columns the name column is still readable, not pushed off by the scope column.

## Escape hatches

- [ ] `HOP_VIM=0 hop` opens search-first: letters type immediately and there is no mode name.
- [ ] `HOP_VIM=0 hop --vim` forces the modal layer back on.
- [ ] `^G` on an empty prompt opens hop; `alt-g` opens it and the half-typed line survives.

## The workspace level

`tests/suite_workspaces.zsh` already covers parsing, `~`/`$VAR` expansion, precedence,
longest-prefix resolution and the repo count, so a wrong path here is a unit bug. Only the picker
needs eyes:

- [ ] `hop -w` shows one row per line in `~/.config/hop/workspaces`, with `~` for `$HOME`.
- [ ] Each row's repo count matches what `ls` in that workspace actually holds.
- [ ] `enter` cds to the workspace itself; `l` drills in and lists only that workspace's repos.
- [ ] `h` from those repos comes back out to the workspace list.
- [ ] `hopw` inside `$REPO` lands in the workspace holding it, not in that workspace's parent.
- [ ] `hopw` from `/tmp` prints the "not inside any configured workspace" error and does not cd.
- [ ] `cd /tmp && hop` with no args opens the workspace picker, not the repo picker.
- [ ] Adding or commenting out a line in the config changes the next `hop -w`, with no reload.

When one of these fails, move whatever part of it does not need a terminal into `tests/`.
