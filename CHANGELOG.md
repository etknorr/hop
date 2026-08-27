# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project adheres to [Semantic Versioning][semver].

## [Unreleased]

## [0.1.2] - 2026-08-27

### Added

- A test for the tally a bound-killed suite reports, which was proven by hand until now.
  That path only runs when a suite is killed outright, and no ordinary suite is, so nothing in the suite reached it.
  A nested `tests/run` runs under a three-second bound against a suite that closes three tests then hangs, and the tally it reports must be exactly three and must equal the markers actually printed.
  Exact on both sides rather than a floor, since `>= 1` still passes with two of the three passes dropped.
- A guard pinning why `tests/lib/pty.zsh` is safe, which until now it was only by accident.
  `zpty -b` at a script's top level makes the spawned shell inherit the caller's EXIT trap, and that trap removes the pty fixtures every pty test shares.
  The guard asks zsh's own parser which function bodies hold a spawn, so one indented inside a top-level `if` fails it too.

### Fixed

- The picker no longer leaves a `hop-guard.XXXXXX` directory in your temp dir when it's killed outright.
  Each picker makes one private directory for the escape guard's timestamp and removes it on `EXIT HUP TERM`, but `SIGKILL` can't be trapped, so `kill -9`, an OOM kill or a terminal tearing down the process group left one behind for good.
  A trap can't fix what a trap can't catch, so the picker sweeps guard directories older than a day before making its own.
  A day rather than an hour, because writing the mark rewrites an existing file and never moves the directory's own mtime, so an hourly sweep would reap the guard out from under a picker you'd left open over lunch.
- `hop --doctor` could hang forever and print nothing, which is the worst place for it, since the issue template tells you to run exactly that command.
  It asked six tools for their versions with stdin inherited, and the `fzf` on your `PATH` isn't always the real binary.
  `fzf-tmux` ships alongside fzf and reads the caller's stdin whenever stdin isn't a terminal, so `hop --doctor` from a script or a pipeline hung with nothing on stdout or stderr.
  The picker's own version check had the same shape, and both read from `/dev/null` now.
- A test suite killed by its bound reported every result it had already produced as zero.
  The tally reached the runner only in a final sentinel line, and the bound ends a suite with `KILL`, which no trap can catch, so a suite killed with 16 passing tests on screen reported `0 passed, 1 failed`.
  The parent counts the result markers it's already holding when no sentinel arrives.
  The bound was also too low for a busy machine: `suite_pty` takes about 13.6s at loadavg 14 and 182.28s at loadavg 185, so the default is 600s now, and a crash reports its own elapsed time and the load average.
- The test suite's recording stubs write each logged call in one append, so two running at once can't splice their lines together.
  Each stub wrote the command name, then every argument, then the newline separately, and a second stub landing in between corrupted the line.
  The preview pane runs one of those stubs on every render, so this was reachable rather than theoretical: it recorded `batgh browse` for `gh browse`, which read as a verb that never ran and sent a whole investigation after the wrong component.
- Fixture directories orphaned by a killed suite are reaped at startup, after 2053 of them had built up under the temp directory.
  The sweep is age-gated so a concurrent run's fixtures survive, and it matches files as well as directories, because the runner's own scratch file leaks the same way.
- CI pins the per-suite bound inside the job's own budget, so one hung suite can't spend the whole job before the bound fires.
  The lint leg also no longer dies when an unrelated third-party apt repo answers 403, which failed `apt-get update` outright and never reached `zsh -n`.
- Twelve more test assertions that couldn't fail, two suites that hung, and three checks that read the wrong evidence.
  Floors were the common cause: `assert_ge 90` against 97 real keys stayed green with seven of them deleted, and `assert_ge 2` against 8 kinds stayed green with `helm` gone from the registry entirely.
  Each is an exact set or an exact count now, and a floor of 1 used to prove evidence exists before asserting over it is kept and spelled that way.
  Both hangs were a stub that read stdin even when answering `--version`, so any stdin that never reached EOF blocked the whole suite.
  The escape-sequence pty cases no longer depend on machine load either, since the guard's discriminator is the cost of its own fork: 12.7ms idle against 425ms at loadavg 35.

One thing this deliberately doesn't cover: nothing asserts that a `SIGKILL`ed suite leaves no fixture directories behind, because `KILL` is untrappable and the zero-leak guard skips exactly that case. The startup reaper clears them later instead.

## [0.1.1] - 2026-08-26

### Added

- An escape guard, so bytes a terminal prints can no longer run a hop verb.
  fzf delivers escape sequences it can't parse as ordinary keystrokes, and in NORMAL mode letters are verbs, so a terminal answering a background-colour query typed `11;rgb:1e1e/1e1e/1e1e` into the picker and the `b` in `rgb` ran `gh browse`.
  Every action that leaves the picker now checks how recently its key arrived, through `bin/hop-guard`, and it fails open rather than swallow a real keypress.
  `HOP_GUARD_WINDOW` sets the threshold, default 150ms, and `HOP_GUARD_WINDOW=0` disables the guard.
  Navigation stays outside the guard deliberately, since `j`, `k`, `g` and `G` must not fork a process on every cursor move, so a hostile sequence can still scroll the list or switch mode.
  It can no longer open an editor, write the clipboard or open a browser tab, and the README documents the gaps that remain.

### Changed

- The browse verb moved off `ctrl-g` and onto `alt-B` in SEARCH, because `ctrl-g` was reachable with no keypress at all.
  A single BEL byte (`0x07`) in anything a program prints arrives at fzf as `ctrl-g`, and hop passed `ctrl-g` on `--expect`, so a stray bell ran `gh browse` and opened a browser tab.
  `--expect` is passed unconditionally, so neither `HOP_VIM=0` nor `--no-vim` protected against it the way they protect the NORMAL-mode letters.
  `ctrl-g` is bound to `ignore` now rather than merely dropped, because fzf's own default for it is `abort`, so the same bell would have closed the picker instead.
  `b` in NORMAL is unchanged, and `^G` still launches hop from the shell, which is the confusion this retires.

### Fixed

- The picker no longer advertises keys it left bound to `ignore`.
  Five NORMAL-mode keys are gated on whether the calling picker had anything for them to do: `r` needs a restore command, `:` a root to enumerate kinds from, `l` a drill target, `h` an up-level target, and `M-a` a reload command.
  The repo picker (`hop -R`) supplies only the up-level target and the workspace picker (`hop -w`) only the drill target, yet the NORMAL legend named `:` and the `?` overlay named all five in both.
  So a user pressed the key the header had just told them to press and got nothing, with no error and no beep, in the two pickers a newcomer meets first.
  The legend omits `: view` where there is no kind menu now, and the overlay is passed the list of keys that picker really bound.
- `hop` no longer hangs forever when no controlling terminal is available.
  A mistyped query was the likeliest way to hit this: `hop -k tg zzzz` from a script, a cron job, a CI step or an agent's shell blocked indefinitely instead of reporting that nothing matched, and a query matching many targets hung the same way.
  The picker deliberately omits `--exit-0` so a typo can be corrected in place, which is right when a terminal exists and a trap when one doesn't.
  fzf doesn't error when `/dev/tty` can't be opened, it starts, writes nothing at all, and blocks on keys it can never receive, so hop wedged with zero bytes on both stdout and stderr.
  hop resolves the query headlessly with `fzf --filter` now and returns non-zero.
  Nothing matched and several matched get different messages, because a typo wants correcting where a broad query wants narrowing, and the latter names how many candidates there were.
  A query matching exactly one target still jumps straight to it, exactly as `--select-1` did before, so `hop <unique-query>` keeps working from a script.
  Redirected shapes such as `hop < /dev/null`, `hop | cat`, `echo x | hop` and `hop 0<&-` are unaffected, because fzf reads keys from `/dev/tty` rather than stdin.
- The copy verb (`ctrl-y`/`alt-y`) no longer reports `hop: copied <path>` when the clipboard command itself fails; it names the failing tool on stderr and returns non-zero.
- The edit verb (`alt-o`) no longer rejects an absolute-path `$EDITOR`/`$VISUAL` (e.g. `/opt/homebrew/bin/nvim`) as "not installed", because a path is checked for existence and the executable bit instead of a `$PATH` lookup.
- Six test assertions that could not fail, four of them able to let a shipped behaviour regress with the suite green.
  The `--help` check for the opt-in `file` kind matched the usage line rather than the kinds registry, so starring every kind still passed.
  Five modal-keymap checks compared a transform's output against the same `HOP_VIM_*` variable the transform reads, and `lib/ui.zsh` declares those empty, so `?` never opening the keys overlay, `?` never closing it and `enter` never switching kinds in the `:` menu were each shippable without one failing test.
  The other two, for `HOP_VIM_TO_NORMAL` and `HOP_VIM_MENU_BACK`, could not have shipped a regression, since a sibling test caught the first and `esc`'s own `:-abort` default caught the second, but they name the cause now instead of leaving it to be inferred.
- `HOP_CONFIG` and `HOP_HOPRC` are exported now, and `HOP_CONFIG` is forwarded explicitly into the reload child alongside `HOP_HOME`.
  Both were plain shell parameters, so a `HOP_CONFIG=~/mine.zsh` line in `.zshrc` never reached the two children that re-source `hop.zsh` to rebuild the kind registry, the `zsh -f` reload shell and `bin/hop-kinds`.
  Your own kinds vanished in exactly the places that depend on those, so the `:` view menu listed the eight shipped presets instead of your kinds, and `alt-a` or `r` printed `hop: unknown kind: <yours>` and blanked the picker.
- `hop -c`/`--cwd`/`--here` resolves `$PWD` before matching it against the row paths now, so it finds targets in a repo reached through a symlink.
  `$PWD` is logical while the rows are built from git's physical `--show-toplevel`, so the two never matched and every row was dropped: `hop -c` reported `hop: no targets under <dir>` and exited 1 in a subtree that plainly had them, which hit every repo under macOS `/tmp`.
  The filter is pure zsh now rather than `awk -F'\t' -v p="$PWD"`, because `awk -v` escape-processes the value it is handed, so a directory whose name contained a backslash silently matched nothing.
- The workspace picker (`-w`/`--workspaces`) reads fzf's exit status now, which it previously skipped entirely.
  `hop -w somequery` matching nothing printed nothing and exited 0, and a too-old fzf, a rejected key bind or an unreachable `/dev/tty` were all indistinguishable from pressing `esc`.
  The ladder `_hop_run` already had is a shared `_hop_fzf_status` now, so the two pickers can't drift apart again, and `esc` stays silent in both.
- `HOP_DEBUG=1` logs every pick now, not only a successful key dispatch.
  The single `_hop_dbg` call sat inside `_hop_dispatch`, so fzf exiting 1 or 130, an empty target set, a version rejection or a tty problem wrote nothing at all, which left the diagnostic blind to precisely the failures people file bugs about.
  Each pick logs its label, row count, query and exit status now.
- `hop upgrade <TAB>` no longer offers a single garbage candidate (every tag joined by spaces) when the user has `column.ui=always` set; release tags are listed with `for-each-ref` now.
- The `:` kind menu's count cache no longer stays blind to `git add`.
  It enumerates via the index (`git ls-files --cached`) but was keyed only on `(root, HEAD)`, so staging a file into a kind that had none, with HEAD unchanged, left that kind hidden from the menu until the next commit.
  The key tracks the index file's mtime and size now too.
- The test suite no longer inherits the settings of whoever runs it.
  An exported `HOP_FZF_MIN`, `HOP_VIM`, `HOP_HOPRC` or `HOP_REPOS` made it fail or hang, an inherited `HOP_FZF_HEIGHT` started fzf against no terminal and orphaned it, and `FZF_DEFAULT_OPTS` silently disabled the control arm of the `--exact` guard.
  Every setting is pinned from one list now rather than from three helpers that each kept their own and drifted, and a test derives that list from the source so it can't.
- The suite's per-child timeout is a real bound again.
  Six call sites used a shape where the timer lived inside the process being timed, so a child that ignored the signal ran unbounded and its grandchildren outlived the run.
  The timer sits outside it now and kills the whole process group.
- The README's environment table omitted `HOP_HIST_MAX`, `HOP_DEBUG` and `HOP_DEBUG_LOG`, three settings hop reads and documents elsewhere, so the one table a user consults to learn what is tunable was the wrong place to look.
  `SMOKE.md` also undercounted its own automated keys.
- Two gaps in the suite's own coverage, both of the shape that lets a shipped behaviour regress with the suite green.
  Nothing asserted on the picker's geometry at all, so a typo'd `--heigth` in `lib/ui.zsh` would have handed every picker fzf's default height with no test failing, and the default `80%` and the `--min-height` that rides with it are both checked against the argv fzf really received now.
  The tripwire on the settings scan was a `>= 15` floor against 17 settings found, so the scan could have decayed to fifteen and still reported healthy, and it asserts an exact sorted set now.

## [0.1.0] - 2026-08-25

First release.

### Added

- `hop`, a modal, fzf-driven navigator for large configuration monorepos.
  It enumerates deployable units instead of walking directories, and `cd`s to the one you meant.
- The `hop_kind` DSL for declaring a family of navigable things, in four shapes: `--dirs` (child directories of a base), `--files` (tracked files matching a pathspec), `--marker` (any directory containing a given file), and `--fn` (a hand-written provider for irregular families).
- Shipped presets covering common config-repo layouts: `terragrunt`, `terraform-modules`, `helm`, `serverless`, `puppet`, `backstage`, `dir` and `file`.
- A modal fzf UI in the style of `k9s` and vim: NORMAL mode where keys are verbs, `/` for SEARCH, and `:` to switch kinds in place without a nested fzf process.
- `HOP_FZF_HEIGHT` sets the picker's height, defaulting to the previous hardcoded `80%`.
  An empty value drops `--height` entirely and gives fzf the whole screen.
- Workspaces: `-w`/`--workspaces` to pick a workspace root and drill into its repos, and `hopw` to `cd` to the workspace containing `$PWD`, deepest match winning.
- `hopr` to `cd` to the repo root, `hop -` for `cd -`, and the `^G`/`alt-g` widget to launch `hop` from a half-typed command line without losing it.
- `-c`/`--cwd`, `-k`/`--kinds`, `-a`/`--all` and `-R`/`--repos` to narrow or widen a search.
- `hop -V`/`--version`, which prints the contents of `VERSION` plus a `git describe` suffix when the install is a git checkout.
  `hop upgrade` reads that same file, so it is the release contract other tooling depends on.
- `hop --doctor` and `HOP_DEBUG=1` for bug reports: install path, config, tool versions, workspace membership, live kind counts, and the last 15 dispatched keys.
- `hop --doctor=short`, a paste-safe diagnostic mode for public bug reports.
  It omits `PWD`, the git toplevel, workspace names and paths, and kind names, replacing them with counts, and shows a config path only when it still matches hop's shipped default.
- `hop upgrade`, which moves a manual clone onto a release.
  Bare `hop upgrade` fast-forwards local `main` and stays on it, so `git pull` keeps working; `hop upgrade 0.1.0` pins to that tag, detached.
  `hop upgrade --check` reports installed versus released and changes nothing.
  It refuses rather than acts on a dirty tree, a side branch, a non-tag detached HEAD, a missing `origin`, a diverged `main`, or an untracked file the release also ships, and it never cleans, resets, merges or forces anything.
- `hop.plugin.zsh`, the filename plugin managers look for, so `hop` needs no per-manager configuration.
  It sources `hop.zsh` and nothing else.
- A real install section in the README covering zinit, antidote, sheldon, oh-my-zsh and a manual clone, each shown both unpinned and pinned to a release tag.
- Repo governance for the now-public project: the MIT license, README badges (CI, license, zsh), a `CONTRIBUTING.md`, GitHub issue and pull request templates, and a `.editorconfig` matching the project's real per-file indentation.

### Fixed

- `HOP_HOME` is derived unconditionally from `hop.zsh`'s own path now rather than inherited from the environment, so a stale exported value can no longer point a sourced shell at the wrong install.
- The copy verb (`y`/`Y`, `ctrl-y`/`alt-y`) no longer hard-requires `pbcopy`, it falls back to `wl-copy`, `xclip`, `xsel`, or `clip.exe`, so it works on Linux (Wayland or X11) and WSL, not just macOS.
  `HOP_CLIPBOARD` overrides the probe entirely for a custom clipboard command.
- `esc` out of a non-matching SEARCH query no longer lands you in NORMAL with a permanently empty list, where every navigation key did nothing and a verb acted on an empty selection.
  `disable-search` only stops future matching, so nothing re-filtered.
- An fzf older than 0.60.3 is refused with an explanation naming the version found, the version needed, and the upstream download, instead of failing as a bare `unknown option: --accept-nth`.
  `--accept-nth` arrived in fzf 0.60.0 and only worked alongside `--select-1` from 0.60.3, and the picker passes both, which is where the floor comes from.
  Debian and Ubuntu package 0.44.x.
  `HOP_FZF_MIN` overrides the floor, the version is read at most once per shell, and a version hop can't parse proceeds rather than blocking.

[keepachangelog]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
[Unreleased]: https://github.com/etknorr/hop/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/etknorr/hop/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/etknorr/hop/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/etknorr/hop/releases/tag/v0.1.0
