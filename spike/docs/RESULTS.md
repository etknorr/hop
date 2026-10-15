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
