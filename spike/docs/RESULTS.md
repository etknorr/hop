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
