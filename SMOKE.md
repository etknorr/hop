# hop manual smoke checklist

`tests/run` covers everything that can be checked headlessly. Only what needs a real terminal is
here: fzf does not paint into a synthetic pty on this machine, in either height or fullscreen mode,
and two attempts at driving it through one hung until they were killed. Do not script these.

Run after any change to `lib/ui.zsh`, `bin/hop-kinds`, or the keymap. Start clean, because the
modal layer is built from `bind`/`unbind` and a half-reloaded shell hides a restore bug:

Substitute a checkout of your own wherever `$REPO` appears below. Pick a large one: several of
these checks are about what happens when the list is longer than the window.

```zsh
exec zsh && cd "$REPO" && hop
```

## NORMAL mode navigation

- [ ] `j` `j` `k` moves the selection down twice and up once, and the query line stays empty.
- [ ] `g` jumps to the first row, `G` to the last.
- [ ] `^d` then `^u` move a half page down then back.
- [ ] `x` `z` `w` `1` do nothing at all: no insert, no bell, no movement.
- [ ] `l` drills in a level, `h` comes back out to the list you started from.

## The mode boundary, and the rebind that restores it

- [ ] `/` switches the header to `SEARCH` and the prompt to `/`.
- [ ] Type `vpc`: all three letters appear in the query and the list filters.
- [ ] `q` types a literal `q` in SEARCH instead of quitting.
- [ ] `esc` returns the header to `NORMAL` and clears the query.
- [ ] **After that round trip, every verb still works**: `j` `k` `g` `G` `^d` `^u` `p` `r` all act,
      and `o` `O` `e` `y` `Y` `b` each fire once and exit. This is the whole unbind/rebind restore.
- [ ] Do `/` `abc` `esc` twice in a row, then confirm `j` still moves rather than typing.

## Overlays and the view switch

- [ ] `?` fills the preview with the keymap; `j` closes it and the real file preview comes back.
- [ ] `?` `?` toggles the overlay off without leaving a stale `keys` label.
- [ ] `:` opens the kind list in place, `j`/`k` move in it, `enter` switches the view.
- [ ] `:` then `esc` returns to the exact list you came from, row count unchanged.
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
