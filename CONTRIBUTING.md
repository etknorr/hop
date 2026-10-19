# Contributing to hop

`hop` is a Go binary plus a small shell function it prints, and the function runs in someone's
interactive shell. That makes the bar "does not break a live terminal", not just "passes CI".

## Running the tests

```sh
go vet ./... && go test ./...
test/shell/run-all.sh
```

`go test` is hermetic: every package runs in a temp `HOME` with the inherited `HOP_*` and `FZF_*`
variables unset, builds synthetic fixture repos, and stubs every external command, so a test can
never open an editor window or a browser tab or write your history. It needs `fzf` and `git`; the
tests that compare against zsh hop 0.3.1 also need `zsh`, and read 0.3.1 from the `v0.3.1` tag, so
fetch tags first. `pty_test.go` drives the real picker on a pseudo-terminal. Run it on fzf 0.60.3,
the floor, as well as your own, by putting an fzf 0.60.3 first on `PATH`.

`test/shell/run-all.sh` runs the shell function, widget and completion in zsh, bash 5, macOS
`/bin/bash` 3.2 and fish. fish runs in docker unless it's on the host or `NO_DOCKER=1` is set.

What can't be asserted, such as how the header wraps at 80 columns, is a manual check in
[docs/SMOKE.md](docs/SMOKE.md). Walk through it after touching `internal/keymap`, `internal/pick`
or the levels in `hop.go`.

New behaviour needs a test. If it can only be checked by hand, add it to `docs/SMOKE.md` instead of
skipping it.

## Parity with zsh hop

`test/parity/` compares this hop with an installed zsh hop 0.3.1 on a real repo, row for row and
jump for jump. Run it after changing `internal/resolve`, `internal/kinds` or `internal/rows`:

```sh
export HOP_PARITY_HOME=<zsh hop 0.3.1 checkout> HOP_PARITY_REPO=<repo> HOP_PARITY_CONFIG=<its config.toml>
test/parity/rows.sh && test/parity/resolve.sh && test/parity/e2e.sh
```

## House style

- `gofmt`, and `go vet` clean.
- No comment unless it names a constraint, a trap or a non-obvious reason. One idea per comment
  line; a `// - ` list of short related points is fine.
- No new dependencies beyond `github.com/BurntSushi/toml`, `golang.org/x/sys` and
  `golang.org/x/term`.
- The shell scripts in `internal/shell/init` and `test/` use TAB indents; `.editorconfig` encodes it.

## Commit messages

One line, subject only, no body. If the change doesn't fit on one line, it is more than one commit.
Match the repo's `git log` style; commit subjects never carry an issue reference.

## Adding a kind

Nearly every family you'd want to navigate is one of the shapes a kind already has: `dirs`, `files`
or `marker`, alone or combined as `[[kind.source]]` tables. Declare it in your own
`~/.config/hop/config.toml`; [Configuring kinds](README.md#configuring-kinds) has the option table
and worked examples. A family too irregular for those gets an `exec` kind, a command that prints the
rows.

Patching the code to add a repo-specific kind is a sign the declaration belongs in your own config.
Nothing repo-specific ships in hop itself, and a recipe in `internal/config/recipes` has to be
useful in repos you've never seen.

## Before opening a pull request

- `go vet ./...`, `gofmt` and `go test ./...` are clean, and so is `test/shell/run-all.sh`.
- Any change to the keymap, the picker or the levels has been walked through
  [docs/SMOKE.md](docs/SMOKE.md) by hand.
- New behaviour has a test, or a stated reason it can't.
