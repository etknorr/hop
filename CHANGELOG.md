# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project adheres to
[Semantic Versioning][semver].

## [Unreleased]

### Changed

- The browse verb moved off `ctrl-g` and onto `alt-B` in SEARCH, because `ctrl-g` was reachable with
  no keypress at all. A single BEL byte (`0x07`) in anything a program prints arrives at fzf as
  `ctrl-g`, and hop passed `ctrl-g` on `--expect`, so a stray bell ran `gh browse` and opened a
  browser tab. `--expect` is passed unconditionally, so neither `HOP_VIM=0` nor `--no-vim` protected
  against it the way they protect the NORMAL-mode letters. `ctrl-g` is now bound to `ignore` rather
  than merely dropped: unbound, fzf's own default for it is `abort`, so the same bell would have
  closed the picker instead. `b` in NORMAL is unchanged.

  This also retires a documented confusion. `^G` launches hop from the shell, so `ctrl-g` *inside*
  hop read as "do that again" when it was really the browse verb. It now means nothing there.

### Added

- An escape guard, so bytes a *terminal* prints can no longer run a hop verb. fzf cannot decode every
  escape sequence that arrives on its input, and the ones it cannot parse are delivered as ordinary
  keystrokes. In NORMAL mode letters are verbs, so a terminal answering a background-colour query with
  `\e]11;rgb:1e1e/1e1e/1e1e\e\\` typed `11;rgb:1e1e/1e1e/1e1e` into the picker and the `b` in `rgb`
  ran `gh browse`. An `\e]52;...` clipboard reply reached the copy verb through its `Y` and clobbered
  the real clipboard; a `\eP...` version reply, which every modern terminal answers, reached `$EDITOR`
  through its `e`. Each of these was reproduced under a pty, not inferred.

  fzf does surface the part it could not parse: an unrecognised `ESC <char>` becomes a bindable
  `alt-<char>`, so `\e]` arrives as `alt-]`. Every such key hop does not already own now stamps a
  clock, and every action that would leave the picker checks that stamp first. Measured on the
  development machine, forged letters arrive about 20ms apart, which is the cost of the check's own
  fork, while a real keypress follows the previous one by however long the user took. The threshold is
  `HOP_GUARD_WINDOW`, default 150ms, and `HOP_GUARD_WINDOW=0` disables the guard. It fails open on a
  missing clock, a missing stamp or a malformed window, because swallowing a real keypress is worse
  than the nuisance it prevents. Nine actions are covered, which is every one that leaves the picker
  rather than only the six letter verbs, so a stray `q` cannot close it either.

  Navigation stays deliberately outside the guard: `j`, `k`, `g` and `G` must not fork a process on
  every cursor move, and `/` and `:` are both undone by `esc`. A hostile sequence can therefore still
  scroll the list or switch mode. It can no longer open an editor, write the clipboard or open a
  browser tab.

  Three gaps remain, all nuisance-level and all documented in the README. A bracketed paste wraps its
  payload in `\e[200~` and `\e[201~`, which fzf parses and silently discards, leaving no introducer to
  hook; it also needs a deliberate paste, and NORMAL mode has search off so pasting there is
  meaningless. Raw `\b` and `\f` still read as `ctrl-h` and `ctrl-l`, which are `--expect` keys;
  `--expect` outranks every bind and so cannot be guarded. Both are in-picker level navigation, and
  moving the remaining `--expect` keys onto guarded binds is queued for 0.2.0. And a bare `ESC` byte
  still closes the picker, since `esc` in NORMAL means quit; `esc` is deliberately left unguarded
  because if `bin/hop-guard` ever went missing a `transform:` would yield no action and take all nine
  guarded keys down with it, leaving `esc` as the only way out.

### Fixed

- The picker no longer advertises keys it left bound to `ignore`. Five NORMAL-mode keys are gated on
  whether the calling picker had anything for them to do: `r` needs a restore command, `:` a root to
  enumerate kinds from, `l` a drill target, `h` an up-level target, and `M-a` a reload command. The
  repo picker (`hop -R`) supplies only the up-level target and the workspace picker (`hop -w`) only the
  drill target, yet the NORMAL legend named `:` and the `?` overlay named all five in both. So a user
  pressed the key the header had just told them to press and got nothing, with no error and no beep, in
  the two pickers a newcomer meets first. The legend now omits `: view` where there is no kind menu,
  and the overlay is passed the list of keys that picker really bound, which is the rule
  `_hop_header`'s own comment already stated for `M-a`. `M-a` was the fifth case and had been missed.

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
- `hop upgrade <TAB>` no longer offers a single garbage candidate (every tag joined by spaces)
  when the user has `column.ui=always` set; release tags are now listed with `for-each-ref`.
- The `:` kind menu's count cache no longer stays blind to `git add`. It enumerates via the
  index (`git ls-files --cached`) but was keyed only on `(root, HEAD)`, so staging a file into a
  kind that had none, with HEAD unchanged, left that kind hidden from the menu until the next
  commit. The key now also tracks the index file's mtime and size.
- The test suite no longer inherits the settings of whoever runs it. An exported `HOP_FZF_MIN`,
  `HOP_VIM`, `HOP_HOPRC` or `HOP_REPOS` made it fail or hang, an inherited `HOP_FZF_HEIGHT` started
  fzf against no terminal and orphaned it, and `FZF_DEFAULT_OPTS` silently disabled the control arm
  of the `--exact` guard. Every setting is pinned from one list now, rather than from three helpers
  that each kept their own and drifted, and a test derives that list from the source so it cannot.
- The suite's per-child timeout is a real bound again. Six call sites used a shape where the timer
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
