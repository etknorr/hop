# Contributing to hop

`hop` is a zsh function, not a binary, so a change here lands directly in someone's interactive
shell. That makes the bar "does not break a live terminal", not just "passes CI".

## Running the suite

```zsh
tests/run
```

The suite is headless and hermetic: it builds synthetic fixture repos rather than reading your
real checkouts, and it stubs every external command so a test can never open an editor window or
a browser tab. Run a subset with a pattern, matched against suite filenames first and test names
second:

```zsh
tests/run dsl
tests/run 'kind menu'
```

Nothing in `tests/` may launch interactive `fzf` — `fzf --filter` is the only permitted mode,
because a real fzf process blocks on `/dev/tty` and hangs a headless run. Anything that genuinely
needs a terminal is a manual check in [SMOKE.md](SMOKE.md), not a test. Run through SMOKE.md after
touching `lib/ui.zsh`, `bin/hop-kinds`, or the keymap; nothing else exercises the modal layer.

New behaviour needs a test in `tests/`. If it can only be checked by hand, add it to SMOKE.md
instead of skipping it.

## House style

- **TAB indent**, everywhere except `completions/_hop`, which follows zsh's own completion-function
  convention of 2-space indent. `.editorconfig` encodes both.
- **`emulate -L zsh` as the first line of every function.** Without it, a function inherits
  whatever options the caller's shell happens to have set, which is exactly the kind of bug that
  only reproduces in someone else's `.zshrc`.
- **Quote every expansion.** `"$var"`, `"${arr[@]}"`, `"$(cmd)"`. An unquoted expansion is a
  word-splitting bug waiting for a path with a space in it.
- **One idea per comment line, and never wrap a comment to a column limit.** Break a comment where
  the thought breaks, not where a line-length rule says to. A `# - ` bulleted list of short, related
  points is fine; two consecutive prose sentences crammed onto one line, or one sentence sliced
  across two lines to fit a column, are not.
- Match the file you're editing. `lib/dsl.zsh`, `lib/ui.zsh`, and the presets are the clearest
  examples of the conventions above in practice.

## Commit messages

**One line, subject only, no body.** If the change does not fit on one line, it is more than one
commit. Match the repo's existing `git log` style; there is no ticket system wired into this repo,
so commit subjects never carry an issue reference.

## Adding a kind

Nearly every family you'd want to navigate is one of the shapes `hop_kind` already knows: `--dirs`,
`--files`, or `--marker`. Declare it in `$HOP_CONFIG` (`~/.config/hop/config.zsh` by default) —
see [Configuring kinds](README.md#configuring-kinds) in the README for the full option table and
worked examples. A family too irregular for the three shapes gets `--fn` and a hand-written
provider function in `lib/providers.zsh`, which is still a first-class kind everywhere: `--help`,
the `:` menu, and completions.

Patching the code to add a repo-specific kind is a sign the declaration belongs in your own
`config.zsh` instead — nothing repo-specific should ship in `hop` itself.

## Before opening a pull request

- `tests/run` is green.
- Any change to `lib/ui.zsh`, `bin/hop-kinds`, or the keymap has been walked through
  [SMOKE.md](SMOKE.md) by hand.
- New behaviour has a test in `tests/`, or a documented reason it can't.
