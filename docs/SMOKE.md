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
- [ ] **[auto]** `esc` returns the header to `NORMAL` and keeps the query, and the list stays filtered.
- [ ] After that `esc` the kept query is still visible on the prompt line, after the `> ` prompt.
- [ ] **[auto]** `j` then `enter` cds to the second row of the filtered list, not of the full one.
- [ ] **[auto]** A second `esc` clears the query and brings every row back, and a third `esc` quits.
- [ ] **[auto]** `/` after that first `esc` is SEARCH again with the query, and a letter lands at its end.
- [ ] **After that round trip, every verb still works**: `j` `k` `g` `G` `^d` `^u` `p` `r` all act,
      and `o` `O` `e` `y` `Y` `b` each fire once and exit. This is the whole unbind/rebind restore.
      `j` and `o` are **[auto]**; the other twelve keys are still yours to check.
- [ ] Do `/` `abc` `esc` twice in a row, then confirm `j` still moves rather than typing.
- [ ] **[auto]** `/` `zzz` `esc` shows NORMAL with no rows and `zzz` still in the query, and a second
      `esc` brings every row back rather than leaving a dead empty list.

## Overlays and the view switch

- [ ] `?` fills the preview with the keymap; `j` closes it and the real file preview comes back.
- [ ] `?` `?` toggles the overlay off without leaving a stale `keys` label.
- [ ] `:` opens the kind list in place, `j`/`k` move in it, `enter` switches the view.
- [ ] **[auto]** `:` then `esc` returns to the list you came from, and `enter` still `cd`s.
- [ ] `:` then `/` filters the kind list, and `esc` still goes back rather than quitting.
- [ ] `/` `vpc` `esc` then `:` lists every kind, not none, because `:` drops the kept query.

## Layout

- [ ] At 80 columns the header shows three short lines and no line wraps or is clipped mid-word.
- [ ] At 80 columns the name column is still readable, not pushed off by the scope column.

## Resolving a query

`tests/suite_match.zsh` covers which tier and rule every query gets, and what the picker is handed.
What it cannot see is how the opened picker looks and behaves under real keys:

- [ ] `hop acct sec prod` opens with the account dir first, then its units; the first key you type
      re-sorts the list into fzf's own order; `esc` into NORMAL keeps the filtered rows, and a second
      `esc` shows every row.
- [ ] `hop securty-tooling-prod` opens with `no exact match for: ... (showing: ...)` as the header's
      first line, above the mode legend, and the legend is still intact after `esc` and `/`.
- [ ] On fzf 0.67.0 or later, type `terraform/acct-sec` so the list scrolls along the path: the name
      column stays visible. Check an 80-column terminal too.
- [ ] The dim path column is readable on both a light and a dark theme.
- [ ] On fzf 0.60.3 (`PATH=<dir holding 0.60.3>:$PATH`), Enter on a row from `hop vpc` cds to it:
      the picker passes `--no-sort` and `--accept-nth=2,3,4` together there.
- [ ] `r`, `alt-a` and `:` then a kind, from `hop -c` in a subdirectory, each keep only rows under it.

## The Enter action and VS Code

`tests/suite_actions.zsh` asserts every `code` command line hop runs. Where VS Code puts the result
is VS Code's business, so these need a real window. Start with `HOP_ACTION` unset unless a line says
otherwise:

- [ ] `HOP_ACTION=open hop` shows `enter open` in the legend, with `c cd` in NORMAL and `M-enter cd`
      in SEARCH; at 80 columns both legends re-flow to three lines without clipping.
- [ ] Under that mode, `c` in NORMAL and `alt-enter` in SEARCH each cd without opening anything.
- [ ] `hop -o` on a file in a repo that is open in a window other than the focused one: the file
      lands in that repo's window and the explorer reveals it.
- [ ] `hop -o` on a file outside every open folder opens it as a loose tab.
- [ ] `hop -o` on a directory whose folder is already open focuses that window instead of a new one.
- [ ] `hop -e` on a tg leaf expands the unit in the repo's window, and `hop -e security-tooling-prod`
      reveals `terragrunt_aws_account.hcl`.
- [ ] Over SSH with no VS Code attached, and with `VSCODE_IPC_HOOK_CLI` pointing at a dead socket,
      `hop --cd -o vpc prod` prints one notice and still cds.
- [ ] In a VS Code Remote-SSH terminal, `hop -o` reaches the window rather than falling back.
- [ ] With `HOP_ACTION=cd+reveal`, hop a few times: note whether each `code -r` opens a preview
      tab that the next one replaces, or a tab that stays.

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
