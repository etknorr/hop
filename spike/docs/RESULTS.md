# hopx spike results

One section per phase. Each phase starts by reading the sections before it.

## Phase 1: module, config, enumeration and row parity

Status: done. Nothing is left over for phase 2.

### What exists

- `spike/hopx`, module `github.com/etknorr/hop/spike/hopx`, Go 1.26, one dependency (`github.com/BurntSushi/toml` v1.6.0).
- Commands: `hopx rows [-k KINDS] [--root DIR] [-a]`, `hopx rows -w` (workspace rows), `hopx rows -R` (repo rows), the hidden `hopx __rows <root> <kind...>` that fzf reloads will call, `hopx kinds`, `hopx config import [CONFIG.zsh] [-o OUT]`, `hopx config check`, `hopx config path`, `-h` and `-V`.
- Packages: `config` (TOML schema, loader, validation with line numbers, `extend`, `presets`, `[settings]`, the 8 embedded presets), `importer` (zsh replays config.zsh, Go re-parses each `hop_kind`), `gitls` (one `git ls-files -z --cached` per run, pathspecs matched in memory), `kinds` (marker, dirs, files, exec, the helm and dir builtins, repo and ws rows), `rows` (render, `_hop_fit`, colours, widths), `workspace` (`_hop_ws_parse`, `_hop_ws_repos`, `_hop_repos`), `collate` (zsh's en_US.UTF-8 sort order) and `testfix` (the fixture repo builder).
- `spike/hopx/testdata/eric.toml`, imported from `~/.config/hop/config.zsh` with no hand edits.
- `spike/parity/rows.sh` and `spike/parity/bench_rows.zsh`.

### G1: row parity on ~/strava/configuration

`spike/parity/rows.sh` sources the worktree's `hop.zsh` under `zsh -f` with `HOP_CONFIG=~/.config/hop/config.zsh` and `HOP_HISTFILE=/dev/null`, and runs hopx with `HOPX_CONFIG=testdata/eric.toml`. `verdict` is a byte `cmp`; `set-diff` counts ANSI-stripped rows found on only one side.

| kind | zsh rows | hopx rows | verdict | set-diff |
|---|---|---|---|---|
| tg | 669 | 669 | IDENTICAL | 0 |
| mod | 28 | 28 | IDENTICAL | 0 |
| helm | 120 | 120 | IDENTICAL | 0 |
| serverless | 12 | 12 | IDENTICAL | 0 |
| puppet | 32 | 32 | IDENTICAL | 0 |
| backstage | 18 | 18 | IDENTICAL | 0 |
| dir | 24 | 24 | IDENTICAL | 0 |
| file | 12033 | 12033 | IDENTICAL | 0 |
| mesos | 200 | 200 | IDENTICAL | 0 |
| conf | 2082 | 2082 | IDENTICAL | 0 |
| rules | 152 | 152 | IDENTICAL | 0 |
| default (tg mod helm dir mesos) | 1041 | 1041 | IDENTICAL | 0 |
| ws (`_hop_provider_ws`) | 4 | 4 | IDENTICAL | 0 |
| repo (`_hop_repo_targets`) | 30 | 30 | IDENTICAL | 0 |

G1 passes: all 11 kinds, the default set, and the ws and repo rows are byte-identical. Diff count is 0 of 16,445 rows.

The first run had one DIFF, on repo: same set, but `identifiers` and `iPhone` swapped. zsh's `(o)` sort and glob expansion use the locale's collation (case folded, accents second, lowercase before uppercase), and Go's `sort.Strings` is bytewise. `internal/collate` now approximates the macOS en_US.UTF-8 order, checked against live zsh on a word list.

### Fixture parity

The Go tests build a fixture git repo (`internal/testfix`) with every shape the spec lists, plus a gitlink, tracked symlinks, a zero-byte `main.tf`, a directory named `main.tf`, `brack[1]`, a trailing `\ `, `café`, long names and scopes, and a user `--fn` provider. `testdata/fixture.zsh` declares 15 kinds over it, covering every `hop_kind` option. Each kind's rows are checked against goldens captured from zsh hop's `_hop_generate`, and `TestLiveZsh` reruns zsh hop on a fresh fixture each time, so a stale golden can't hide a regression. All 15 kinds match byte for byte, including the exec kind that runs the zsh provider through `compat.zsh`.

`gitls` is checked against real `git ls-files` for 36 pathspecs. Two git rules mattered and aren't in git's docs:

- Any pattern first matches as a literal, so `:(glob)odd/brack[1]/f` finds the file named `brack[1]`.
- git strips the literal prefix before wildmatch runs, so a `**` right after the prefix counts as segment-leading: `:(glob)svc/a**` matches `svc/alpha/README.md`, but `:(glob)**f` doesn't match `x/af`.

### G2: config migration

`hopx config import` turns Eric's `config.zsh` into `testdata/eric.toml` (32 lines) with no hand edits. The import verifies itself by loading the TOML back and comparing it to the replayed registry. Tests also cover:

- `config.example.zsh`, including its `--fn` kind, which becomes an `exec` kind running through `compat.zsh`;
- a config using every `hop_kind` option and every `HOP_*` setting;
- each of hop's 8 `presets/*.zsh`, imported and compared with the embedded TOML preset (all 8 equal);
- the importer's error cases (unknown option, undefined `--fn`, missing value, no shape, bad depth, unknown preset).

`TestEricConfig` re-imports Eric's live config and compares it to `eric.toml`. It only runs with `HOPX_PARITY_REPO` set, since that file is his to change. It passes today.

### Speed

`spike/parity/bench_rows.zsh`, median of 15 runs, M-series Mac, warm page cache, `~/strava/configuration`:

| set | rows | hopx | hop cold (`zsh -f`, source hop.zsh, `_hop_generate`) | hop warm (`_hop_generate` in a sourced shell) |
|---|---|---|---|---|
| default | 1,041 | 24.6 ms | 277.1 ms | 261.7 ms |
| file | 12,033 | 36.6 ms | 1,309.6 ms | 1,369.9 ms |

hopx is about 11x faster on the default set and about 35x on `file`. An earlier 15-run pass gave 24.5 ms and 36.8 ms for hopx. One `git ls-files -z --cached` on this repo takes 10.4 ms (median of 15), so it's about 40% of hopx's default-set time. hop runs 7 of them for the default set, one per `_hop_ls` call (tg, mod, dir and mesos once each, helm three times). I haven't split hop's remaining time between those forks and its per-row zsh work.

### Tests

`go vet ./...` is clean and `go test ./...` passes: 39 top-level tests, 81 counting subtests, across 9 packages. Two are skipped unless `HOPX_PARITY_REPO` is set: `TestParityRows` (runs `rows.sh`) and `TestEricConfig`. With `HOPX_PARITY_REPO=~/strava/configuration` both pass.

Run them with `cd spike/hopx && go test ./...`. Regenerate the goldens from zsh hop with `go test ./internal/kinds ./internal/rows -update`.

### I2: lines

| area | zsh code lines | Go code lines |
|---|---|---|
| enumeration, rows, workspaces (`providers.zsh`, `dsl.zsh`, `workspaces.zsh`) | 763 | 1,345 (`kinds`, `rows`, `gitls`, `workspace`, `collate`) |
| config and import | none (hop sources zsh) | 1,166 (`config`, `importer`) plus 172 lines of zsh (`import.zsh`, `compat.zsh`) |
| CLI | part of `hop.zsh` | 241 |
| tests | not ported | 1,272 plus the 146-line fixture builder |

Code lines exclude blank and comment lines. The engine port runs about 1.8 Go lines per zsh line.

### Found in hop

- `_hop_dsl_preview` (`lib/dsl.zsh:188`) tests a literal candidate with `-s` only, so a directory passes. With `--preview 'main.tf,...'`, a unit holding a directory named `main.tf` previews that directory. `_hop_first_file` uses `-f && -s` for exactly this reason. hopx copies the `-s` behaviour for parity.
- `_hop_entity_name` (`lib/providers.zsh:235`) never reads a last line with no trailing newline, because `read` fails on it. A catalog file ending in `  name: foo` with no newline gets its basename instead.
- `_hop_provider_ws` (`lib/workspaces.zsh:154`) turns `$HOME` into `~` with `${path/#$HOME/~}`, a plain prefix test. With `HOME=/Users/eric`, a workspace at `/Users/ericx` shows as `~x`.
- Row order depends on the shell's locale. `_hop_ws_repos` sorts with `(o)` and preview globs sort by collation, so the same repo lists differently under `LANG=C`.

### Deviations

Recorded in `DEVIATIONS.md`.

### For phase 2

- The effort probes at `/private/tmp/claude-hopx-effort/` hold the 1,506-query corpus. `/tmp` gets purged too, so copy what phase 2 needs into `spike/` first.
- `kinds.Generate` returns `[]rows.Row` in kind order, unranked. `rows.Render(r, root)` gives the exact bytes. `__rows` doesn't rank or filter by cwd yet, which is phase 3's job.

## Phase 2: MRU, resolver and headless report

Status: done. Nothing is left over for phase 3. The stop rule doesn't apply: G3 and G4 pass with zero differences.

### What exists

- `internal/match`: `_HOP_MATCHER_FLAGS` (checked against the live `lib/ui.zsh` array by a test), a `Matcher` interface, the external `fzf --filter` implementation with `FZF_DEFAULT_OPTS` and `FZF_DEFAULT_OPTS_FILE` set empty, and hop's version floor 0.60.3.
- `internal/mru`: `Rank` (`_hop_rank`) and `Remember` (`_hop_remember`), on hop's file format, written by temp file and rename.
- `internal/resolve`: `lib/match.zsh` ported function by function, each Go function naming its zsh original.
  - T0 (`Literal`), T1, T2a and T2 (`rewrite`, `abbrevs`, `compound`, `prune`, the env-word map), T3 (`loose`), relaxed, all-but-one, T4 and the 6000-row cap.
  - `decide` with ancestor injection, README previews and `minimal`. `decideJump` has J1, J1b, J3 with the clipped-column guard, J0, and J2 with the kind-word guard and `aligned`.
  - `coherence`, the `_hop_text` fast path for relaxed words, `Report` (`_hop_headless_report`), `Rank` (`_hop_res_rank`) and `Input` (`_hop_res_input`, for phase 3).
- `internal/act`: the cmdfile protocol: `O_EXCL`, mode 0600, no newline, or stdout when `HOPX_CMDFILE` is unset.
- `hopx [flags] [query...]`, headless: hop()'s option loop and exit-2 rules, T0 before enumeration, the workspace level with its repo fallback, `-R`, `-c`, `-k`, `-a`, `-p`, `/`, then enumerate, rank, resolve, and jump or report.
- `hopx __resolve-dump [--full] [--stats] [--jump J] [--root DIR] [-k KINDS]`.
- `spike/parity/resolve_dump.zsh`, `resolve.sh` and `bench_resolve.zsh`. The 1,506-query corpus is copied into `spike/parity/corpus/queries.txt`.

### G3 and G4: resolver parity on ~/strava/configuration

`resolve.sh` builds the query sets the way `tests/eval_real.zsh` does. It runs each query through T0 and then `_hop_resolve` in zsh hop (Eric's `config.zsh`, `HOP_HISTFILE=/dev/null`), and through `hopx __resolve-dump --full` (`eric.toml`, an empty history). "core" counts differences in verdict, tier, rule or target rel. "full" counts differences anywhere in the line: n, m, inj, every candidate rel in order, the picker query, the note, and the full headless report text.

| jump | set | queries | core diffs | full diffs | hopx jumps |
|---|---|---|---|---|---|
| auto | names | 583 | 0 | 0 | 282 |
| auto | pref3 | 324 | 0 | 0 | 52 |
| auto | scope+env | 27 | 0 | 0 | 20 |
| auto | name+env | 566 | 0 | 0 | 468 |
| auto | nonsense | 500 | 0 | 0 | 0 |
| auto | corpus | 1,506 | 0 | 0 | 785 |
| auto | typo | 513 | 0 | 0 | 4 |
| auto | relaxed | 583 | 0 | 0 | 0 |
| unique | all 8 sets | 4,602 | 0 | 0 | 1,589 |
| never | all 8 sets | 4,602 | 0 | 0 | 0 |

- **G3 passes**: 0 differences on names, scope+env and name+env under auto, in every column, not only the four the bar names.
- **G4 passes**: 0 nonsense jumps.
- **I1**: pref3 and the unique and never sweeps have 0 differences too, so 13,806 resolves in total match.
- The three extra sets reach the approximate tiers, which the spec's sets barely touch. Under auto, typo resolves 469 queries at T2 and relaxed resolves 583 at relaxed. The spec's five sets are T1 except the nonsense set's 28 T2 and 5 T3 picks.

### Fixture tests

The Go tests port `match_fixture` (`testfix.BuildMatch`) and its config (`testdata/match.zsh`, imported to `match.toml`).

- **The case table**: all 126 `suite_match.zsh` cases, the 50 nonsense words included, each compared as a whole line.
  - `TestGoldenTable` compares against `testdata/golden/resolve.tsv`, captured from `testdata/resolve_runner.zsh`, a copy of suite_match's runner that also prints every candidate and the report.
  - `TestLiveZsh` reruns the table through zsh hop every time.
- **`TestSuiteMatch`**: suite_match's 68 `mt_jump` and `mt_pick` assertions, with the expected values copied from the suite. Every pick also gets the suite's parity check: the candidates are exactly `fzf --filter`'s rows for the picker query.
- **`TestSuiteMatchDetails`** has suite_match's other claims: on-disk spelling, pwd before root, `-c` containment and its control, README previews, the 50-word nonsense property, and injected rows keeping their colour. `TestKindWordGuard` has a control showing J2 jumps without the kind list. `TestMRU`, `TestEmptyQuery` and `TestApproxMax` cover the rest.
- **Differential tests against zsh itself**:
  - `TestApproxAgainstZsh` checks 4,000 pairs, 2,361 of them in reach, against zsh's own `(#aN)`. It confirms zsh's approximate match is restricted Damerau-Levenshtein (optimal string alignment) distance at most N.
  - `TestRewriteAgainstZsh` runs `_hop_rewrite` narrow, `_hop_rewrite` wide and `_hop_loose` on 2,292 queries (the corpus plus generated typos) over the fixture vocabulary, with 0 differences.
  - `TestRankAgainstZsh` checks `_hop_rank`, and `TestFlagsMatchHop` checks the matcher flags.
- **`TestHeadlessAgainstHop`**: the built binary and zsh's `hop()`, each in its own session with no controlling terminal. It covers 37 command lines: the probe queries, each tier, `-p`, `HOP_JUMP`, `-c`, `-k`, `-a`, `/`, `~/x`, an absolute path, `-w`, `-R`, and the outside-a-repo workspace fallback with J0. Both start from the same seeded history. All 37 match on stderr byte for byte, on exit status, on the final directory, and on the history file left behind.
- **Injected faults**: always skipping coherence broke 4 cases in both the golden and the live table, and moving the two-error threshold from 8 to 9 characters broke 3 tests.

`go vet ./...` is clean and `go test ./...` passes. There are 65 top-level tests and 234 counting subtests, across 13 packages. Three are skipped unless `HOPX_PARITY_REPO` is set (`TestParityRows`, `TestParityResolve`, `TestEricConfig`). Regenerate the resolver golden with `go test ./internal/resolve -run TestGoldenTable -update`.

### Speed

Headless, from `~/strava/configuration`, median of 15 runs. Both sides end at the report, which is where the picker's first draw would start. The load average was about 14 during the run, from other agents on the machine, so read the ratios rather than the absolute times. `bench_resolve.zsh`:

| query | hopx | hop cold | hop warm | outcome |
|---|---|---|---|---|
| `-p vpc` | 106.1 ms | 548.2 ms | 547.9 ms | 36 targets |
| `-p vpc prod` | 76.8 ms | 521.6 ms | 538.9 ms | 8 targets |
| `-p eks staging` | 77.2 ms | 657.2 ms | 503.3 ms | 7 targets |
| `-p acct sec tooling prod` | 79.7 ms | 525.3 ms | 506.3 ms | 4 targets |
| `vpc` | 111.0 ms | 549.8 ms | 521.1 ms | 36 targets |
| `eks security` | 72.6 ms | 512.9 ms | 505.3 ms | jump |
| `securty-tooling-prod` | 87.6 ms | 570.2 ms | 536.4 ms | T2, 4 targets |
| `kps zzqx` | 89.2 ms | 612.7 ms | 567.6 ms | relaxed, 2 targets |

G7's first half passes: `hopx -p` beats `hop -p` on all four probe queries, by 5 to 8.5 times. Per jump, `eks security` takes 72.6 ms against 505.3 ms warm. The shell-function overhead comes in phase 4.

Per-query resolve time, enumeration excluded, from `__resolve-dump --stats` under the same load:

| set | ms per query | fzf forks per query |
|---|---|---|
| names | 26.1 | 2.49 |
| corpus | 29.7 | 2.45 |
| typo | 40.0 | 2.85 |
| relaxed | 60.1 | 3.07 |
| nonsense | 20.8 | 1.13 |

Forking fzf is now the cost. Each fork is about 10 ms on 1,041 rows, a typical query forks 2 or 3 times, and enumeration adds about 25 ms. The resolver's own Go work is small next to that. An in-process matcher (phase 5's `fzfembed`) would remove most of the remaining time. The whole parity sweep took about 205 to 290 s per jump mode in zsh, against about 85 to 125 s in hopx.

### I2: lines

| area | zsh code lines | Go code lines |
|---|---|---|
| resolver (`lib/match.zsh`) | 764 | 1,118 (`resolve`) |
| matcher and MRU (`_hop_filter`, `_hop_rank`, `_hop_filter_under`, `_hop_remember`) | about 70 | 235 (`match`, `mru`), 29 (`act`) |
| hop() and the ws and repo levels, up to the picker | 395 (`hop.zsh` 259-737, picker parts included) | 414 (`hop.go`, including `__resolve-dump`) |
| tests | not ported | 1,279 Go, plus 96 zsh and 105 sh of harness |

The resolver port runs about 1.5 Go lines per zsh line, against 1.8 for the engine.

### I3: pace

Phase 1's commits landed at 10:26 and phase 2's last code commit at 11:20, so phase 2 took about one agent-hour, the full parity sweep included. That's against the effort research's 8 conventional days for the resolver port. Two things made it fast. hop's own comments and suite_match name every rule and its reason. And the parity harness was cheap to build, because zsh hop could be driven directly.

### Found in hop

- `_hop_remember` rewrites the history in place with `print > file`, so a reader racing a jump can see a truncated history. One pass of `_hop_rank` then ranks with fewer entries. It's harmless but real. hopx writes to a temp file and renames it.
- Nothing else in phase 2. The port surfaced no resolver bug: every rule did what its comment says.

### For phase 3

- `resolve.Result.Input(all)` is the picker's stdin for a pick, and `Result.Query` and `Result.Note` are its `--query` and first header line.
- `session.pick` in `hop.go` is where the picker goes. It currently reports instead of picking when a terminal exists.
- `act.CD` is the cd half of `_hop_act_cd`. Open, reveal, copy and the editor actions are still to build.

## Phase B3: picker, actions and shell init (spec phases 3 and 4)

Status: done. Nothing is left over for phase 5. The writing-style advisor pass on this file is still left for phase 5, as before.

### What exists

- `internal/pick`: the fzf argv (`_hop_pick` without the modal layer), the session JSON, `Key` (the one decision a bind can't make), `Shim` (`__sh`), `Preview` (`bin/hop-preview` without `--keys`), `Parse` (`_hop_parse_result`) and `Run`.
  - Every callback is a `hopx __verb` command run through `--with-shell '<hopx> __sh'`, and no bind string holds a path or a query.
  - The matcher flags come from `match.Flags`, so the picker and the headless resolver can't drift.
  - A resolver pick opens ordered (`--no-sort` plus `change:toggle-sort+unbind(change)`) with its note above the legend, and only an empty query gets `--select-1`.
  - `--freeze-left=1` is passed from fzf 0.67.0, and `HOP_FZF_HEIGHT` set but empty is fullscreen.
- Keys: Enter, alt-enter (always cd), ctrl-o, ctrl-t, ctrl-y, alt-y, alt-o, alt-B (`print(ctrl-g)+accept`), ctrl-/ and alt-p (preview), ctrl-r, alt-a (reload with every kind) and alt-k (the kind menu, see `DEVIATIONS.md`).
- Callbacks: `__preview {2} {3}`, `__rows [kind...]` (session root and `-c` dir, ranked), `__menu` (live counts), `__key enter|esc|alt-enter`, `__header` and `__sh`.
- `internal/act`: `Actor.Dispatch` is `_hop_dispatch`, and `Actor.Enter` is `_hop_act_enter` for every mode.
  - cd goes through the cmdfile. `code -r` only ever gets a file, and a dir always gets `code -n`.
  - Reveal stands in a README or first file for a dir. A failed `code` after a cd keeps the cd and returns code's status.
  - With no `code`, open falls back to `$VISUAL`/`$EDITOR`, which is exec'd with fds 0 to 2 on the terminal. Copy probes `HOP_CLIPBOARD`, pbcopy, wl-copy, xclip, xsel and clip.exe, and browse runs `gh browse` from the repo root.
- `internal/tty`: `/dev/tty` for fzf's screen when stderr isn't a terminal, and `Attach` (`Dup2`, `Dup3` on linux) before the editor exec.
- `internal/shell` and `hopx init zsh|bash|fish|pwsh [--cmd NAME]`: the prototype's scripts, with the traps the spec lists, plus `hopx __complete` (flags, `--action=` modes, `init` shells, and kinds with their descriptions from the loaded config).
- Flags: `-a -k -c -w -R -p -o -e --cd --action= -h -V`, with hop's exit-2 rules. `-o`, `-e` and `--action=` now act on a jump instead of exiting 2.
- `internal/ptytest`: a pty driver with no dependency past `syscall` (`TIOCPTYGRANT`/`TIOCPTYUNLK`/`TIOCPTYGNAME` on darwin, `TIOCSPTLCK`/`TIOCGPTN` on linux).
- `spike/shell/test/` (`run-all.sh`, `fixture.sh`, `cd.{sh,fish,ps1}`, `pick.{sh,fish,ps1}`, `widget.exp`, `complete.exp`, `rc/`) and `spike/docker/Dockerfile.{fish,pwsh}`.
- `spike/parity/bench_pick.zsh` and `bench_shells.zsh`.
- One new dependency: `golang.org/x/term` (and `golang.org/x/sys` under it), for `isatty`, since `/dev/null` passes a character-device check.

### G5: shell coverage

`spike/shell/test/run-all.sh` builds hopx for darwin and linux/arm64, then gives each shell a fresh fixture repo (`plain`, `with space`, `trail-space-backslash\ `, `café`, a name holding a newline, `brack[1]`, `alpha`, `beta/gamma`) and a clean environment. It took 69 s, and a second run gave the same result.

| shell | where | pass | fail | xfail |
|---|---|---|---|---|
| zsh 5.9 | host | 31 | 0 | 0 |
| bash 5.3 | host | 31 | 0 | 0 |
| bash 3.2 (`/bin/bash`) | host | 31 | 0 | 0 |
| fish 3.7.0 | docker, ubuntu:24.04 | 33 | 0 | 0 |
| pwsh 7.5.3 | docker, ubuntu:24.04 | 32 | 0 | 1 |

Every shell runs the same cases:

- `cd.*`, with no terminal: T0 to each of the six names, three resolver jumps (`gamma`, `with space`, `brack`), `hopx /`, `hopx -`, no match (rc 1, no move), a bad flag (rc 2), `--action=cd+open` with a `code` that exits 3 (rc 3 and the cd kept), the bare binary printing its dir, `hopx -h | grep`, no cmdfile left in `$TMPDIR`, the history, and `HOPX_CMDFILE` not leaking into the shell.
- `pick.*`, on a terminal from `script(1)`, with `FZF_DEFAULT_OPTS` binds firing on `load` in place of keystrokes: cancel (rc 130, no move), Enter on three targets, and ctrl-y to a stub pbcopy.
- `init-parses`: `zsh -n`, `bash -n`, `/bin/bash -n`, `fish -n` and pwsh `[scriptblock]::Create`.
- `widget.exp`, interactive under expect: ^G on a half-typed line opens the real picker, a pick cds, the prompt hook re-runs (`[gamma]> `), the half-typed line comes back and runs, and `hopx -` returns.
- `complete.exp`: TAB completes `--wor` to `--workspaces` and `-k ` to the fixture's one kind.
- fish and pwsh also run G6, below.

The pwsh XFAIL is the expected backslash case: pwsh on Unix reads `\` as a separator, so `Set-Location -LiteralPath '/fx/repo/trail-space-backslash\ '` fails. hopx wrote the right path. The function reports the error and returns 1 without leaving the dir it was in.

G5 passes.

### G6: callbacks don't depend on the shell

`TestPicker` drives the real fzf on a pty through seven cases: Enter, ctrl-y, esc, the preview pane, alt-k to the helm kind and a pick there, alt-a and a pick among every kind, and an ordered relaxed pick with its note. Each case runs once per `$SHELL`:

| where | `$SHELL` | result |
|---|---|---|
| host | `/bin/sh`, zsh | pass |
| docker, fish image | fish, `/bin/sh` | pass |
| docker, pwsh image | pwsh, `/bin/sh` | pass |

The host runs were repeated 8 times in a row and the docker runs 3 times, all passing. G6 passes.

Two harness bugs turned up on the way, both in the test and not in hopx:

- A wait matched output drawn before the last keystroke.
- tcell repaints only the cells that changed, so a count like `1/27` may never be drawn whole. The pty test now waits on the selected row's preview instead.

### G7, second half: per jump

`bench_shells.zsh`, `eks security` (a T1 jump) through each shell's function, cd included, measured as (15 jumps minus 0 jumps) / 15 in one shell, median of 5 such pairs. Init is the shell with the init minus the bare shell, median of 31. Load average was about 5 to 9.

| shell | ms per jump | init ms |
|---|---|---|
| hop, zsh, sourced (what ^G runs) | 393.6 | 4.9 (`source hop.zsh`) |
| hopx, zsh | 65.9 | 3.8 |
| hopx, bash 5.3 | 71.2 | 5.2 |
| hopx, bash 3.2 | 75.5 | 1.0 |
| bare hopx binary, no function | 66.8 | none |
| hopx, fish 3.7 (docker) | 33.1 | 3.2 |
| hopx, pwsh 7.5 (docker) | 37.0 | 155.4 |
| bare hopx binary (docker) | 30.2 | none |

- G7 passes: a jump through hopx's function is 5 to 6 times faster than hop's ^G in every host shell.
- The function itself costs up to 9 ms over the bare binary.
- Init is noise-level in the POSIX shells. Two earlier 15-run passes gave 0.9 to 10.0 ms for hopx and 4.6 to 18.6 ms for hop.
- The docker rows run on linux with the repo on a bind mount, so compare them only with the docker bare-binary row.
- pwsh's 155 ms init is the shell's own cost: `Invoke-Expression` over a captured `hopx init pwsh`, and `Get-Command Set-PSReadLineKeyHandler` autoloading PSReadLine under `-NoProfile`.

### Callback latency against hop's scripts

`bench_pick.zsh`, `~/strava/configuration` with Eric's config, median of 15:

| callback | hopx ms | hop ms | hop script |
|---|---|---|---|
| preview, a file | 4.7 | 21.3 | `bin/hop-preview` |
| preview, a dir | 4.6 | 17.9 | `bin/hop-preview` |
| reload, default kinds, 1,042 rows | 21.1 | 346.2 | `bin/hop-kinds rows` |
| kind menu | 42.9 | 32.1 | `bin/hop-kinds menu`, counts cached |

The menu is the one row where hopx is slower, because it counts all 11 kinds live (12,033 rows for `file` alone) where hop reads a cache. hop's cold menu shows no counts at all, and warming them costs about 1.6 s in the background.

### Manual check on Eric's real data

`TestRealRepoPicker` (runs only with `HOPX_PARITY_REPO`) drives the picker on a pty in `~/strava/configuration` with `eric.toml`. History, clipboard, `code` and the editor are stubs in a temp dir. The last column is the time from exec to the drawn prompt.

| dir | command | keys | outcome | first draw |
|---|---|---|---|---|
| . | `hopx` | type `eks staging`, Enter | cd `terraform/acct-infrastructure/env-staging/us-east-1/services_eks` | 252 ms |
| . | `hopx eks staging` | Enter | the same cd | 127 ms |
| . | `hopx -p vpc prod` | Down, Enter | cd `terraform/acct-log-archives/env-prod/us-east-1/vpc`, the second candidate | 128 ms |
| . | `hopx thanos` | ctrl-y | pbcopy got `…/kubernetes/values/thanos`, no cd | 148 ms |
| . | `hopx` | alt-k, `rules`, Enter, `heatmaps prime`, Enter | cd `kubernetes/charts/service-rules/heatmaps/prime-prod` (rules isn't a default kind) | 109 ms |
| . | `hopx` | alt-a, `playbook`, Enter | cd `mesos/templates/playbook` (a `dir` row from the every-kind reload) | 129 ms |
| terraform/acct-security-tooling-prod | `hopx -c` | `vpc`, Enter | cd `terraform/acct-security-tooling-prod/env-prod/us-east-1/vpc` | 108 ms |
| . | `hopx --action=open eks staging` | Enter | `code -n …/services_eks`, a dir, so never `-r` | 104 ms |
| . | `hopx -k file -p atlantis.yaml` | ctrl-o | `code -r …/backstage/atlantis.yaml`, a file | 189 ms |
| . | `hopx -p routemaster` | alt-o | the editor exec'd on `…/routemaster/main.tf` | 108 ms |
| . | `hopx -w` | esc | rc 130, no cd | 87 ms |

Before the menu case used `rules`, it tried `thanos legacy` among helm rows. That returned rc 1 with `hop: no match`, which is correct: Eric's repo has no thanos-legacy.

### Tests

`go vet ./...` is clean and `go test ./...` passes, with 90 top-level tests (261 counting subtests) across 17 packages. Four are skipped unless `HOPX_PARITY_REPO` is set: `TestParityRows`, `TestParityResolve`, `TestEricConfig` and `TestRealRepoPicker`. All six spec targets cross-compile with `CGO_ENABLED=0`.

New in this phase:

- `pick`: argv goldens (`testdata/golden/argv.golden`: default, `-c`, `-k helm`, `--action=open`, `HOP_FZF_HEIGHT=`, `-w`).
  - Every argv goes through the real `fzf --filter` and exits 0, with a control that injects an unknown action and expects rc 2.
  - Also covered: no bind string holds the binary's path, the legends, `Parse` (blank `--expect` line, `print()+accept`'s extra line, empty preview), `SplitWords`, `Shim` in-process and fall-through, `Key` in and out of the menu, the session round trip, and `Preview` (file, dir with dotfiles and a subdir, empty dir, 400-line cap, missing target).
- `act`: every Enter mode against a stub `code`, a failing `code` after cd, the no-code fallbacks, and each key's argv, cd and history.
- `shell`: each init parsed by the host shells, `--cmd` renaming, the pwsh path quoting, and `Complete`.
- `main`: `__rows` equals `hopx rows` plus rank and honours `-c`, `__menu` counts, `__key`, `__header` and `__sh` through `run`, `init`, and `__complete`.
- `TestPicker` (above), and `ptytest`'s own test.

### I2: lines

| area | zsh code lines | Go code lines |
|---|---|---|
| picker, actions, preview, kind menu (`ui.zsh`, `actions.zsh`, `bin/hop-preview`, `bin/hop-kinds`) | 823, of which about 200 are the modal layer that isn't ported | 477 (`pick`) + 388 (`act`) + 50 (`tty`) |
| shell glue | zsh only: the widget and `completions/_hop` | 182 lines of init script for four shells, 95 (`shell`) |
| tests | not ported | 958 Go, plus 343 lines of shell and expect harness |

Without the modal layer the picker and actions run under 1.5 Go lines per zsh line, against 1.8 for the engine and 1.5 for the resolver.

### I3: pace

Phase 2's last commit was at 11:22. This phase's code commits landed between 12:41 and 13:24, and its docs about 25 minutes later, so it took about two and a half agent-hours. The effort research put picker and keymap at 6 days, shell init at 4, actions at 3 and the pty and E2E harness at 3 (16 conventional days). The time went on harness bugs (the wait marker, tcell's partial repaints, Docker Desktop's empty same-path mount) rather than on hopx itself. The prototypes' shell traps all held.

### Found in hop

- The alt-a legend is stale. `lib/ui.zsh:29` says `M-a +conf` and `bin/hop-preview:99` says "add the conf kind", but `hop.zsh:728` reloads with every kind (`_HOP_ALL_KINDS`).
- A directory whose name holds a newline breaks its row. `_hop_generate` prints the row with the newline inside it, so fzf sees two or three broken lines. hopx matches this for parity. T0 still reaches such a dir by path.

### For phase 5

- `run-all.sh` builds everything it needs, including the linux test binary for G6, and needs the `hopx-b3-fish` and `hopx-b3-pwsh` images: `docker build -f spike/docker/Dockerfile.fish -t hopx-b3-fish spike/docker`, and the same for pwsh. `NO_DOCKER=1` runs the host shells only.
- Per jump, fzf forks are still the cost: the bare binary takes 67 ms on the host for a T1 jump, and the shell function adds almost nothing. The `fzfembed` measurement is the next lever.
- pwsh on Windows remains unverified past cross-compile, as the spec says.

## Phase B4: parity and performance against the hop Eric runs

Status: done. hopx now agrees with the installed hop on every query the harness runs. The writing-style advisor pass on this file is still left for phase 5.

### The reference moved

The phases before this one held hopx to the worktree's `hop.zsh`, which is 0.2.0. Eric's install at `~/.local/share/hop` is 0.3.1, released on 2026-10-15 while the spike ran. 0.3.0 changed 702 lines of `hop.zsh`, `lib/` and `bin/`:

- Columns fit each list: a column is as wide as its longest value up to a cap, the name column fits 95% of names past 28 characters, and an all-`-` column drops out. Names are now clipped, keeping both ends around `…`.
- J3 matches a clipped name whole when the rel spells it out, so a narrow column costs no jump.
- A first word naming a non-default kind is read as `-k`: `hop file aeraki.yaml`.
- A path typed outside its repo is looked for in every repo and workspace, and a checkout on its default branch wins among clones of one origin.
- Smaller text changes: the T4 hint, the headless report's T0 and kind-word lines, and `-v`.

hopx was ported from 0.2.0, so the first run against 0.3.1 measured version drift, not port quality. This phase ported the whole 0.3.1 delta, except the modal layer's esc change, since hopx has no modal layer. `HOPX_LAYOUT=fixed` keeps the 0.2 layout so the 0.2.0-pinned goldens and harnesses still hold. The parity scripts pick the layout from the reference's `VERSION`.

### What exists

- `spike/parity/e2e.sh`: each query through each implementation's own shell function, headless.
  - zsh hop is `hop()` from `$HOP_PARITY_HOME` (default `~/.local/share/hop`) with Eric's `config.zsh` and `_hop_tty_ok` stubbed to fail.
  - hopx is the function `hopx init zsh` prints, with `testdata/eric.toml`. Every shard runs in a new session, so neither side can open `/dev/tty`.
  - The history file is a temp file, emptied before each query. Eric's history is never read or written.
  - Per query it records rc, the landing dir, the remembered dir, wall time and all of stderr, and compares verdict (jump, pick, none) and target (the landing dir, or the "best matches" line for a pick). `text` counts agreeing queries whose rc, history or any byte of stderr still differ.
  - The sets are eval_real's five, built by the reference hop from its own rows (`sets.zsh`), plus two hand-written ones: `v03` (kind words, paths, clipped names; 31 queries) and `away` (paths into other repos typed from `~`; 14 queries).
- `spike/parity/perf.sh` and `perf_zsh.zsh`: enumeration, resolve per tier and end to end, below. `__resolve-dump --ms` adds per-query resolve time.
- `rows.sh` and `resolve.sh` take `HOP_PARITY_HOME` too, and `sets.zsh stress` writes resolve_dump's three stress sets.
- `spike/hopx/build.sh`: the six cross-compile targets, with sizes.
- The 0.3.1 port: `internal/rows/layout.go` (`_hop_layout`, `_hop_lay_parse`), `unclip` in J3, `resolve.WordUnread` and the kind-word reading in `cmdHop`, and `internal/resolve/elsewhere.go` (`_hop_elsewhere`, `_hop_main_checkout`, `_hop_git_facts`), plus the report and hint text.

### Agreement per set, end to end

`e2e.sh` on `~/strava/configuration`, 2,044 queries per jump mode. Every query that agrees also matches on rc, history and stderr byte for byte (`text` 0 everywhere).

| jump | set | queries | agree | disagree |
|---|---|---|---|---|
| auto | names | 582 | 582 | 0 |
| auto | pref3 | 324 | 324 | 0 |
| auto | scope+env | 27 | 27 | 0 |
| auto | name+env | 566 | 566 | 0 |
| auto | nonsense | 500 | 500 | 0 |
| auto | v03 | 31 | 31 | 0 |
| auto | away | 14 | 14 | 0 |
| unique | all seven sets | 2,044 | 2,044 | 0 |
| never | all seven sets | 2,044 | 2,044 | 0 |

Against 0.3.1: 6,132 of 6,132 agree. Under auto, 280 names, 51 pref3, 20 scope+env, 468 name+env, 17 v03 and 10 away queries jump on both sides, and no nonsense word jumps.

Against the worktree's 0.2.0 (`HOP_PARITY_HOME=<worktree>`, before the 0.3.1 port, eval_real's five sets only): 6,000 of 6,000 agree, with `text` 0. The port from phases 1 to 3 is exact end to end.

### Every disagreement, and its cause

Before the 0.3.1 port, against 0.3.1, 88 queries disagreed: 30 under auto, 30 under unique, 28 under never. All were caused by 0.3.0's fitted layout:

- 28 names-set queries (25 under never) and one name+env query (`api-server-dem…safe-to-delete prod`) are names 0.3.1 clips, such as `github-actions…rka-runner-dev`. eval_real builds the names set from the display column, so these queries hold the `…`. hop matched them on its clipped display and jumped, or picked them under never. hopx never clipped names, so it found nothing or picked other rows.
- `ext` (pref3) and `ml dev` (name+env, never only) picked the same rows in a different order: fzf's tiebreak reads the padded display, whose widths differ.

Porting `_hop_layout` and `_hop_unclip` fixed all 88. The hand-written sets then found three more, all `_hop_elsewhere`: `configuration/terraform/acct-security-tooling-prod`, `configuration/kubernetes` and `terraform/acct-nope` from inside the repo. Porting it fixed those too. Nothing is left documented as a known disagreement.

### Lower-level parity after the port

- `rows.sh` against 0.3.1: all 14 lists byte-identical, 16,461 rows (11 kinds, the default set of 1,042, 4 workspace and 30 repo rows). Against 0.2.0 with `HOPX_LAYOUT=fixed`, also all identical.
- `resolve.sh` against 0.3.1, auto: 0 core and 0 full differences on all eight sets, 4,599 queries, with zsh run as `HOP_VIM=0` since hopx has no modal layer. Before the T4 hint was reworded, the only full differences were 525 lines of that hint (`(esc twice clears)` against `(esc clears)`).
- `resolve.sh` against 0.2.0, auto, after the port: 0 core and 0 full differences on all eight sets, 4,602 queries. The script reads 0.2.0's `(esc clears)` hint as hopx's `(ctrl-u clears)`; nothing else needed rewording.

### Speed

`perf.sh`, `~/strava/configuration`, Eric's config. The host load average was 7 to 17 throughout, from other agents, so read the ratios.

Enumeration, median of 15. hopx is a whole `hopx rows` process. hop is `_hop_rows` in an already-sourced shell, which is what `hop()` pays, and "fresh" adds a new zsh sourcing `hop.zsh`.

| list | rows | hopx ms | hop ms | hop fresh ms |
|---|---|---|---|---|
| default kinds | 1,042 | 43.4 | 282.7 | 301.4 |
| file | 12,046 | 57.8 | 1,491.5 | 1,412.0 |

That is 6.5 and 26 times faster. Phase 1 measured 24.6 ms for hopx's default list on a quieter host. The fitted layout adds nothing measurable: 43.6 ms with `HOPX_LAYOUT=fixed` and 43.0 ms without, back to back.

Resolve per tier, auto, per query with enumeration excluded, over the eight resolve.sh sets (4,599 queries). Both sides put every query in the same tier.

| tier | queries | hopx median | hopx p90 | hop median | hop p90 | hop / hopx |
|---|---|---|---|---|---|---|
| T1 | 3,012 | 29.9 | 73.7 | 32.7 | 45.1 | 1.1x |
| T2 | 474 | 33.2 | 48.2 | 77.5 | 113.6 | 2.3x |
| T3 | 6 | 67.5 | 113.6 | 51.2 | 161.1 | 0.8x |
| relaxed | 582 | 34.6 | 51.5 | 108.5 | 170.2 | 3.1x |
| T4 | 525 | 25.3 | 86.1 | 33.8 | 47.0 | 1.3x |
| all | 4,599 | 31.9 | 68.8 | 35.5 | 105.2 | 1.1x |

- The resolver itself is not where hopx wins. Both sides fork the same external fzf about 2.5 times per query, at about 10 ms each, and that is most of a T1 resolve on either side.
- hopx wins where hop does work in zsh: the T2 rewrites and the relaxed tier run 2 to 3 times faster.
- T3 has only 6 queries, so its row is noise. hopx's p90 is higher at T1 and T4, which is fork jitter under the load.
- Embedding fzf (phase 5) is the lever for this table.

End to end through each shell function, auto, serial: every 10th query of the eight sets, plus all of v03 and away, 509 calls per side. Two runs, the second under heavier load:

| group | calls | hopx median, run 1 | hop median, run 1 | hopx median, run 2 | hop median, run 2 | hop / hopx |
|---|---|---|---|---|---|---|
| eight sets, jumps | 169 | 55.4 | 341.3 | 78.2 | 498.1 | 6.2 to 6.4x |
| eight sets, no jump | 340 | 60.8 | 358.5 | 85.4 | 518.8 | 5.9 to 6.1x |
| v03 (kind words, including `file`) | 31 | 62.0 | 390.3 | 92.7 | 644.7 | 6.3 to 7.0x |
| away (paths from `~`, no enumeration) | 14 | 29.0 | 34.2 | 33.9 | 43.3 | 1.2 to 1.3x |
| all | 509 | 57.4 | 350.5 | 83.7 | 510.7 | 6.1x |

- hop's v03 p90 was 3.1 s and 4.4 s, which is `hop file x` listing 12,046 files in zsh. hopx's p90 was 147 and 168 ms.
- `away` is the one group where the two are close, because neither enumerates anything. In the parallel `e2e.sh` run hopx's median was higher there (42.6 against 30.0 ms), which is contention: serially, and in a 25-run check (hopx 21.0 ms, hop 44.0 ms with `source hop.zsh` included and 13.6 ms of that being the source), hopx is the faster.
- G7 still passes: hopx is faster than hop for every probe query and every group here.

### Cross-compile

`build.sh` (`CGO_ENABLED=0 go build -trimpath -ldflags='-s -w'`):

| target | bytes | MiB | `file` |
|---|---|---|---|
| darwin/arm64 | 3,476,354 | 3.32 | Mach-O 64-bit executable arm64 |
| darwin/amd64 | 3,715,584 | 3.54 | Mach-O 64-bit executable x86_64 |
| linux/amd64 | 3,727,522 | 3.55 | ELF 64-bit LSB executable, x86-64, statically linked |
| linux/arm64 | 3,539,106 | 3.38 | ELF 64-bit LSB executable, ARM aarch64, statically linked |
| windows/amd64 | 4,057,600 | 3.87 | PE32+ executable (console) x86-64 |
| windows/arm64 | 3,723,264 | 3.55 | PE32+ executable (console) Aarch64 |

The linux/amd64 binary ran `-V` and `init bash` in an `ubuntu:24.04` container under `--platform linux/amd64` emulation. The darwin/arm64 binary is the one every test here ran. The Windows binaries were not run, because there is no Windows host or VM available.

### Tests

`go vet ./...` is clean and `go test ./...` passes: 99 top-level tests, 338 counting subtests, across 17 packages. With `HOPX_PARITY_REPO=~/strava/configuration`, `TestParityRows`, `TestParityResolve` (against the worktree's 0.2.0), `TestRealRepoPicker`, `TestEricConfig` and `TestEricConfigLoads` pass as well.

New in this phase:

- `testfix.RefHome("v0.3.1")` unpacks hop at a tag from the worktree's own git objects into the temp dir, so tests can compare against 0.3.1 without depending on Eric's install. Tests skip when the tag or git is missing.
- `TestListLiveZsh03`: six lists, including the 95% fit, the 56 cap, dropped columns, a separator inside a value, accented names and `like` widths, byte-identical to 0.3.1's `_hop_layout`. Also `TestListWidths`, `TestListFixed` and `TestParseWidthsRejects`.
- `TestUnclip` and `TestUnclipLiveZsh03`, against 0.3.1's `_hop_unclip`.
- `TestHeadlessAgainstHop03`: the 37 headless command lines from phase 2, plus 31 for 0.3.0, run through 0.3.1's `hop()` and the hopx binary. They cover kind words with narrowed defaults, `-k`/`-a`/`-c` overriding them, a kind word outside a repo, the main-checkout jump, the never and unique picks, two origins, the repo-name prefix, the misspelt-path hint, and `-c` and `HOP_REPOS` from inside a repo. stderr, rc, landing dir and history all match. Breaking `mainCheckout` fails 3 of them, and disabling the kind-word reading fails 10.
- `TestGitFacts` (a clone, a linked worktree, scp-style and ssh URLs, a reftable repo, no origin) and `TestElsewhereWordShape`.

### I2: lines

| area | zsh lines | Go lines |
|---|---|---|
| 0.2.0 to 0.3.1 delta (`hop.zsh`, `lib/`, `bin/`) | +702 −157 | about 440 new (layout 157, elsewhere 282 non-blank, non-comment) plus about 330 net in modified files |
| its tests | 0.3.0's own tests, not ported | 337 new lines of Go test, plus the 0.3 cases in `hop_test.go` |
| parity and perf harness | not ported | 463 lines of shell and zsh |

### I3: pace

The phase started at about 13:39, after B3's docs commit at 13:36. The first runs against 0.3.1 measured the drift by about 13:55, the fitted layout was byte-identical on all 14 lists by about 14:06, and kind words and `_hop_elsewhere` agreed by about 14:35. The rest went on the harness, the timings and the docs. Porting a real upstream release took about 45 minutes of agent time. The code commits landed at 15:23.

This is the measurement the cost question most needed: a second implementation has to track every hop release. For a release of this size that is under an hour of agent time, provided the parity harness exists to say when the port is done.

### Found in hop

- Since 0.3.0, eval_real's names set includes clipped names. The 28 names 0.3.1 clips arrive as queries holding `…`, such as `github-actions…rka-runner-dev`, which nobody types. Those queries jump only because the display is clipped exactly that way, so the set now partly measures the clip rather than names. `tests/eval_real.zsh` could build names from the raw name, or skip names holding `…`.
- From inside a repo, `_hop_elsewhere` runs only for a one-word query, so `hop configuration/terraform/x vpc` never looks in other repos. That matches the CHANGELOG ("a path"), and it is worth knowing.
