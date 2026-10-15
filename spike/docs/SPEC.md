# hopx spike spec

## The question

Is a proper cross-shell hop worth building, what would it cost, and how close can a quick build get? hop today is about 4.9k lines of zsh plus 9.2k lines of tests, and it only runs in zsh. The spike answers the question with a working binary measured against hop on real data, not with a design document.

The spike is additive. The working hop (v0.2.0, installed at `~/.local/share/hop`) stays the supported tool and the reference implementation throughout. hopx is a separate binary with a separate shell function, history file and config file, so the two can sit side by side in one shell.

## Hard rules for every phase

- Where code goes: work only in `/Users/eknorr/worktrees/hop/spike-cross-shell` on branch `spike/cross-shell`. Everything new goes under `spike/`. Never modify `hop.zsh`, `lib/`, `bin/`, `presets/`, `tests/`, `completions/`, `README.md`, `CHANGELOG.md`, `.github/` or any other existing file in this branch.
- Read-only: never edit `~/personal/code/hop`, `~/.local/share/hop`, `~/.zshrc`, `~/.bashrc`, `~/.config/hop/*`, other worktrees under `~/worktrees/hop/`, or `~/strava/configuration`. Reading `~/strava/configuration`, `~/.config/hop/config.zsh` and `~/.config/hop/workspaces` is expected.
- History: never write Eric's history. hopx reads and writes `$HOPX_HISTFILE`, defaulting to `${XDG_STATE_HOME:-~/.local/state}/hopx/history`. Every test and parity run sets a mktemp `HOPX_HISTFILE`. Any run that sources hop sets `HOP_HISTFILE=/dev/null`, as `tests/eval_real.zsh` does.
- Names: the binary is `hopx` and the shell function is `hopx`, so neither collides with `hop`. Config is `$HOPX_CONFIG`, else `${XDG_CONFIG_HOME:-~/.config}/hop/config.toml`. `HOP_CONFIG` keeps meaning the zsh file.
- Toolchain: Go 1.26 (installed), zsh 5.9, bash 5.3 from brew, `/bin/bash` 3.2, fzf 0.73.1 and git. fish and pwsh are not on the host, so test them in docker (`ubuntu:24.04` plus apt fish, `mcr.microsoft.com/powershell`). Don't `brew install` anything. Go dependencies come from the module cache or the proxy. The allowed ones are `github.com/BurntSushi/toml`, `golang.org/x/sys` and `golang.org/x/term`, plus `github.com/junegunn/fzf@v0.73.1` only for the optional embed measurement in phase 5.
- Shell house style: TAB indent, `emulate -L zsh` in zsh functions, and quoted expansions. Comments only for a constraint or a non-obvious why. Go code is `gofmt`ed and passes `go vet`.
- Commits: one-line Conventional Commit subjects under 72 characters, with no body and no AI attribution. Run `git branch --show-current` and confirm `spike/cross-shell` before every commit. Do not push. If a hook denies a command, stop and report it.
- Each phase ends green: `cd spike/hopx && go vet ./... && go test ./...` passes, and the phase's own parity or shell checks pass or have their mismatches recorded in `spike/docs/RESULTS.md`.

## Layout

```
spike/
  docs/SPEC.md            this file
  docs/RESULTS.md         measurements and verdicts, one section per phase
  hopx/                   Go module github.com/etknorr/hop/spike/hopx, binary hopx
    go.mod
    main.go               flag parsing and subcommand dispatch only
    internal/config/      TOML schema, loader, validation, settings, embedded presets
    internal/importer/    `hopx config import` (zsh replays config.zsh, Go re-parses)
    internal/kinds/       enumeration engine: marker/dirs/files, builtins helm/dir/repo
    internal/rows/        the 4-field row: render, split, widths, colours
    internal/gitls/       one `git ls-files -z --cached` per run, filtered in memory
    internal/mru/         rank and remember
    internal/match/       Matcher interface; external `fzf --filter` implementation
    internal/resolve/     T0..T4, decide rules, headless report
    internal/pick/        fzf argv, binds, `__sh` shim, callbacks, result parse
    internal/act/         cd (via cmdfile), open, reveal, copy, edit
    internal/shell/       embedded init scripts, `hopx init`, `__complete`
    internal/tty/         reopen /dev/tty when fds are pipes
    presets/*.toml        the 8 shipped presets, embedded
    testdata/             fixture repo builder, eric.toml, goldens
  shell/                  hopx.zsh, hopx.bash, hopx.fish, hopx.ps1 (embedded by internal/shell)
  parity/                 rows.sh, resolve_dump.zsh, resolve.sh, queries.sh
  docker/                 Dockerfile.fish, Dockerfile.pwsh and run scripts
```

Internal package boundaries can move if a phase finds a better cut, but `main.go` stays thin and every package has its own `_test.go`.

## Prior art to lift, not rewrite

Five researchers built throwaway prototypes before this spec. Each phase starts by copying the relevant one into `spike/`, then hardens it. Copy the one under `$TMPDIR` in phase 1 before anything else, because macOS purges `$TMPDIR`.

| prototype | path | what it proved | lifted in |
|---|---|---|---|
| config + engine | `/var/folders/fx/nw3rkh6j3fq9jh0lv80mckbw0000gp/T/hopx-config-spike/` (`hopx/{config,settings,engine,workspaces,import}.go`, `hopx/share/{import,compat}.zsh`, `hopx/presets/*.toml`, `compare.sh`, `fixture.zsh`, `eric.toml`) | TOML import of Eric's config; all 11 kinds byte-identical to zsh (15,370 rows); workspaces parser identical | 1 |
| enumeration bench | `~/personal/code/hop/.git/scratch/spike-bench/` (`main.go`, `files.go`, `filterbench/`, `shims/`) | 1041 default rows and 12,033 `file` rows identical, 18 ms vs 279 ms | 1, 2 |
| effort probes | `/private/tmp/claude-hopx-effort/` (`enum/`, `fzflib/`, `queries.txt`) | a 1,506-query corpus; embedded fzf matched external fzf on all of them | 2, 5 |
| picker | `~/personal/code/hop/.git/scratch/spike-picker/` (`main.go`, `binds.go`, `callbacks.go`, `shim.go`, `t/drive.py`, `t/shells.py`) | `--with-shell '<hopx> __sh'` runs every callback identically under sh, zsh, fish and pwsh; 17/17 pty checks | 3 |
| shell glue | `~/personal/code/hop/.git/scratch/spike-shells/` (`fake/init/hopx.{zsh,bash,fish,ps1}`, `fake/dup_*.go`, `test/cd.*`, `test/widget.exp`, `docker/`) | 106/106 checks across zsh, bash 5.3, bash 3.2, fish 3.7 and pwsh 7.5 | 4 |

The scratch dirs under `~/personal/code/hop/.git/scratch/` are read-only sources: copy from them, never edit them.

## Interfaces every phase relies on

### The row

A row is hop's 4-field TSV line, byte for byte (`lib/providers.zsh:68-95`):

```
<display>\t<dir>\t<preview>\t<rel>
```

- `display` is `name kind scope env region` padded to the widths `_HOP_W_NAME=28`, `_HOP_W_KIND=5`, `_HOP_W_SCOPE=22`, `_HOP_W_ENV=9` (`lib/providers.zsh:20-23`), with hop's SGR colours and `_hop_fit` clipping. scope clips from the tail.
- `dir` is the absolute target directory, `preview` the absolute preview file or the dir, and `rel` the dimmed repo-relative path. A dir target's rel ends in `/`.
- An empty column is `-`.
- Byte parity on rows is the first gate, because the resolver's rules and fzf's ranking both read these bytes.

### Matching

`internal/match` exposes `Filter(query string, rows []string) ([]string, error)`. The spike implementation forks `fzf --filter=<q>` with exactly `_HOP_MATCHER_FLAGS` (`lib/ui.zsh:384`: `--ansi --delimiter=\t --with-nth=1,4 --exact -i --tiebreak=begin,chunk`; read the array at the start of phase 2 rather than trusting this copy), with `FZF_DEFAULT_OPTS` and `FZF_DEFAULT_OPTS_FILE` cleared and never `--accept-nth`. hopx checks `fzf --version` against hop's floor 0.60.3 and refuses below it. Phase 5 may add an embedded implementation behind a build tag as a measurement.

### The cd protocol

The binary never prints shell code, and the shell never `eval`s binary output.

- The shell function sets `HOPX_CMDFILE` to a fresh path under the user's temp dir, for the binary's environment only.
- When the binary picks a directory it creates that file with `O_CREAT|O_EXCL`, mode 0600, and writes one absolute path with no newline.
- The function reads the file, deletes it, runs a plain `cd "$dir"` (never `builtin cd` and never `cd --`, which breaks zoxide's `--cmd cd`), and returns the binary's exit status. A failed `code` therefore keeps the cd and returns its status, as hop does.
- With `HOPX_CMDFILE` unset, as in a script, the binary prints the directory on stdout instead, so `cd "$(hopx foo)"` works.
- Exit 0 means success, 1 means nothing chosen or nothing matched, 2 is a usage error, and 130 is a cancelled picker.
- stdout otherwise stays the real terminal, so `hopx -h | less` works.

### Callbacks from fzf

Every fzf `preview`, `reload`, `transform` and `execute` string is a `hopx __<verb>` command, run through `--with-shell '<abs path to hopx> __sh'`. `__sh` splits its one argument into words and dispatches in-process, so no shell runs. A command that isn't `hopx …`, such as a bind from the user's `FZF_DEFAULT_OPTS`, falls through to `$SHELL -c`. State lives in a per-picker session JSON in `os.MkdirTemp` (root, kinds, cwd filter, action), passed as `HOPX_SESSION`, so no bind string embeds a path. This is the only design the researchers saw run identically under sh, zsh, fish and pwsh. hop's own POSIX-sh `transform:` bodies break under fish and pwsh.

## Scope

### In scope

- Config: the TOML format from the config research, with a top-level `presets` list, ordered `[[kind]]` tables, `extend = true`, and a `[settings]` table. The 8 presets are embedded. `hopx config import [path]` turns `config.zsh` into TOML and verifies it by loading it back. A converted copy of Eric's config is checked in as `spike/hopx/testdata/eric.toml`, and every parity run uses it so the run never depends on re-importing.
- Enumeration: the `marker`, `dirs` and `files` shapes, with every option the eight presets and Eric's config use (depth, under, layout, trim, name_template, strip_ext, exclude, preview, preview_skip, scope and `name_from = "yaml:metadata.name"`). Plus the `helm`, `dir` and `repo` builtins (`lib/providers.zsh:257`, `:308`, `:329`) and the `exec` provider protocol from the config research.
- Rows: the 4-field format above, byte-identical to `_hop_generate`.
- MRU: `_hop_rank` (`hop.zsh:158`) and `_hop_remember` (`lib/actions.zsh:59`), with the same file format and a temp-file-plus-rename write.
- Workspaces and repos: the workspaces parser (`lib/workspaces.zsh`) and `hopx -w`/`hopx -R`, enough to resolve and pick among them.
- Resolver, ported from `lib/match.zsh`:
  - T0 literal path (`_hop_literal_target`) and T1 exact.
  - The decide rules J1 `single`, J1b `onedir`, J3 `display`, J0 `name` and J2 `dir`, in `_hop_decide_jump`'s order.
  - T2a reorder and T2 typo and abbreviation rewrites (`_hop_vocab_build`, `_hop_abbrevs`, `_hop_compound`, `_hop_rewrite`).
  - T3 loose, relaxed and all-but-one, and T4 none.
  - The `_HOP_APPROX_MAX=6000` cap, `HOP_JUMP` auto/unique/never, and ancestor-dir injection with `_hop_coherence` ordering.
- Headless report: `_hop_headless_report` (`lib/match.zsh:904`), with the same stderr lines and exit 1 when there is no tty.
- Picker: external fzf, launched with the matcher flags, the preview window, `--expect=ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y`, `alt-B:print(ctrl-g)+accept`, `ctrl-/` and `alt-p` toggle-preview, `alt-a` reload to all kinds, the `:` kind menu as a reload, and the cwd filter. Preview runs as `hopx __preview`, reloads as `hopx __rows` and `hopx __menu`. The result parse matches `_hop_parse_result`.
- Actions: cd (via the cmdfile), open (`code -r <file>`, else `$VISUAL`/`$EDITOR`), reveal, ctrl-t folder, copy (`pbcopy`, `wl-copy`, `xclip`), and alt-o editor, with hop's VS Code fallbacks reduced to "on PATH or not". The binary runs editors itself: on unix it `syscall.Exec`s the editor after writing the cmdfile.
- Terminal handling: when stdin or stderr isn't a tty, reopen `/dev/tty` for fzf and for the editor. Without this the pwsh widget opens an invisible picker.
- Shell init: `hopx init zsh|bash|fish|pwsh` prints an embedded script defining the `hopx` function, `hopx -` as the shell's own `cd -`, a ^G/alt-g widget and dynamic completion via `hopx __complete`.
- Parity harness: rows and resolver verdicts compared against zsh hop on `~/strava/configuration` with Eric's config, using the five query sets from `tests/eval_real.zsh`.
- Cross-compile: `CGO_ENABLED=0` builds for darwin/{arm64,amd64}, linux/{arm64,amd64} and windows/{amd64,arm64}.

### Out of scope

- The vim modal layer, beyond what the core binds need: NORMAL/SEARCH modes, the `?` overlay, the letter table, unbind/rebind. The picker starts in plain fzf search. The bind generator is shaped so the layer could be added, but it isn't built.
- The escape guard (`bin/hop-guard`, `HOP_GUARD_WINDOW`).
- `--doctor`, the debug log and `=short` redaction.
- `hop upgrade`. Packaging owns updates in a production hopx.
- Windows beyond cross-compiling. There is no claim that hopx runs on Windows, and `code.cmd` quoting, `CONOUT$` and drive letters are not built.
- Packaging: no goreleaser, brew tap, scoop or winget.
- The drill and up pickers (ctrl-l, ctrl-h), the kind-count cache and its warmer, and `.hoprc`/`.hop.toml` trust.
- Porting hop's 645 test cases. The spike writes its own Go tests and relies on the parity harness for behaviour.
- Changing hop. Bugs found in hop go into `RESULTS.md` under "Found in hop" for the agents fixing hop. They are not fixed here.

## Build phases

Each phase is sized for one agent in one sitting. Phases run in order, and each starts by reading this spec and the previous phases' sections of `RESULTS.md`. A phase that can't finish records what is left at the top of its `RESULTS.md` section, and the next phase starts there.

### Phase 1: module, config, enumeration and row parity

Goal: `hopx rows` prints exactly what `_hop_generate` prints for Eric's config on `~/strava/configuration`.

Deliverables:
- `spike/hopx/go.mod` (module `github.com/etknorr/hop/spike/hopx`, go 1.26) and a `main.go` with subcommand dispatch and `-h`.
- The `$TMPDIR` config prototype copied into `internal/config`, `internal/importer` and `internal/kinds` first, then reshaped into the layout above.
- `internal/config` with the schema, loader, `extend`, `presets`, and the 8 presets embedded with `//go:embed`. Validation reports the TOML line for an unknown key, more than one shape key, an unknown layout or trim column, `...` on a column other than the last, and a name holding `,` or a space. `[settings]` follows flag > env > file > default.
- `internal/importer`: `hopx config import [config.zsh] [-o out.toml]` runs `share/import.zsh` under `zsh -f`, replays the records, writes TOML and verifies it by loading it back. The default output is stdout, and it never writes `~/.config/hop/config.toml` unless `-o` names it.
- `spike/hopx/testdata/eric.toml`, produced by import from Eric's real config and checked in.
- `internal/gitls`, `internal/kinds` (marker, dirs, files, exec, builtins helm/dir/repo) and `internal/rows` (render, `_hop_fit`, colours, widths).
- `hopx rows [-k kinds] [--root DIR] [--all]`, which prints rows to stdout and doesn't rank.
- `spike/parity/rows.sh`, which:
  - sources the worktree's `hop.zsh` with `HOP_CONFIG=~/.config/hop/config.zsh` and `HOP_HISTFILE=/dev/null`, and dumps `_hop_generate` for each kind and for the default set;
  - runs `hopx rows` with `HOPX_CONFIG=testdata/eric.toml`;
  - `cmp`s each pair and prints one line per kind: `kind rows-zsh rows-hopx IDENTICAL|DIFF first-diff-line`.

Tests (`go test`):
- Config: every validation error, `extend` merging, a redeclared kind keeping its menu position, an empty registry loading all 8 presets, and an import round trip on `config.example.zsh` and on a fixture config that covers every option.
- Engine: a generated fixture git repo built in `t.TempDir()` (port `fixture.zsh`), with golden rows per kind covering:
  - the root-level marker, depth 2, and strip_ext at the last `.`;
  - layouts tried longest first, `...` joins, trim in order, name_template, and the no-layout early return;
  - preview globs with `**/`, zero-byte skip, the symlink refusal, and preview_skip on the basename.
- Rows: width padding, tail clipping of scope, and SGR bytes against goldens captured from `_hop_row`.
- Parity, skipped unless `HOPX_PARITY_REPO` is set: `rows.sh` as a Go test wrapper.

Exit criteria: all 11 of Eric's kinds and the default set are IDENTICAL on `~/strava/configuration`, or every DIFF is explained in `RESULTS.md`. Record wall time for `hopx rows` against sourcing hop and running `_hop_generate` (default kinds and `file`, median of 15 runs each).

Example commits: `feat(spike): add hopx module, TOML config and presets`, `feat(spike): port the kind engine and row renderer`, `test(spike): add the rows parity harness`.

### Phase 2: MRU, resolver and headless report

Goal: `hopx <query>` without a tty decides exactly as `hop <query>` does, with the same verdict, tier, rule and target, and the same headless report.

Deliverables:
- `internal/mru`: `Rank(rows, hist)` and `Remember(dir)`.
  - `Rank` matches `_hop_rank`: the rank+index stable key, and only rows whose dir is in history move.
  - `Remember` matches `_hop_remember`: dedupe, absolute only, existing dirs only, `HOP_HIST_MAX` default 300, written via temp file plus rename.
- `internal/match`: the external fzf Matcher and the version check.
- `internal/resolve`: a straight port of `lib/match.zsh`, function by function. Each Go function keeps its zsh function's name in a doc line, so a reviewer can diff the two side by side. It returns a `Result{Verdict, Tier, Rule, Query, Note, Target, N, M, Inj, Rows}` that mirrors the `_hop_res_*` globals. `_hop_hits` and `_hop_text_build` may use their in-memory fast path or call the Matcher, as long as verdicts match.
- `hopx [words]` headless: T0 runs first, before enumeration, as `hop()` does. Then enumerate, rank, resolve, and either jump (cmdfile or stdout) or print the headless report and exit 1.
- `hopx __resolve-dump`, hidden: reads one query per line on stdin and prints `query\tverdict\ttier\trule\trel(target)\tn` per query against one enumeration. It never cds or writes history.
- `spike/parity/resolve_dump.zsh`, which:
  - sources the worktree's `hop.zsh` the way `tests/eval_real.zsh` does (copy its setup, never edit it);
  - builds the five query sets with eval_real's own construction: names, pref3, scope+env, name+env, and nonsense from `tests/fixtures/dictionary.txt`;
  - prints the same TSV, running T0 and then `_hop_resolve` per query;
  - writes the query sets to files, so hopx reads the identical list.
- `spike/parity/resolve.sh`: runs both, diffs per set, and prints a table of `set queries same diff` plus the first 20 diffs. Run it once per `HOP_JUMP` value of auto, unique and never.

Tests (`go test`):
- MRU: ordering ties, two rows sharing one dir, history naming no row, dead dirs pruned, the cap, and an atomic write that survives a concurrent reader.
- Resolver unit tests on the phase-1 fixture repo, at least one per tier and per rule. Expected values are captured from `_hop_resolve` on the same fixture through a small zsh helper checked into `testdata/`.
- Literal paths: `.`, `..`, `./x`, `/x` under the root, `~` forms, case-insensitive segments, and a trailing slash.
- Headless report: golden stderr for none, pick at T1, pick at T2/T3, relaxed, and `HOP_JUMP=never`.

Exit criteria: `resolve.sh` reports per-set counts. The go/no-go bar below needs zero diffs on names, scope+env and name+env, and zero nonsense jumps. Every remaining diff is listed in `RESULTS.md` with its cause. Record per-query resolve time, and end-to-end `hopx -p <q>` against `hop -p <q>` for `vpc`, `vpc prod`, `eks staging` and a four-word query.

### Phase 3: picker and actions

Goal: in a real terminal, `hopx` opens fzf over the ranked rows, the preview works, the core keys do what hop's do, and choosing a row lands in the right place.

Deliverables:
- `internal/pick`, lifted from the picker prototype. The fzf argv builder covers:
  - the matcher flags, prompt, header, preview window and `--expect`;
  - the binds listed under scope;
  - `--with-shell '<hopx> __sh'` and the session JSON;
  - `HOP_FZF_HEIGHT`, where set-but-empty means fullscreen, so use `LookupEnv`.
- Callbacks:
  - `__sh`;
  - `__preview {2} {3}`, a port of `bin/hop-preview` for files and dirs, without the `?` overlay;
  - `__rows <kinds>`, from session state, ranked, honouring the cwd filter;
  - `__menu`, the `:` kind list as rows, where Enter on a kind row reloads to that kind.
- Result parsing that matches `_hop_parse_result`: the first non-empty key line, fields split with empties kept, and an empty preview defaulting to dir.
- `internal/act`: dispatch per key as in `lib/actions.zsh:394-399`, plus Enter under `--action`/`HOP_ACTION` cd, open, reveal, cd+open and cd+reveal. The binary execs editors and starts `code`. `remember` follows hop's rules: cd, ctrl-o and ctrl-t remember, and copy does not.
- `internal/tty`: reopen `/dev/tty` for fzf's stdin and stderr, and before the editor exec, when fds are pipes. Use `Dup2` on darwin and `Dup3` on linux, as in `fake/dup_*.go`.
- Flags `-a -k -c -p -o -e --cd --action= -w -R -h -V`, with hop's exit-2 combination rules.

Tests (`go test`):
- argv goldens for default, `-c`, `-k helm`, `--action=open` and `HOP_FZF_HEIGHT=` set but empty.
- Every argv parses: run `fzf <argv> --filter x </dev/null` and expect exit 0 and no `unknown action`. A control injects a bogus action and expects exit 2.
- `__sh` dispatch, including a non-hopx fallthrough.
- `__preview` output for a file, a dir with a README, and an empty dir.
- `__rows` matching `hopx rows` plus rank.
- Result-parse cases, including a blank `--expect` line and `alt-B`.
- A pty test using `script(1)` or a minimal Go pty helper (no new deps; `golang.org/x/sys/unix` openpty is fine):
  - type a query, press Enter, and check the cmdfile holds the expected dir;
  - press ctrl-y with a stub `pbcopy` on PATH, and check the clipboard file.

Exit criteria: the pty tests pass on macOS. A manual check with Eric's real data is recorded in `RESULTS.md` (query, key, outcome). Record the latency of `__preview` and `__rows` against `bin/hop-preview` and `bin/hop-kinds rows`.

### Phase 4: shell init in four shells

Goal: `eval "$(hopx init <shell>)"` gives a working `hopx` function, `hopx -`, the widget and completion in zsh, bash 5, bash 3.2, fish and pwsh.

Deliverables:
- `spike/shell/hopx.{zsh,bash,fish,ps1}`, lifted from `spike-shells/fake/init/*` and embedded by `internal/shell`. `hopx init <shell> [--cmd NAME]` prints them, and `--cmd` renames the function zoxide-style without ever defaulting to `hop`. The scripts must carry over the traps the shells research recorded:
  - zsh: `command hopx`, `zle push-input` plus accept-line for the widget so precmd re-runs, and `compdef` only when compinit already ran.
  - bash 4+: the `bind -x` save/restore of READLINE_LINE and READLINE_POINT around accept-line, bound in emacs, vi-insert and vi-command.
  - bash 3.2: the kill-ring macro, plus the empty-word fix in completion (`"${COMP_WORDS[COMP_CWORD]}"`).
  - fish: `string collect`, plain `cd` (not `builtin cd`, which breaks `cd -`), and `commandline -f repaint`.
  - pwsh: `$env:` set and then cleared in `finally`, the absolute binary path baked in, `Set-Location -LiteralPath`, `Get-Command Set-PSReadLineKeyHandler` to autoload PSReadLine, and `InvokePrompt()`.
- `hopx __complete <words…>`: flags, and kinds with their descriptions from the loaded config.
- `spike/docker/Dockerfile.fish` and `Dockerfile.pwsh`, each with:
  - an Ubuntu base plus fish or pwsh;
  - fzf 0.73.1 from the GitHub release, checksum-verified, since distro fzf 0.44.1 is below the floor;
  - git, and the linux/arm64 hopx bind-mounted in;
  - `~/strava/configuration` mounted read-only at the same path.
- Shell tests under `spike/shell/test/`:
  - `cd.sh` (run by zsh, bash 5.3 and `/bin/bash`), `cd.fish` and `cd.ps1`.
  - Each covers the cd contract on `plain`, `with space`, `trail-space-backslash\ `, `café`, an embedded newline and `brack[1]`.
  - Each also covers cancel (130, no move), `--cd-then-fail` (rc kept, PWD moved), a bare binary printing its dir, `hopx -`, and stdout piping.
  - `widget.exp` and `complete.exp` come from the prototype.
  - `run-all.sh` runs the host shells and both containers, and prints a pass count per shell.
- A Go test that runs `hopx init` for each shell and checks that the output parses: `zsh -n`, `bash -n` and `/bin/bash -n`, plus `fish -n` and pwsh `[scriptblock]::Create` when docker is available.

Exit criteria: `run-all.sh` passes in all five shells, or each failure is recorded in `RESULTS.md` with a cause. The pwsh backslash-path limitation on Unix is expected and recorded, not fixed. Record per-jump time and shell startup cost per shell, against hop's ^G jump and `source hop.zsh`.

### Phase 5: cross-compile, measurements and the verdict

Goal: one document that answers Eric's question with numbers.

Deliverables:
- `spike/hopx/build.sh`: `CGO_ENABLED=0 go build -trimpath -ldflags='-s -w'` for the six targets, with `file` output and sizes recorded.
- A linux/arm64 run of `rows.sh` and `resolve.sh` inside docker against the read-only repo, which should match the darwin results.
- Optional, behind a `fzfembed` build tag: an embedded-fzf Matcher. It uses `fzf.ParseOptions` plus `fzf.Run` from `github.com/junegunn/fzf@v0.73.1/src`, with calls serialized because fzf keeps package globals. Rerun `resolve.sh` with it and record identity, per-call latency and binary size. It stays off by default.
- `spike/docs/RESULTS.md`, completed with:
  - one table per go/no-go criterion below, with measured value, bar and pass/fail;
  - the cost estimate, revised by what the build actually needed;
  - "Found in hop";
  - a one-paragraph recommendation.
- The full parity and shell suites rerun once from a clean `go build`, with results pasted in.

Tests: `go test ./...` and `go test -tags fzfembed ./...` both pass, and the parity and shell suites have run as above.

## Go/no-go criteria the spike measures

Each criterion gets a measured value in `RESULTS.md`. Go means every row in "must pass" passes and the cost estimate still holds after the build.

### Must pass

| # | criterion | bar | measured by |
|---|---|---|---|
| G1 | Row parity, default kinds and all of Eric's 11 kinds | byte-identical on `~/strava/configuration` | `parity/rows.sh` |
| G2 | Config migration | `hopx config import` on Eric's config.zsh and `config.example.zsh` produces TOML that loads back to the same registry, with no hand edits | importer test, plus `eric.toml` |
| G3 | Resolver parity, sets names, scope+env and name+env | 0 differences in verdict, tier, rule or target, under `HOP_JUMP=auto` | `parity/resolve.sh` |
| G4 | Resolver safety, nonsense set | 0 jumps | `parity/resolve.sh` |
| G5 | Shell coverage | the cd contract, `hopx -` and the widget pass in zsh 5.9, bash 5.3, bash 3.2, fish and pwsh 7, except the documented pwsh-on-Unix backslash case | `spike/shell/test/run-all.sh` |
| G6 | Callbacks shell-independent | preview, reload and the `:` menu work with `SHELL` set to sh, zsh, fish and pwsh | phase-3 pty test rerun in docker |
| G7 | Speed, not slower anywhere | `hopx -p <q>` before first draw ≤ hop's for all four probe queries; per-jump time ≤ hop's ^G | phase 2 and 4 timings |

### Inform the decision, no fixed bar

| # | measurement | why it matters |
|---|---|---|
| I1 | pref3 and the `unique`/`never` sweeps, diff count | pref3 is the noisiest set, since three-letter prefixes hit T2 and T3 heavily; a small residual is expected, a large one means the resolver port is unfinished |
| I2 | Go lines per zsh lines ported, per area | calibrates the production estimate |
| I3 | Agent-hours per phase, from commit timestamps | calibrates the "divide by 1.6-2" pace assumption |
| I4 | Binary size per target, with and without embedded fzf | the cost of dropping the external fzf |
| I5 | Embedded vs external fzf: identical results and per-call latency | decides (c) below |
| I6 | Bugs found in hop along the way | value of the spike even on a no-go |

### Stop rule

If G1 or G3 is still far off at the end of phase 2, for example more than 1% of names-set queries differ for causes not understood, stop. Write up phases 1 and 2 and skip phases 3 and 4. A resolver that won't converge is the failure the effort research named as the reason not to proceed, and the zsh hop keeps working regardless.

## Production effort estimate (what the spike is checking)

These figures come from the effort research: one engineer, focused 5-day weeks at a conventional pace, using hop's code and 645 test cases as the spec. At the agent-assisted pace hop itself was built at (v0.1.0 to v0.2.0 in about 7 calendar weeks), divide by about 1.6 to 2. Phase 5 revises them with what the build actually took.

| option | scope | estimate | agent-assisted |
|---|---|---|---|
| (a) | feature parity, fzf external, macOS and Linux, zsh + bash 5 (+ degraded bash 3.2) + fish, brew tap | about 11 weeks (8 to 13) | about 6 to 7 weeks |
| (b) | (a) plus Windows/PowerShell: path normalization, PSReadLine widget, pwsh completions, windows CI, scoop and winget | about 14 weeks (11 to 17) | about 8 to 9 weeks |
| (c) | (a) with fzf embedded as a Go library | about 11.5 weeks; about 14 with Windows, since embedding pays for itself there | about 6.5 to 7 weeks |
| (c′) | (a) with a custom bubbletea or tcell picker instead of fzf | about 17 weeks | not recommended |

Where the time goes in (a), roughly 55 focused days:

| item | days |
|---|---|
| resolver port | 8 |
| test port to Go | 7 |
| picker and keymap | 6 |
| config and import | 4 |
| shell init | 4 |
| parity harness, pty/E2E | 3 each |
| actions | 3 |
| docs | 2.5 |
| everything else | under 2 each |

The milestone-1 decision point (enumeration, resolver and parity harness green) is about 3 conventional weeks. This spike's phases 1 and 2 are that milestone compressed.

Two estimates from the other areas, for reference. They overlap with (a) rather than adding to it.

| area | estimate |
|---|---|
| config and kind DSL alone | 3 to 4 weeks |
| shell integration alone | 4 to 5 weeks, 3 to 3.5 without Windows |

What the research already settled, so the spike doesn't re-litigate it:

- Go over Rust: only Go gets fzf's exact matcher in-process, it cross-compiled for 7 targets with no extra toolchain, and it is the only toolchain on the host.
- TOML over YAML: a bare `- *.tf` is YAML alias syntax.
- No `eval` of binary output.
- Every fzf callback goes through `hopx __*`.
- zsh hop stays the frozen reference.

## Known risks the spike should surface, not solve

- The fzf Go API isn't a stable contract. Pin the version exactly, and canary-test it if embedding.
- Windows is unverified past cross-compile. That covers `code.cmd` quoting, `CONOUT$`, drive letters, and the cmd.exe default shell for fzf binds.
- User `--fn` kinds are zsh code. They migrate through `exec` plus `compat.zsh`, which still needs zsh at runtime.
- Settings precedence flips: env beats file in hopx, where config.zsh beats env in hop.
- There are two configs during coexistence. config.zsh stays the source, and config.toml is regenerated from it.
- The zsh and bash widgets submit ` hopx` as a command line. It shows in scrollback, and lands in history unless ignorespace is set.
- Three zsh behaviours are deliberately not matched: locale-dependent glob order, a literal preview candidate that is a directory, and equal-width layout tie-breaks. None shows on Eric's repo.
