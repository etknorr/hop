# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project adheres to [Semantic Versioning][semver].

## [Unreleased]

### Added

- A structural guard pinning why `tests/lib/pty.zsh` is safe, which until now it was only by accident.
  `zpty -b` at a script's top level makes the spawned shell inherit the caller's EXIT trap, and that trap removes the pty fixtures every pty test shares, so hoisting a spawn out of `pty_open` or `pty_canary` would delete them mid-run.
  Nothing enforced or even recorded that, and `pgrep -x zpty` could never have caught it either, since `zpty` is a builtin whose child carries the spawned command's name instead.
  The guard asks zsh's own parser which function bodies hold a spawn, rather than checking what column the line starts in, so a spawn indented inside a top-level `if` fails it too.
- A test for the tally a bound-killed suite reports, which until now was proven by hand only.
  That code path runs only when a suite is killed outright, and no ordinary suite is ever killed, so nothing in the suite could reach it.
  A nested `tests/run` is driven under a three-second bound against a suite that closes three tests and then hangs, and the tally it reports back is asserted to be exactly three and to equal the markers actually printed.
  Exact on both sides rather than a floor, because `>= 1` still passes with two of the three passes silently dropped, which is this defect itself in miniature.
  A second assertion pins the signal, since only the untrappable `KILL` reaches the marker counting at all: under a signal the suite can trap it closes its open test and reports four from a sentinel instead, which is a different mechanism that must not be mistaken for this one.

### Fixed

- A test suite killed by its bound reported every result it had already produced as zero.
  The tally reached the runner only in a final sentinel line, and the bound ends a suite with `KILL`, which no trap can catch, so a suite killed with 16 passing tests on screen reported `0 passed, 1 failed`.
  Preserving a partial tally was designed and wired, and worked for every signal except the one the runner itself sends.
  The parent counts the result markers it is already holding when no sentinel arrives, so a killed suite keeps its passes.
- The per-suite bound was too low for a busy machine, and a crash never said what had killed it.
  `suite_pty` takes about 13.6s at loadavg 14 and 182.28s at loadavg 185, so the 120s bound was killing a suite that was merely slow, and the default is 600s now.
  A crash reports its own elapsed time and the load average, and separates the runner's bound from a signal sent from outside it, which is the distinction that had exit 143 at 110.83s read as this bound firing for most of a day when the bound exits 142.
- Fixture directories orphaned by a killed suite are reaped at startup.
  A suite that cannot run its cleanup leaves its entire fixture set behind, and 2053 entries had accumulated under the temp directory before anyone counted them.
  The sweep is age-gated so a concurrent run's fixtures survive, and it matches files as well as directories, because the runner's own scratch file leaks the same way.
- The recording stubs the test suite uses now write each logged call in a single append, so two of them running at once can no longer splice their lines together.
  Each stub wrote the command name, then every argument, then the newline, as separate appends, and a second stub landing between them corrupted the line.
  The preview pane runs one of those stubs on every render, so this was reachable rather than theoretical: it recorded `batgh browse` in place of `gh browse`, which read as a verb that never ran and sent an entire investigation after the wrong component.
  The race is far too rare to hold a test to, measured at one corrupted trial in six under sixty-way concurrency, so what is asserted instead is the property that makes interleaving impossible: exactly one append per call.
- The picker no longer leaves a `hop-guard.XXXXXX` directory in your temp dir every time it is killed outright.
  Each picker makes one private directory for the escape guard's timestamp and removes it on `EXIT HUP TERM`, but `SIGKILL` cannot be trapped, so `kill -9`, an OOM kill, or a terminal tearing down the process group left the directory behind for good and one accumulated per killed picker.
  A trap cannot fix what a trap cannot catch, so the picker now sweeps guard directories older than a day before creating its own.
  The sweep is a glob qualifier rather than a `find`, costing no process: measured at 1.1ms against a temp dir holding 3008 entries, where the guard's own fork costs 12.7ms on an idle machine.
  A day rather than an hour, because writing the mark rewrites an existing file and so never moves the directory's own mtime, which means an hourly sweep would reap the guard out from under a picker you had left open over lunch.
- `hop --doctor` could hang forever and print nothing, which is the worst place for this bug: the issue template tells you to run exactly that command.
  It asked six external tools for their versions with stdin inherited, and the `fzf` on your `PATH` is not always the real binary.
  `fzf-tmux` ships alongside fzf and reads the caller's stdin with `cat <&0` whenever stdin is not a terminal, so `hop --doctor` from a script or a pipeline was enough to hang it with no output and nothing to report.
  The picker's own fzf version check had the same shape.
  Both read from `/dev/null` now, and each is covered by a test that hangs if its redirect is removed.
- Eight more test assertions that a floor kept from failing.
  `assert_ge N` reads like a bound but asserts a size, so it passes on every larger value too: the modal keymap check sat at 90 against 97 real keys and stayed green with seven of them deleted, and the `--help` registry check sat at 2 against 8 kinds and stayed green with `helm` gone from the kind list entirely.
  Each is an exact set or an exact count now.
  A floor of 1 used honestly, to prove evidence exists before asserting over it, is kept and spelled that way.
- One integration test was reading the wrong evidence rather than too little of it.
  The fzf stub records the picker's rows to a file it only truncates on the runs it actually makes, so a probe that errored before reaching the picker left the previous invocation's rows in place, and with `hop -c` broken the check that every offered row is inside `$PWD` passed on rows from a different directory.
  The record is emptied before each run now.
  That check asserts it has rows before ranging over them too, because truncating the record fixes whose rows they are and cannot make an empty list fail.
- The integration suite no longer hangs when the runner's stdin never reaches EOF.
  `_hop_fzf_ver` is the one fzf call in the product that is never handed rows on a pipe, and the recording stub read stdin unconditionally, so it blocked on anything that never closes: under a fifo held open the suite took 81 seconds and failed seven of its tests.
  The stub answers a `--version` query without reading stdin now, which is what real fzf does.
- The core suite no longer hangs either, for the same reason and with the same fix.
  Handed a live stdin, `tests/run core` discarded all 31 of its cases and took the full 120s bound, reporting `a test may await a terminal` when every probe was really waiting on an EOF that an open pipe never sends.
  Its own recording stub captured stdin even when answering `--version`, so each probe burned its bound until the suite bound killed the run.
  CI never saw it, because GitHub Actions hands the job `/dev/null`.
- The picker-geometry tests were reading the wrong evidence, in the very pair written to stop exactly that.
  Both opened by asserting the recorded fzf argv was non-empty, but the stub records every fzf call and `_hop_fzf_ver` runs `fzf --version` before the picker ever starts, so a non-empty argv proved only that the version probe had run.
  Stubbing the picker's own call out entirely left the arm that checks an empty `HOP_FZF_HEIGHT` sends no `--height` passing green against an argv holding nothing but `--version`.
  Each arm opens on `--ansi` now, a flag only the picker passes.
- The core suite's stub matches a `--version` query anywhere in argv rather than only as the first word.
  `_hop_fzf_ver` happens to put it first, so the narrower check was correct today and would have gone back to blocking on stdin the moment that call grew a leading flag.
- The escape-sequence pty cases no longer depend on how loaded the machine is.
  `bin/hop-guard` times a verb against the previous check's clock reading, so its discriminator is the cost of its own fork: 12.7ms mean idle, but 425ms mean at loadavg 35, well past the 0.15s threshold.
  A check that slow reads as a real keypress and fails open, and the forged payload duly reached the editor verb in three runs out of four under 24-way load.
  Those cases pin the window past any plausible fork latency now, which leaves every link they exist to prove intact.
  The comment claiming the threshold has the headroom a loaded runner needs is corrected to say the opposite.
  The shipped default is unchanged, because the failure direction is fail-open: heavy load reverts to the nuisance the guard was written for rather than swallowing a keypress you did make.
- A real keypress could also read as a verb that never ran, for a reason with nothing to do with the guard.
  The pty stubs appended their name, then their arguments, then their newline, as separate appends to one shared log, and the preview pane runs the `bat` stub on every render.
  A concurrent call lands between those appends and records `batgh browse ...` in place of `gh browse ...`, which corrupts the only field the check reads.
  It presented as the browse verb never running, with an empty stderr and the dispatch already logged, which pointed the investigation at the guard rather than at the log.
  That suite drops the `bat` stub now, leaving the log exactly one writer, and `bin/hop-preview` falls through to the `cat`/`head` path it already uses on a machine without `bat`.
  The controls also report hop's stderr and any line no single stub could have written, since a verb can bail after `dispatch key=` is logged.
  The multi-append write that made it possible is fixed for every suite at once, in its own entry.
- The guard's own unit suite had four assertions with the same defect.
  Asserting that a verb was refused means asserting a 150ms threshold was crossed, measured across the very fork whose latency is being timed: 1 in 40 of those checks failed open at loadavg 44, and three of the four sat on the default window.
  They pin an explicit window now.
  The malformed-window case could not simply be pinned, because the value under test is precisely the fallback to the default, so it asserts only what holds at every load and checks the fallback constant against the default constant in the source.
  Asserting that a verb *ran* needs no pin either way, because load only pushes the age further outside the window.

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
[Unreleased]: https://github.com/etknorr/hop/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/etknorr/hop/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/etknorr/hop/releases/tag/v0.1.0
