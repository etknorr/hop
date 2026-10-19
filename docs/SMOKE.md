# hop manual smoke checklist

`go test ./...` covers everything that can be checked without eyes on a screen. `pty_test.go` drives the real fzf on a pseudo-terminal and sends real keystrokes, so the items marked **[auto]** are asserted on every run, on fzf 0.60.3, 0.67.0 and the host's, and only need a human when one of them fails. `internal/keymap` holds every bind byte for byte against zsh hop 0.3.1's.

What stays manual is what has no machine-readable outcome: whether a header wrapped, a column got clipped, or a theme left something unreadable. A pty test runs at one fixed size, so that's the list below.

Run it after any change to `internal/keymap`, `internal/pick` or the levels in `hop.go`. Build the binary from the checkout, and use your own repo wherever `$REPO` appears, a large one, since several checks are about a list longer than the window:

```sh
go build -o bin/hop . && cd "$REPO" && eval "$(/path/to/checkout/bin/hop init zsh --cmd hopdev)" && hopdev
```

`--cmd hopdev` keeps an installed `hop` untouched. Keep your real history out of the run with `export HOP_HISTFILE=$(mktemp)`.

## NORMAL mode navigation

- [ ] **[auto]** `j` `j` `k` moves the selection down twice and up once, the query line still empty.
- [ ] `g` jumps to the first row, `G` to the last.
- [ ] `^d` then `^u` move half a page down, then back.
- [ ] `x` `z` `w` `1` do nothing: no insert, no bell, no movement.

## The mode boundary, and the rebind that restores it

- [ ] **[auto]** `/` switches the header to `SEARCH` and the prompt to `/`, and typed letters filter.
- [ ] `q` types a literal `q` in SEARCH instead of quitting.
- [ ] **[auto]** `esc` returns the header to `NORMAL`, keeps the query, and `j` walks the filtered rows.
- [ ] After that `esc` the kept query is still visible after the `> ` prompt.
- [ ] **[auto]** A second `esc` brings every row back, and a third quits with status 0.
- [ ] `/` after that first `esc` is SEARCH again with the query, and a letter lands at its end.
- [ ] After the round trip every key still acts: `j` `k` `g` `G` `^d` `^u` `p` `r`, and `o` `O` `e` `y` `Y` `b` `c` each fire once and exit. **[auto]** for `j` and the seven verbs.
- [ ] `/` `abc` `esc` twice in a row, then `j` still moves rather than typing.
- [ ] **[auto]** `/` `zzz` `esc` shows NORMAL with no rows and `zzz` kept, and a second `esc` brings every row back.

## Overlays and the view switch

- [ ] **[auto]** `?` fills the preview with the keymap, and `j` closes it and the file preview comes back.
- [ ] `?` `?` toggles the overlay off without leaving a stale ` keys ` label.
- [ ] The overlay fits a narrow preview pane (under 50 columns) without wrapping.
- [ ] `:` opens the kind list in place, `j`/`k` move in it, `enter` switches the view.
- [ ] **[auto]** `:` then `esc` returns to the list you came from, and `enter` still cds.
- [ ] **[auto]** `:` then `/` filters the kind list, and `enter` there switches to the kind.
- [ ] `:` `/` `esc` is back in the menu's NORMAL with the filter kept; one more `esc` leaves the menu.
- [ ] After `:` switched to a kind, `r` reloads that kind, and `:` `esc` comes back to it.
- [ ] `/` `vpc` `esc` then `:` lists every kind, not none, because `:` drops the kept query.

## Layout

- [ ] At 80 columns the NORMAL and SEARCH headers each show three short lines, none wrapped or clipped mid-word.
- [ ] At 200 columns each header is one line.
- [ ] At 80 columns the name column is readable, not pushed off by the scope column.
- [ ] Resize the terminal with the picker open: the headers keep the width hop measured at start, as zsh hop's did.

## Resolving a query

- [ ] `hop acct sec prod`, or any query whose words name an ancestor dir, opens with that dir first, then its children; the first key you type re-sorts into fzf's order.
- [ ] A typo, such as `hop securty-tooling-prod` in a repo with `security-tooling-prod`, opens with `no exact match for: ... (showing: ...)` as the header's first line, above the SEARCH legend.
- [ ] `hop zzqx` opens on the query with `nothing close to: zzqx (esc twice clears)`, and `esc` `esc` does clear it.
- [ ] On fzf 0.67.0 or later, type a long path so the list scrolls along it: the name column stays visible.
- [ ] The dim path column is readable on both a light and a dark theme.
- [ ] `r`, `alt-a` and `:` then a kind, from `hop -c` in a subdirectory, each keep only rows under it.

## The Enter action and VS Code

`internal/act` asserts every `code` command line hop runs. Where VS Code puts the result is VS Code's business, so these need a real window. Start with `HOP_ACTION` unset unless a line says otherwise:

- [ ] `HOP_ACTION=open hop` shows `enter open` in the legend, with `c cd` in NORMAL and `M-enter cd` in SEARCH.
- [ ] Under that mode, `c` in NORMAL and `alt-enter` in SEARCH each cd without opening anything. **[auto]** for `c`.
- [ ] `hop -o` on a file in a repo open in another window: the file lands in that repo's window.
- [ ] `hop -o` on a directory whose folder is already open focuses that window instead of a new one.
- [ ] Over SSH with no VS Code attached, and with `VSCODE_IPC_HOOK_CLI` pointing at a dead socket, `hop --cd -o x` prints one notice and still cds.
- [ ] In a VS Code Remote-SSH terminal, `hop -o` reaches the window rather than falling back.

## Escape hatches and the guard

- [ ] `HOP_VIM=0 hop` opens search-first: letters type at once, the prompt is `hop ▸ ` and there is no mode name.
- [ ] `HOP_VIM=0 hop --vim` forces the modal layer back on, and `hop --no-vim` turns it off.
- [ ] In a terminal that answers colour queries (OSC 11), opening the picker never runs `b`, `e` or `y` by itself. **[auto]** for forged replies of seven escape classes.
- [ ] Press `alt-x` then `b` within a blink: `b` is ignored. Wait a moment and `b` browses.

## The levels

- [ ] `hop -w` shows one row per configured workspace, with `~` for `$HOME` and a repo count.
- [ ] **[auto]** `l` drills into a workspace's repos, `l` again into a repo's targets, and `h` `h` comes back out.
- [ ] **[auto]** In a repo, `h` from the targets goes to every repo, and `h` again to the workspaces.
- [ ] Drilling into a repo doesn't cd; only the final `enter` does. **[auto]**
- [ ] With `HOP_VIM=0`, `ctrl-l` and `ctrl-h` make the same moves. **[auto]**
- [ ] `b` on a workspace row prints the hint to press `l`.
- [ ] `hopw` inside a repo lands in the workspace holding it, the innermost when two nest.
- [ ] `hopw` from `/tmp` prints the "not inside any configured workspace" error and doesn't cd.
- [ ] `cd /tmp && hop` opens the workspace picker, not the repo picker.

When one of these fails, move whatever part of it doesn't need eyes into `pty_test.go`.
