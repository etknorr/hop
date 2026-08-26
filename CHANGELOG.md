# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project adheres to
[Semantic Versioning][semver].

## [Unreleased]

### Fixed

- The copy verb (`ctrl-y`/`alt-y`) no longer reports `hop: copied <path>` when the clipboard
  command itself fails; it now names the failing tool on stderr and returns non-zero.
- The edit verb (`alt-o`) no longer rejects an absolute-path `$EDITOR`/`$VISUAL` (e.g.
  `/opt/homebrew/bin/nvim`) as "not installed"; a path is now checked for existence and the
  executable bit instead of a `$PATH` lookup.
- Four test assertions that could not fail, letting a shipped behaviour regress with the suite green.
  The `--help` check for the opt-in `file` kind matched the usage line rather than the kinds registry,
  so starring every kind still passed. Three modal-keymap checks compared a transform's output
  against the same `HOP_VIM_*` variable the transform reads, and `lib/ui.zsh` declares those empty,
  so `?` never opening the keys overlay, `?` never closing it and `enter` never switching kinds in
  the `:` menu were each shippable without one failing test.
- Two more keymap assertions of the same shape, for `HOP_VIM_TO_NORMAL` and `HOP_VIM_MENU_BACK`.
  Neither regression could actually ship: a sibling test caught the first, and `esc`'s own `:-abort`
  default caught the second. These now name the cause instead of leaving it to be inferred.
- `HOP_CONFIG` and `HOP_HOPRC` are now exported, and `HOP_CONFIG` is forwarded explicitly into the
  reload child alongside `HOP_HOME`. Both were plain shell parameters, so a `HOP_CONFIG=~/mine.zsh`
  line in `.zshrc` never reached the two children that re-source `hop.zsh` to rebuild the kind
  registry: the `zsh -f` reload shell and `bin/hop-kinds`. Your own kinds vanished in exactly the
  places that depend on those, so the `:` view menu listed the eight shipped presets instead of your
  kinds, and `alt-a` or `r` printed `hop: unknown kind: <yours>` and blanked the picker. The reload
  child keeps `zsh -f`, which is why each variable is named one at a time rather than pulled in by
  letting the child read rc files.
- `hop -c`/`--cwd`/`--here` now resolves `$PWD` before matching it against the row paths, so it finds
  targets in a repo reached through a symlink. `$PWD` is logical while the rows are built from git's
  physical `--show-toplevel`, so the two never matched and every row was dropped: `hop -c` reported
  `hop: no targets under <dir>` and exited 1 in a subtree that plainly had them. This hit every repo
  under macOS `/tmp` and any checkout below a symlinked parent. `_hop_act_browse` already fixed this
  same class with `${1:A}`. The filter is also pure zsh now rather than `awk -F'\t' -v p="$PWD"`,
  because `awk -v` escape-processes the value it is handed, so a directory whose name contained a
  backslash silently matched nothing.
- The workspace picker (`-w`/`--workspaces`) now reads fzf's exit status, which it previously skipped
  entirely. `hop -w somequery` matching nothing printed nothing and exited 0, and a too-old fzf, a
  rejected key bind or an unreachable `/dev/tty` were all indistinguishable from pressing `esc`. The
  ladder that `_hop_run` already had is now a shared `_hop_fzf_status`, so the two pickers cannot
  drift apart again, and `esc` stays silent in both.
- `HOP_DEBUG=1` now logs every pick, not only a successful key dispatch. The single `_hop_dbg` call
  sat inside `_hop_dispatch`, so every failure that happened *before* a dispatch wrote nothing at
  all: fzf exiting 1 or 130, an empty target set, a version rejection, a tty problem. The diagnostic
  was structurally blind to precisely the failures people file bugs about, and a real `hop: no match`
  added no line for `hop --doctor` to show. Each pick now logs its label, row count, query and exit
  status.
- The test suite no longer inherits the settings of whoever runs it. An exported `HOP_FZF_MIN`,
  `HOP_VIM`, `HOP_HOPRC` or `HOP_REPOS` made it fail or hang, an inherited `HOP_FZF_HEIGHT` started
  fzf against no terminal and orphaned it, and `FZF_DEFAULT_OPTS` silently disabled the control arm
  of the `--exact` guard. Every setting is pinned from one list now, rather than from three helpers
  that each kept their own and drifted, and a test derives that list from the source so it cannot.
- The suite's per-child timeout is a real bound again. Five call sites used a shape where the timer
  lived inside the process being timed, so a child that ignored the signal ran unbounded and its
  grandchildren outlived the run. The timer now sits outside it and kills the whole process group.

## [0.1.0] - 2026-08-25

First release.

### Added

- `hop`, a modal, fzf-driven navigator for large configuration monorepos: enumerates deployable
  units instead of walking directories, and `cd`s to the one you meant.
- The `hop_kind` DSL for declaring a family of navigable things, in four shapes: `--dirs` (child
  directories of a base), `--files` (tracked files matching a pathspec), `--marker` (any directory
  containing a given file), and `--fn` (a hand-written provider for irregular families).
- Shipped presets covering common config-repo layouts: `terragrunt`, `terraform-modules`, `helm`,
  `serverless`, `puppet`, `backstage`, `dir` and `file`.
- A modal fzf UI in the style of `k9s` and vim: NORMAL mode where keys are verbs, `/` for SEARCH,
  and `:` to switch kinds in place without a nested fzf process.
- `HOP_FZF_HEIGHT` sets the picker's height, defaulting to the previous hardcoded `80%`. An empty
  value drops `--height` entirely and gives fzf the whole screen.
- Workspaces: `-w`/`--workspaces` to pick a workspace root and drill into its repos, and `hopw` to
  `cd` to the workspace containing `$PWD`, deepest match winning.
- `hopr` to `cd` to the repo root, `hop -` for `cd -`, and the `^G`/`alt-g` widget to launch `hop`
  from a half-typed command line without losing it.
- `-c`/`--cwd`, `-k`/`--kinds`, `-a`/`--all` and `-R`/`--repos` to narrow or widen a search.
- `hop -V`/`--version`, which prints the contents of `VERSION` plus a `git describe` suffix when
  the install is a git checkout. `hop upgrade` reads that same file, so it is the release contract
  other tooling depends on.
- `hop --doctor` and `HOP_DEBUG=1` for bug reports: install path, config, tool versions, workspace
  membership, live kind counts, and the last 15 dispatched keys.
- `hop --doctor=short`, a paste-safe diagnostic mode for public bug reports: it omits `PWD`, the
  git toplevel, workspace names and paths, and kind names, replacing them with counts, and shows
  a config path only when it still matches hop's shipped default.
- `hop upgrade`, which moves a manual clone onto a release. Bare `hop upgrade` fast-forwards local
  `main` and stays on it, so `git pull` keeps working; `hop upgrade 0.1.0` pins to that tag,
  detached. `hop upgrade --check` reports installed versus released and changes nothing. It refuses
  rather than acts on a dirty tree, a side branch, a non-tag detached HEAD, a missing `origin`, a
  diverged `main`, or an untracked file the release also ships, and it never cleans, resets, merges
  or forces anything.
- `hop.plugin.zsh`, the filename plugin managers look for, so `hop` needs no per-manager
  configuration. It sources `hop.zsh` and nothing else.
- A real install section in the README covering zinit, antidote, sheldon, oh-my-zsh and a manual
  clone, each shown both unpinned and pinned to a release tag.
- Repo governance for the now-public project: README badges (CI, MIT license, zsh), a
  `CONTRIBUTING.md`, GitHub issue and pull request templates, and a `.editorconfig` matching the
  project's real per-file indentation.
- MIT license.

### Fixed

- `HOP_HOME` is now derived unconditionally from `hop.zsh`'s own path rather than inherited from
  the environment, so a stale exported value can no longer point a sourced shell at the wrong
  install.
- The copy verb (`y`/`Y`, `ctrl-y`/`alt-y`) no longer hard-requires `pbcopy`: it now falls back to
  `wl-copy`, `xclip`, `xsel`, or `clip.exe`, so it works on Linux (Wayland or X11) and WSL, not just
  macOS. `HOP_CLIPBOARD` overrides the probe entirely for a custom clipboard command.
- `esc` out of a non-matching SEARCH query no longer lands you in NORMAL with a permanently empty
  list, where every navigation key did nothing and a verb acted on an empty selection.
  `disable-search` only stops future matching, so nothing re-filtered. The transition now runs
  `clear-query+search()` as static actions on the `esc` bind itself rather than from inside the
  mode-transition string: fzf does not honour a `search()` emitted by a `transform:`, and `esc` has
  to be a transform in order to tell its three meanings apart.
- An fzf older than 0.60.3 is now refused with an explanation naming the version found, the version
  needed, and the upstream download, instead of failing as a bare `unknown option: --accept-nth`.
  `--accept-nth` arrived in fzf 0.60.0 and only worked alongside `--select-1` from 0.60.3, and the
  picker passes both. Debian and Ubuntu package 0.44.x. `HOP_FZF_MIN` overrides the floor, the
  version is read at most once per shell, and a version hop cannot parse proceeds rather than
  blocking.

[keepachangelog]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
[Unreleased]: https://github.com/etknorr/hop/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/etknorr/hop/releases/tag/v0.1.0
