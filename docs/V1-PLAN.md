# hop 1.0 build plan

hop 1.0 is the Go binary from the hopx spike, renamed `hop`, at parity with zsh hop 0.3.1 for daily use, with nothing Strava- or Eric-specific in its code or zero-config defaults. The zsh implementation is deleted from the repo at the end.

This file is for the agents building it. Read it top to bottom before starting a workstream, then read `docs/spike/FINDINGS.md` and `docs/spike/DEVIATIONS.md` (at `spike/docs/` until the restructure moves them).

## 0. Ground rules and starting state

### Decisions already made (Eric's, final)

- The binary is `hop`. The zsh implementation is deleted, not maintained.
- macOS and Linux only. The Windows cross-compile stays in `scripts/build.sh` and CI compiles it, but nobody does Windows work.
- Shells: zsh, bash 5.x, macOS `/bin/bash` 3.2, and fish. Each gets `eval "$(hop init <shell>)"`, and fish gets `hop init fish | source`. PowerShell isn't a 1.0 shell (see 4.6).
- Parity with zsh hop 0.3.1 for daily use, as listed in section 2.
- Zero-config defaults are generic: `dir`, `project` and `file`. The six old presets become opt-in recipes. Eric's layout lives in his config.
- Migration happens once, for Eric, through `hop import`. The history and workspaces file formats stay as they are.
- Distribution is Homebrew (a formula in this repo) plus `go install`, released from a `v*` tag.

### Hard rules for every agent

- Write only in your own worktree under `~/worktrees/hop/<slug>` and on your branch. Create it with `git -C ~/personal/code/hop fetch origin` and then `git -C ~/personal/code/hop worktree add ~/worktrees/hop/<slug> -b <branch> origin/v1/go`. Never under `/tmp`, and never switch branches in `~/personal/code/hop`.
- Read-only: `~/.zshrc`, `~/.config/hop/`, `~/.local/share/hop`, `~/strava/configuration`. Generated config goes to a file in the worktree, such as `testdata/eric.toml`.
- Never write Eric's history, `~/.local/state/hop/history`. After the restructure the binary's default history path IS that file, so every test, harness and manual run sets `HOP_HISTFILE` to a temp file. Gate: the file's checksum is the same before and after your run.
- Never `go install`, `brew install` or `brew tap` on the host: each writes outside the worktree. Build with `go build -o <worktree>/bin/hop .`.
- No merges to `main`, no tags, no releases, no PRs. Push your branch when your task says so.
- Commits: one-line Conventional Commit subjects (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `build:`, `ci:`), at most 72 characters, no body, no AI attribution, no ticket IDs, one logical concern each.
- Code style matches the spike: `gofmt`, `go vet` clean, no comment unless it names a constraint, trap or non-obvious why.
- Allowed Go dependencies stay the spike's: `github.com/BurntSushi/toml`, `golang.org/x/sys`, `golang.org/x/term`. No workstream adds one, so `go.sum` never conflicts.
- fzf floor stays 0.60.3. Scratch binaries: `~/personal/code/hop/.git/scratch/bin0603/fzf` (0.60.3) and `bin0670/fzf` (0.67.0). The host's `/opt/homebrew/bin/fzf` is 0.73.1, the latest. Linux fzf tarballs for docker are in `~/personal/code/hop/.git/scratch/linux` and `spike/docker`.
- A hook or permission denial means stop and report it. Never route around one.
- Verify with real runs: `go vet ./...`, `go test ./...`, the parity harness and the pty tests. Report failures as they are.

### Where v1/go stands at a4c7f42

`v1/go` holds the spike under `spike/` plus main at 0.3.1. Merging main moved the worktree's `hop.zsh` from 0.2.0 to 0.3.1, and four live-zsh tests that compare against the worktree's `hop.zsh` now fail, because they expect 0.2.0's fixed layout and its T4 hint:

```
FAIL internal/kinds    TestWorkspaceAndRepoRowsMatchZsh, TestLiveZsh
FAIL internal/resolve  TestLiveZsh (57 of 126 cases: "(esc twice clears)" vs "(ctrl-u clears)")
FAIL internal/rows     TestRenderLiveZsh (fixed vs fitted layout)
```

`go vet` is clean and every other package passes. The restructure fixes these four (section 4.1).

## 1. Target layout

After the retirement step the repo looks like this:

```
go.mod                    module github.com/etknorr/hop, go 1.26
go.sum
main.go                   verb registry and dispatch, -h, -V (B)
hop.go                    hop()'s flow: T0, levels, enumerate, rank, resolve, pick (A)
cmd_picker.go             __rows, __menu, __key, __guard, __keys, __hopw (A)
cmd_shell.go              init, __complete, upgrade, --doctor (B)
cmd_config.go             import, __config, __kinds, __dump-rows (C)
internal/
  act/                    cd, open, reveal, edit, copy, browse, Enter modes (A)
  collate/                zsh's en_US sort order (frozen)
  config/                 TOML schema, settings, recipes, zero-config defaults (C)
    recipes/*.toml        dir, project, file, terragrunt, terraform-modules, helm, serverless, puppet, backstage
  debuglog/               HOP_DEBUG log (B)
  doctor/                 --doctor and --doctor=short (B)
  gitls/                  one git ls-files per run (C)
  guard/                  the escape guard's mark and check (A)
  importer/               hop import: config.zsh to TOML (C)
    share/import.zsh
    v031/presets.toml     0.3.1's eight presets, frozen, for the importer only
  keymap/                 the modal layer's binds, headers and ? overlay (A)
  kinds/                  marker, dirs, files, sources, exec, builtin dir (C)
  match/                  fzf --filter matcher and the version floor (A)
  mru/                    rank and remember (A)
  pick/                   fzf argv, session, __sh shim, preview, result parse (A)
  ptytest/                pty helper (A)
  resolve/                T0 to T4, decide rules, headless report (A)
  rows/                   the 4-field row, layout, colours (C)
  shell/                  init scripts and completion (B)
    init/hop.zsh, hop.bash, hop.fish
  testfix/                fixture repo builder, RefHome (frozen)
  tty/                    /dev/tty reopen (frozen)
  upgrade/                hop upgrade for brew, go install and checkouts (B)
  version/                version string, build info, init staleness (B)
  workspace/              workspaces parser and repo discovery (frozen)
testdata/
  eric.toml               Eric's imported config, the parity runs' Go-side config
  golden/                 row, argv and report goldens
  public/                 goldens for the public test repos
  repos.lock              pinned public repos (name, URL, commit)
  fetch-repos.sh          shallow-fetches repos.lock into testdata/repos/ (gitignored)
test/
  parity/                 rows.sh, resolve.sh, e2e.sh, perf.sh, corpus/ (A edits, all run)
  shell/                  cd.sh, pick.sh, cd.fish, pick.fish, *.exp, rc/, run-all.sh (B)
  docker/                 Dockerfile.fish, fzf.sha256 (B)
scripts/build.sh          six-target cross-compile, Windows included (B)
.goreleaser.yaml          release archives (B)
Formula/hop.rb            the Homebrew formula (B)
.github/workflows/        ci.yml, release.yml (B)
docs/RELEASING.md         release steps for the Go binary (B)
docs/SMOKE.md             manual picker checks, rewritten for Go (A)
config.example.toml       a working config to copy (C)
workspaces.example        unchanged (C)
README.md, CHANGELOG.md, CONTRIBUTING.md, LICENSE, VERSION, .editorconfig, .gitignore
```

Where each existing path goes:

| Path today | 1.0 | When |
|---|---|---|
| `spike/hopx/*` | repo root (`go.mod`, `*.go`, `internal/`, `testdata/`) | restructure |
| `spike/hopx/internal/config/presets/` | `internal/config/recipes/`, rewritten generic | C |
| `spike/hopx/build.sh` | `scripts/build.sh` | restructure |
| `spike/parity/` | `test/parity/` | restructure |
| `spike/shell/test/` | `test/shell/` | restructure |
| `spike/docker/` | `test/docker/`; `Dockerfile.pwsh` and `pwsh.sha256` deleted | restructure moves, B deletes pwsh |
| `spike/docs/` | `docs/spike/`, deleted at retirement (git keeps it) | restructure, retirement |
| `hop.zsh`, `hop.plugin.zsh`, `lib/`, `bin/` | deleted | retirement |
| `presets/*.zsh` | deleted; recipes replace them, and the importer keeps a frozen 0.3.1 copy as TOML | retirement |
| `completions/_hop` | deleted; `hop init <shell>` emits completion | retirement |
| `tests/` (24 suites, 713 cases) | deleted after each case is ported or marked n/a in a ledger (4.2) | retirement |
| `tests/eval_real.zsh` query sets | already rebuilt by `test/parity/sets.zsh` from the oracle install | nothing to move |
| `SMOKE.md` | `docs/SMOKE.md`, rewritten for the Go picker | A |
| `config.example.zsh` | `config.example.toml` | C |
| `internal/kinds/compat.zsh` | deleted with `--fn` support (3.2) | C |
| `.github/ISSUE_TEMPLATE/*`, `CONTRIBUTING.md` | rewritten for Go | retirement |

The main package is at the repo root so `go install github.com/etknorr/hop@latest` installs a binary named `hop`.

## 2. Parity checklist

Status is the spike's at a4c7f42: **done** (matches 0.3.1), **missing**, **deviates** (behaves differently), or **new** (1.0 adds it on purpose). zsh refs are files in this repo at 0.3.1. Spike refs are relative to `spike/hopx/`, which the restructure moves to the repo root, so they stay valid after it. The owner is the workstream that closes the row: R (restructure and seams), A, B, C, or I (integration).

The resolver, rows and headless output are already proven: rows are byte-identical for all 14 lists, 13,797 resolver queries agree under all three `HOP_JUMP` modes, and 6,132 end-to-end queries agree on exit code, every byte of stderr and the remembered history. Rows marked done in 2.2 and 2.3 are covered by that harness and need no new work beyond keeping it green.

### 2.1 Command line (`hop.zsh:465` `hop()`; spike `hop.go:37` `parseHop`, `hop.go:343` `cmdHop`)

| Behaviour | zsh | Spike | Status | Owner |
|---|---|---|---|---|
| `hop` alone opens the picker on the default kinds, in NORMAL mode | `hop.zsh:810`, `lib/ui.zsh:306` | `hop.go:343` | deviates: no modal layer | A |
| `hop words...` resolves; a clear match jumps, otherwise the picker opens best-first; no tty prints the headless report and exits 1 | `hop.zsh:284` | `hop.go:225`, `resolve/report.go:35` | done | |
| `-a`, `--all` | `hop.zsh:495` | `hop.go:43` | done | |
| `-k`, `--kinds K[,K...]`, attached `-kK`; `-k` alone says `hop: -k needs a comma-separated kind list`, exit 2 | `hop.zsh:582` | `hop.go:64` | done | |
| `-c`, `--cwd`, `--here`: rows under the physical `$PWD`, kept through every reload | `hop.zsh:687` | `hop.go:379`, `callbacks.go:54` | done | |
| `-R`, `--repos`; `-w`, `--workspaces` | `hop.zsh:500` | `hop.go:310`, `hop.go:333` | done, but no drill or up (2.9) | A |
| `-p`, `--pick` | `hop.zsh:515` | `hop.go:51` | done | |
| `--cd`, `-o`/`--open`, `-e`/`--reveal`, `--action=MODE`, and their exit-2 messages: `-o and -e are exclusive`, `--action=MODE cannot be combined with --cd, -o or -e`, `--action=X is not one of cd, open, reveal, cd+open, cd+reveal`, `--action needs a mode` | `hop.zsh:520-544`, `:622-636` | `hop.go:55-107` | done | |
| `--no-vim`, `--vim` | `hop.zsh:545` | none | missing | A |
| `--doctor`, `--doctor=short`, `--doctor short`; `--doctor=x` says `hop: --doctor=x: unknown --doctor mode, want: --doctor=short`, exit 2 | `hop.zsh:555` | none | missing | B |
| `-V`, `-v`, `--version` | `hop.zsh:491`, `:136` | `main.go:102` prints `hopx 0.0.0-spike` | deviates | B |
| `-h`, `--help`: usage, keys, and the registered kinds with `*` on defaults | `hop.zsh:47` | `main.go:25` | deviates: different text | B |
| `--` ends options; `hop: unknown option: X`, exit 2 | `hop.zsh:606` | `hop.go:84` | done | |
| `hop /` cds to the repo root; `hop: not in a git repository`; `/` or `-` with anything else says `hop: / takes no other arguments`, exit 2 | `hop.zsh:596`, `:646` | `hop.go:73`, `:363` | done | |
| `hop -` is `cd -` | `hop.zsh:638` | the init scripts do it; the bare binary exits 2 with a message | done in the shell | |
| `upgrade` is the verb only as the first word with nothing before it | `hop.zsh:571` | none | missing | B |
| A first word naming a non-default kind with rows here is read as `-k`, with `hop: reading "file" as -k file` | `hop.zsh:698-720` | `hop.go:381-405` | done | |
| T0: a typed path jumps before enumeration; not under `-w`, `-R` or `HOP_JUMP=never` | `hop.zsh:724` | `hop.go:412` | done | |
| A path missing here is looked for in other repos and workspaces | `hop.zsh:740`, `lib/match.zsh:180` | `resolve/elsewhere.go:34` | done | |
| `hop: fzf is not installed`, exit 1 | `hop.zsh:743` | `match/match.go` | done | |
| fzf below the floor: four lines naming the version, the cause and the fix | `lib/ui.zsh:361` | `match/match.go:133`, one line | deviates | A |
| `HOP_FZF_MIN` lowers the floor | `lib/ui.zsh:320` | none | missing | A |
| An invalid `HOP_JUMP` warns `hop: HOP_JUMP=x is not one of auto, unique, never; using auto` | `hop.zsh:671` | `config/settings.go` warns in other words | deviates | C |
| An invalid `HOP_ACTION` warns `hop: HOP_ACTION=x is not one of cd, open, reveal, cd+open, cd+reveal; using cd` once per call | `lib/actions.zsh:87` | `config/settings.go` | deviates | C |
| `hop: no kinds selected`, exit 2; `hop: no targets under PWD for kinds: k`, exit 1; `hop: no targets in ROOT for kinds: k`, exit 1 | `hop.zsh:772-797` | `hop.go` | done | |
| Outside a repo: the workspace picker when workspaces exist (with the repo fallback), else the repo picker | `hop.zsh:758` | `hop.go:310` | done | |
| `hop: no workspaces configured (edit FILE)`; `hop: not in a git repository, and no repos found (set $HOP_REPOS)` | `hop.zsh:376`, `:452` | `hop.go` | done | |
| `hop: no readable repos in $HOP_REPOS` | `hop.zsh:456` | folded into the status-1 message | deviates | A |
| `hopr` cds to the repo root | `hop.zsh:813` | none | missing | B (shell), uses `hop /` |
| `hopw` cds to the workspace holding `$PWD`, longest prefix; `hop: PWD is not inside any configured workspace` | `hop.zsh:413` | none | missing | A (`hop __hopw`), B (shell function) |
| `^G` and `alt-g` open hop from a half-typed line, which survives | `hop.zsh:827` | `shell/init/hopx.zsh` uses `push-input` plus `accept-line` | deviates: ` hop` reaches scrollback, and history without `HIST_IGNORE_SPACE`. Kept, because precmd hooks then see the new dir | B |
| Esc out of the picker returns 0 | `hop.zsh:253` | returns 130 | deviates | A: return 0 |

### 2.2 Resolver (`lib/match.zsh`; spike `internal/resolve/`)

| Behaviour | Status | Owner |
|---|---|---|
| T0 literal paths: `.`, `..`, `./x`, `/x`, `~` and `~user` forms, case-insensitive segments, trailing slash (`resolve/literal.go:74`) | done | |
| T1 exact; T2a reorder; T2 typo, abbreviation, compound and env-word rewrites (`_HOP_ENV_WORDS`, `lib/match.zsh:16`); T3 loose, relaxed and all-but-one; T4 none (`resolve/resolve.go:519`) | done | |
| Decide rules J1 single, J1b onedir, J3 display, J0 name, J2 dir, in order; unclipped names in J3 | done | |
| `_HOP_APPROX_MAX=6000` and its note `typo matching skipped above 6000 rows` | done | |
| `HOP_JUMP` auto, unique, never; ancestor-dir injection with coherence order | done | |
| Headless report lines (`lib/match.zsh:1195-1250`; `resolve/report.go:35`) | done | |
| T4 hint: `nothing close to: q (esc twice clears)` with the modal layer on, `(ctrl-u clears)` with `HOP_VIM=0` (`lib/match.zsh:1158`) | deviates: always `(ctrl-u clears)` (`resolve/resolve.go:631`) | A |
| Other-repo notes: `hop: X -> rel (found in repo...)` and `hop: no repo has W, but SEG/ is in ...` (`lib/match.zsh:248`, `:264`) | done | |
| `hash -d` named dirs in `~` forms and `(D)` abbreviation | deviates: only `$HOME` (DEVIATIONS phase 1 #10). Kept | |

### 2.3 Rows, layout and enumeration (`lib/providers.zsh`, `lib/dsl.zsh`; spike `internal/rows/`, `internal/kinds/`)

| Behaviour | Status | Owner |
|---|---|---|
| The 4-field row `display TAB dir TAB preview TAB rel`, SGR colours, `-` for empty columns | done | |
| 0.3's fitted layout: per-list widths, caps, the name floor and 95% fit, clipping that keeps both ends of a name and the end of a scope, all-`-` columns dropped (`lib/providers.zsh:99`; `rows/layout.go`) | done | |
| 0.2's fixed layout behind `HOPX_LAYOUT=fixed` | spike-only, for the old reference | I deletes it |
| Env colours: prod red, staging yellow, dev and `playground` blue, other env magenta (`lib/providers.zsh:161`; `rows/rows.go:102`) | done, but `playground` is a Strava word | C moves the table to `[settings]` (3.6) |
| `git ls-files -z --cached`, `:(glob)` added to bare pathspecs, git failure reported (`lib/providers.zsh:230`; `gitls/gitls.go`) | done | |
| `hop_kind` shapes `--dirs`, `--files`, `--marker` and every option: `--depth`, `--under`, `--layout` (longest first, `name...`), `--trim`, `--name-template`, `--name-fn _hop_entity_name`, `--strip-ext`, `--exclude`, `--preview` (globs, zero-byte skip), `--preview-skip`, `--scope-literal`, `--default`, `--desc` | done, as TOML keys (`config/config.go:71`) | |
| Redeclaring a kind replaces it and keeps its menu position; `hop_preset` names | done; `presets` becomes `recipes` | C |
| No config at all loads every preset (`hop.zsh:36`) | done as 0.3.1 does it | C changes it to `dir`, `project`, `file` (3.1) |
| `--fn` kinds | deviates: `exec` plus `compat.zsh`, which needs zsh at runtime | C drops `compat.zsh`; `exec` stays (3.2) |
| The `helm` and `dir` builtins (`lib/providers.zsh:366`, `:417`; `kinds/builtins.go:79`, `:51`) | done | C replaces builtin helm with config (3.5) |
| `hop: unknown kind: k` | done (`kinds/engine.go`) | |
| A repo-root `.hoprc`, opt-in through `HOP_HOPRC=1` (`lib/providers.zsh:510`) | missing | C: dropped in 1.0, and `HOP_HOPRC=1` gets a one-line warning (3.7) |
| `-s` on a literal preview candidate, so a directory named `main.tf` previews | done, matching hop's bug | |

### 2.4 Workspaces and repos (`lib/workspaces.zsh`; spike `internal/workspace/`)

| Behaviour | Status | Owner |
|---|---|---|
| `name = path` and bare `path` lines, `#` comments, CRLF, `~` and `$VAR` expansion without eval, missing paths skipped, first name wins | done | |
| `HOP_WORKSPACES` (colon list) beats `HOP_WORKSPACES_FILE`, which beats the default guesses `~/src ~/code ~/projects ~/dev ~/work` | done | |
| Repos are git repos directly inside a workspace, a worktree's `.git` file included; `HOP_REPOS` overrides | done | |
| Workspace rows show the `~` path and `N repos`; repo rows preview the README | done (`kinds/builtins.go:128`, `:140`) | |
| `-x` tested with `access(2)` | deviates: mode bits (DEVIATIONS phase 1 #11). Kept | |

### 2.5 History (`lib/actions.zsh:57`, `hop.zsh:177`; spike `internal/mru/`)

| Behaviour | Status | Owner |
|---|---|---|
| Rank: rows whose dir is in history move up, by first-seen rank then input order | done (`mru/mru.go:41`) | |
| Remember: front of list, deduped, absolute and live dirs only, `HOP_HIST_MAX` (300) | done (`mru/mru.go:85`), written by temp file and rename instead of in place | |
| `HOP_HISTFILE` defaults to `~/.local/state/hop/history`, one dir per line | deviates: `HOPX_HISTFILE`, `~/.local/state/hopx/history` | R renames; Eric's ranking then carries over |
| cd, ctrl-o and ctrl-t remember; copy doesn't | done; ctrl-o and ctrl-t remember before running (DEVIATIONS B3 #6). Kept | |

### 2.6 Picker, non-modal parts (`lib/ui.zsh:423` `_hop_pick`; spike `pick/args.go:56`)

| Behaviour | Status | Owner |
|---|---|---|
| Matcher flags shared with the headless filter (`lib/ui.zsh:386`; `match.Flags`) | done | |
| `--accept-nth=2,3,4`, reverse layout, inline info, rounded border with the label, header first with a bottom border, `▸` pointer | done | |
| Prompt `hop ▸ ` with the modal layer off | deviates: `hopx ▸ ` | R |
| `--expect=ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y`, plus `ctrl-l` and `ctrl-h` where a level is there | partial: no ctrl-l or ctrl-h | A |
| Preview `{2} {3}`, the window spec, ctrl-/ and alt-p toggle, ctrl-r refresh, ctrl-g ignored, alt-B browse | done | |
| alt-enter always cds, and does nothing in the kind menu | done (`pick/session.go:61`) | |
| `HOP_FZF_HEIGHT` (unset 80%, empty fullscreen) with `--min-height=18`; `--freeze-left=1` from fzf 0.67.0 | done | |
| alt-a reloads with every kind, keeping `-c` and the history order | done | |
| `--select-1` only for an empty query and never for a kind word; ordered mode for a resolver pick | done | |
| The resolver's note above the legend | done | |
| Non-modal legend, three lines of 35 columns or less (`lib/ui.zsh:13`) | deviates: adds `M-k` lines (`pick/args.go:112`) | A |
| fzf exit 1 says `hop: no match for: q`; others say `hop: fzf exited with status N` | done | |
| Callbacks run as `hop __verb` through `--with-shell 'hop __sh'`, never `$SHELL` | new design, done (`pick/shim.go:65`) | |
| `/dev/tty` reopened when fds are pipes | done (`internal/tty`) | |
| Preview pane: header rel, directory listing capped at 200, `bat` else `head -400`, missing-target and unreadable lines (`bin/hop-preview:107`) | done (`pick/preview.go:54`) | |

### 2.7 Modal layer (`lib/ui.zsh:45-311`, `bin/hop-preview:27`, `bin/hop-guard`)

All missing in the spike, all A's.

| Behaviour | zsh ref |
|---|---|
| On by default; `HOP_VIM=0` or `--no-vim` turns it off, `--vim` forces it on | `lib/ui.zsh:59`, `hop.zsh:545` |
| Empty query starts in NORMAL (`--disabled`, prompt `> `); a CLI query starts in SEARCH (prompt `/ `, search enabled), and a resolver note stays in the header | `:297-310` |
| NORMAL owns every printable ASCII key plus ctrl-d and ctrl-u; unowned ones are `ignore`; `(` and `)` get their own unbind | `:46`, `:271` |
| NORMAL: j/k down/up, g/G first/last, ctrl-d/ctrl-u half page, each restoring the preview | `:223-228` |
| NORMAL verbs as `print(<key>)+accept`: o (ctrl-o), O (ctrl-t), e (alt-o), y (ctrl-y), Y (alt-y), b (ctrl-g browse), c (alt-enter, always cd, ignored in the menu) | `:229-236`, `:262` |
| NORMAL: p toggles the preview, q aborts, r reloads the current view, l drills in, h goes up, `/` to SEARCH, `?` the help overlay, `:` the kind menu; r, l, h and `:` are bound only where they work | `:237-247` |
| `/` unbinds the whole set, enables search, moves the cursor to the end, prompt `/ `, SEARCH header | `:163` |
| Esc: in the menu goes back to the view you came from; in SEARCH returns to NORMAL keeping the query; in NORMAL with a query clears it; in NORMAL with no query quits. A query matching nothing comes back as an empty NORMAL list and the second esc restores all rows (0.3.0) | `:180`, CHANGELOG 0.3.0 |
| Headers: `NORMAL  j/k move  g/G top/bot  / search  : view  ? help  enter cd  q quit` and the SEARCH line, re-flowed to three lines when wider than the pane (45% of `COLUMNS` from 120); `: view` only with a root; enter named by the mode, plus `c cd` or `M-enter cd` when Enter isn't cd | `:73` |
| `?` overlay in the preview pane, label ` keys `, closed by any nav key; lists only the live optional keys (r, :, l, h, M-a) and what Enter does | `:183`, `bin/hop-preview:27-105` |
| Escape guard: each alt-<char> hop doesn't own marks the time; o O e y Y b c l h q are refused within `HOP_GUARD_WINDOW` (0.15 s) of a mark, each refusal re-arms it, any malformed state fails open, `0` disables it; state lives in a mode-700 per-picker dir, stale ones reaped after a day | `:137-147`, `:257`, `:280`, `:514-531`, `bin/hop-guard` |
| The kind-count cache is not ported: counts are live (43 ms on Eric's repo) | DEVIATIONS B3 #4, kept |

### 2.8 Kind menu (`lib/ui.zsh:187-210`, `bin/hop-kinds`; spike `callbacks.go:89`, `pick/session.go:61`)

| Behaviour | Status | Owner |
|---|---|---|
| `:` in NORMAL opens it in place, clearing the query, prompt `: ` | deviates: alt-k in plain search | A: `:` in NORMAL, alt-k removed |
| Header `VIEW  enter switch  esc back  j/k move  / filter` | deviates: `KINDS ...` | A |
| One row per kind with targets here, count and description; zero-count kinds hidden | done, with live counts | |
| Enter switches to that kind, keeping `-c`; esc goes back to the view you came from | done | |
| c and alt-enter do nothing on a menu row | alt-enter done, c missing | A |

### 2.9 Levels (`hop.zsh:328-463`; spike `hop.go:310`, `:333`)

| Behaviour | Status | Owner |
|---|---|---|
| Workspace picker: Enter goes to the workspace; l or ctrl-l drills into its repos | Enter done, drill missing | A |
| Repo picker: Enter goes to the repo; h or ctrl-h goes up to the workspace picker | Enter done, up missing | A |
| Targets picker: h or ctrl-h goes up to the repo picker | missing | A |
| Repo picker: l or ctrl-l drills into that repo's targets without a cd | new: 0.3.1 has no drill below a repo, and Eric asked for workspace to repo to targets | A |
| From a fallback workspace pick, a query the repos answer more closely opens the repo picker | done | |
| Workspace and repo rows are folders, so open and reveal both mean `code -n` and the legend says open | done | |
| Browse on a workspace row also prints `hop: to go INTO a repo from a workspace, press l (NORMAL) or ctrl-l (SEARCH)` | missing | A |

### 2.10 Actions (`lib/actions.zsh`; spike `internal/act/verbs.go`)

| Behaviour | Status | Owner |
|---|---|---|
| Enter by mode: cd, open, reveal, cd+open, cd+reveal, for file and dir targets (README table "What Enter does") | done (`verbs.go:311`) | |
| alt-enter and NORMAL c always cd | done (alt-enter); c with A | A |
| ctrl-o: `code -r` a file, `code -n` a dir; ctrl-t: `code -n` the row's dir | done | |
| ctrl-y and alt-y copy dir and file: `HOP_CLIPBOARD`, then pbcopy, wl-copy, xclip, xsel, clip.exe; `hop: copied X`; failure messages | done (`verbs.go:215`) | |
| alt-o: `$VISUAL`, `$EDITOR`, `vi`, split on whitespace, given the real tty | done (`act/exec_unix.go:18`) | |
| ctrl-g/alt-B/b: `gh browse` from the repo root with a relative path; `refusing to guess a path` | done (`verbs.go:230`), drill hint missing (2.9) | A |
| Reveal: the preview file, else a top-level README, else the first file; `nothing to reveal at the top of REL; use -o to open it as a folder`, not a failure after a cd | done (`verbs.go:293`) | |
| VS Code usable: on PATH, a live `VSCODE_IPC_HOOK_CLI` socket, no SSH session without one, Linux with `DISPLAY` or `WAYLAND_DISPLAY` or WSL | deviates: on PATH only (DEVIATIONS B3 #7) | A |
| Fallback to the terminal editor with `hop: REASON; using the terminal editor instead`; with no tty, `hop: no terminal for an editor; target: X`; cd+open without code says `so this was a cd only` | done | |
| `HOP_CODE` word-split launcher | done | |
| A relative dir is `hop: not a target directory: X`; unknown key `hop: unhandled key: X` | done | |
| cd is plain `cd`, so zoxide and chpwd hooks fire | done in the init scripts | |

### 2.11 Doctor and debug log (`lib/doctor.zsh`)

All missing, all B's. Sections in order: install (HOP_HOME, version, loaded, entry point), config (HOP_CONFIG, HOP_WORKSPACES_FILE, HOP_HISTFILE readable or MISSING, HOP_DEFAULT_KINDS, HOP_VIM, HOP_ACTION, HOP_JUMP, HOP_CODE, VS Code reachable, HOP_HOPRC, HOP_REPOS, HOP_DEBUG, HOP_DEBUG_LOG), tools (zsh, fzf, git, gh, bat, code versions or NOT INSTALLED), terminal (TERM, COLUMNS, completions), where you are (PWD, git toplevel, workspace for PWD), workspaces, kinds with row counts and shape, keys people mix up, the last 15 debug lines. `$HOME` prints as `~`. `--doctor=short` withholds PWD, the toplevel, workspace and kind names and any customised path, and prints counts and a shape histogram instead.

`HOP_DEBUG=1` appends timestamped lines to `HOP_DEBUG_LOG` (default `~/.local/state/hop/debug.log`): `generate root= kinds=`, `resolve tier= rule= verdict= n= inj= q= target= ms=`, `pick label= rows= query= st=`, `dispatch key= dir= preview= rel=`. Logging never fails a call.

### 2.12 Upgrade (`lib/upgrade.zsh`)

Missing, B's. 0.3.1 moves a git checkout: bare `hop upgrade` fast-forwards `main` to the newest `vX.Y.Z` that origin still publishes, `hop upgrade X.Y.Z` pins detached at that tag, `--check` (also `--dry-run`, `-n`) reports installed against released and changes nothing. It refuses, changing nothing, when the checkout is dirty (untracked files aren't dirt), on another branch, detached off a release tag, without `origin`, not its own repo, diverged from the release, or holding an untracked file the release ships. Messages are prefixed `hop upgrade:`. 1.0 keeps all of this for a checkout and adds brew and `go install` installs (4.6).

### 2.13 Version (`hop.zsh:116-146`)

0.3.1 prints `hop X.Y.Z (describe)`, and `hop A loaded, B installed (describe): run 'exec zsh' to load it` when the shell runs an older hop than the one on disk. A binary is always the installed one, so the 1.0 analogue is the shell init: the init script carries the hash of the template it came from, and `-V` says when the shell's integration is older than the binary's (4.6). Missing, B's.

### 2.14 Completion (`completions/_hop`; spike `shell/shell.go:65`)

| Behaviour | Status | Owner |
|---|---|---|
| Every flag with its description | done | |
| `-k` completes kinds from the live config, comma-separated, excluding chosen ones | partial: kinds yes, comma lists and exclusion unchecked | B |
| Mutually exclusive flags drop out (`-o`/`-e`, `--action` with `--cd -o -e`, `--vim`/`--no-vim`) | missing | B |
| `--action=` completes the five modes; `--doctor=` completes `short` | partial | B |
| `/`, `-` and `upgrade` as targets; after `upgrade`, `--check` and `-h` | missing | B; local release tags aren't completed, since a binary has no checkout |

### 2.15 Environment

Every variable becomes a `[settings]` key too. Env beats the file, which inverts 0.3.1 (where a `typeset` in config.zsh beat the environment); Eric's config.zsh sets none, so his behaviour doesn't change.

| Variable | 1.0 | Owner |
|---|---|---|
| `HOP_CONFIG` | path of `config.toml`. A value ending in `.zsh` is zsh hop's, which 0.3.1 exports into every child; 1.0 ignores it for loading and uses it as `hop import`'s default source | C |
| `HOP_DEFAULT_KINDS`, `HOP_WORKSPACES_FILE`, `HOP_WORKSPACES`, `HOP_REPOS`, `HOP_ACTION`, `HOP_JUMP`, `HOP_CODE`, `HOP_HIST_MAX`, `HOP_CLIPBOARD`, `HOP_FZF_HEIGHT` | as 0.3.1 | done |
| `HOP_HISTFILE` | as 0.3.1 | R (rename from `HOPX_HISTFILE`) |
| `HOP_VIM`, `HOP_GUARD_WINDOW`, `HOP_FZF_MIN` | as 0.3.1 | A |
| `HOP_DEBUG`, `HOP_DEBUG_LOG` | as 0.3.1 | B |
| `HOP_HOPRC` | unsupported; `1` warns once | C |
| `HOP_HOME` | gone; nothing reads it | |
| `HOPX_*` | renamed `HOP_*`: `HOP_CMDFILE`, `HOP_SESSION` (internal) | R |

### 2.16 Install and distribution

0.3.1 installs as a zsh plugin (zinit, antidote, sheldon, oh-my-zsh through `hop.plugin.zsh`) or a manual clone. 1.0 replaces all of them with Homebrew, `go install` and release archives (B). The README and CHANGELOG say so plainly, since plugin-manager users lose their install path.

## 3. The agnostic design (C)

### 3.1 Zero-config defaults

Recipes are embedded TOML files. Three are core and six are opt-in:

| Recipe | Kinds | Default set | Notes |
|---|---|---|---|
| `dir` | `dir` | yes | builtin: the repo root plus every top-level tracked dir, skipping `target` and `tmp`, previews `README.md`, `README`, `CLAUDE.md`. `skip` and `preview` become settable on the kind |
| `project` | `project` | yes | new, 3.2 |
| `file` | `file` | no | every tracked file, as today |
| `terragrunt`, `terraform-modules`, `helm`, `serverless`, `puppet`, `backstage` | as named | as each recipe says | opt-in, rewritten generic (3.3) |

A config with neither a `recipes` key nor any `[[kind]]` gets `recipes = ["dir", "project", "file"]`. Once a config sets `recipes` or declares a kind, it gets exactly what it names, as 0.3.1 loads presets only into an empty registry.

`~/.config/hop/config.zsh` present with no `config.toml` prints one line, `hop: found config.zsh; run 'hop import -o ~/.config/hop/config.toml' to use it`, and runs on the zero-config defaults.

### 3.2 The project kind

```toml
[[kind]]
name = "project"
desc = "dirs holding a build manifest"
default = true
marker = ["package.json", "go.mod", "Cargo.toml", "pyproject.toml", "setup.py", "Gemfile",
          "pom.xml", "build.gradle", "build.gradle.kts", "composer.json", "mix.exs",
          "Package.swift", "CMakeLists.txt", "*.csproj", "Dockerfile", "Makefile"]
min_depth = 1
nested = false
exclude = ["**/node_modules/**", "**/vendor/**", "**/third_party/**", "**/testdata/**",
           "**/fixtures/**", "**/test/fixtures/**"]
preview = ["README.md", "README", "package.json", "go.mod", "Cargo.toml", "pyproject.toml",
           "setup.py", "Gemfile", "pom.xml", "build.gradle", "build.gradle.kts", "Makefile", "Dockerfile"]
```

- No layout, so a row's name is the dir's basename and its scope is the parent path: `packages/api` shows as `api` with scope `packages`.
- `min_depth = 1` drops the repo root, which `dir`'s `<root>` row already covers.
- `nested = false` drops a match inside another match, so `packages/web/examples/demo/package.json` doesn't become a second project under `packages/web`.
- This is the starting point, not the answer. C tunes it on the public repos in 4.7 and records the row counts and every rejected false positive in `testdata/public/README.md`. The bar: every row is a dir a person would `cd` to on purpose, and a repo with N services or packages shows roughly N rows, not N times the number of Makefiles. If Makefile or Dockerfile make it noisy, the first lever is dropping them from `marker`, the second a `weak` marker list that only counts where no stronger marker matched.

### 3.3 Recipes

- Top-level `recipes = ["terragrunt", "helm"]` loads those recipes in order, before the file's `[[kind]]` tables. It replaces the spike's `presets` key; there's no alias, because the only existing TOML is Eric's, which the importer regenerates.
- A `[[kind]]` with a recipe's kind name replaces it in place, keeping its menu position, and `extend = true` merges into it, as today.
- `hop --doctor` lists the available recipes and which are loaded. `hop -h` lists the registered kinds as today.
- The opt-in recipes become generic. They assume a tool's file names, never a directory convention:

| Recipe | 0.3.1 preset | 1.0 recipe |
|---|---|---|
| `terragrunt` (`tg`) | marker `terragrunt.hcl` under `terraform/`, layouts `scope,env,region,name...` and `scope,name...`, the three Strava `preview_skip` globs | marker `terragrunt.hcl` anywhere, `min_depth = 1` so a root `terragrunt.hcl` include isn't a unit, `exclude = ["**/.terragrunt-cache/**"]`, no layout, preview `terragrunt.hcl`, `main.tf`, `*.tf`, `README.md` |
| `terraform-modules` (`mod`) | dirs `terraform/modules`, depth 2, the Strava `preview_skip` globs | marker `["main.tf", "variables.tf"]`, `nested = false`, excluding dirs that hold `terragrunt.hcl`, preview `README.md`, `main.tf`, `*.tf` |
| `helm` | builtin probing `kubernetes/values`, `services`, `charts`, `kubernetes/charts`, `kubernetes/services`, `cluster-apps` | marker `Chart.yaml` anywhere, preview `Chart.yaml`, `values.yaml`, `README.md` |
| `serverless` | dirs `serverless` | marker `["serverless.yml", "serverless.yaml", "template.yaml", "samconfig.toml"]` |
| `puppet` | dirs `modules` | marker `manifests/init.pp` |
| `backstage` | files `backstage/*.yaml` | files `**/catalog-info.yaml`, `name_from = "yaml:metadata.name"` |

  The `mod` exclusion needs one more marker option, `unless = ["terragrunt.hcl"]`, if `exclude` can't express it; C adds it only if a test repo needs it. A marker that names a path (`manifests/init.pp`) puts the row on the dir that holds `manifests/`.
- Each recipe gets a fixture test and, where one exists, a public repo golden.

### 3.4 Kind-schema extensions

| Key | On | Meaning |
|---|---|---|
| `recipes` | top level | 3.3 |
| `marker` as a list | marker kinds | a dir holding any of these is one row; entries may be basename globs (`*.csproj`) or a relative path (`manifests/init.pp`) |
| `min_depth` | marker kinds | the matched dir must sit at least this many segments below `under` (or the root); default 0 |
| `nested` | marker kinds | `false` drops a match inside another match of the same source; default `true` |
| `[[kind.source]]` | any kind | a kind built from several shapes, each a table with its own `dirs`, `files` or `marker` and the per-shape options; rows come out source by source, in order. `name`, `desc` and `default` stay on the kind. A kind has either a top-level shape or sources, never both |
| `skip` | `builtin = "dir"` | top-level dirs that are never targets; default `["target", "tmp"]` |
| `env_colors` | `[settings]` | env word to colour class: `{ prod = ["prod"], staging = ["staging"], dev = ["dev"] }` by default; any other env is magenta |
| `builtin = "helm"` | | removed; config errors name the helm recipe and `hop import` |
| `exec` | any kind | kept: a command printing 4-field rows, run in the repo root. `compat.zsh` and zsh `--fn` support go |

Validation keeps the spike's rule that an unknown key is an error with its line, and adds: sources and a top-level shape together; `nested` or `min_depth` on a non-marker shape; an empty `marker` list.

### 3.5 helm as config

Eric's helm, written as sources, reproducing `_hop_provider_helm` (`lib/providers.zsh:366`) row for row:

```toml
[[kind]]
name = "helm"
desc = "helm charts, values and apps"
default = true

  [[kind.source]]
  dirs = ["kubernetes/values", "services", "charts"]
  preview = ["docs/playbooks.md", "Chart.yaml", "values.yaml", "charts/*/Chart.yaml", "*.y*ml", "README.md"]

  [[kind.source]]
  marker = "Chart.yaml"
  under = "kubernetes/charts"
  layout = ["name..."]
  scope = "kubernetes/charts"
  preview = ["Chart.yaml"]

  [[kind.source]]
  files = ["kubernetes/services/**/*.yaml"]
  under = "kubernetes/services"
  exclude = ["*/tests/*"]
  strip_ext = true
  layout = ["name..."]
  scope = "kubernetes/services"

  [[kind.source]]
  files = ["cluster-apps/charts/cluster-apps/templates/*.yaml"]
  under = "cluster-apps/charts/cluster-apps/templates"
  strip_ext = true
  scope = "cluster-apps"
```

Known gaps between the builtin and these sources, each a case the fixture must pin and `rows.sh` must show is absent from Eric's repo, or that gets a fix:

1. The builtin uses an empty `Chart.yaml` as the preview; the marker source falls back to the dir. Fix if it shows: a source option `preview_marker = true`.
2. A `Chart.yaml` directly in `kubernetes/charts/` is named `Chart.yaml` by the builtin and `kubernetes/charts` by the source.
3. The builtin keeps a tracked path that isn't a regular file (deleted locally, or a symlink to a dir) in `kubernetes/services` and `cluster-apps`; the files shape drops it.
4. `_hop_preview_helm` tests literal candidates with `-f && -s`, the shape's preview with `-s`, so a dir named `Chart.yaml` previews only through the source.

After this, `kinds/builtins.go` keeps `builtinDir` and loses `builtinHelm` and `previewHelm`.

### 3.6 Strava- and Eric-specific things to move out

From `git grep -niE 'strava|acct-|mesos|cluster-apps|playbook|playground|kubernetes/(values|services|charts)|provider_\*|variables_defaults|versions_override'` on a4c7f42:

| What | zsh | spike | Goes to |
|---|---|---|---|
| helm's families `kubernetes/values`, `services`, `charts`, `kubernetes/charts`, `kubernetes/services` with its `*/tests/*` skip, `cluster-apps/charts/cluster-apps/templates` | `lib/providers.zsh:366-414` | `kinds/builtins.go:79-125` | Eric's config (3.5) |
| helm's preview chain led by `docs/playbooks.md` | `lib/providers.zsh:312` | `kinds/builtins.go:32`, `kinds/compat.zsh:87` | Eric's config |
| `preview_skip = provider_*.tf, variables_defaults.tf, versions_override.tf` | `presets/terragrunt.zsh`, `presets/terraform-modules.zsh` | `config/presets/terragrunt.toml`, `terraform-modules.toml` | Eric's config |
| terragrunt's `under = terraform` and acct/env/region layouts | `presets/terragrunt.zsh` | `config/presets/terragrunt.toml` | Eric's config; the recipe goes generic |
| `terraform/modules` depth 2, `modules/`, `serverless/`, `backstage/` | `presets/*.zsh` | `config/presets/*.toml` | Eric's config; recipes go generic |
| All eight presets as the zero-config default | `hop.zsh:37` | `config/config.go:21` `PresetOrder`, `LoadAllPresets` | `dir`, `project`, `file` |
| `playground` as a dev colour | `lib/providers.zsh:161-162` | `rows/rows.go:102` | `[settings] env_colors` in Eric's config |
| Usage examples `hop vpc prod`, `hop terraform/x`, `-k tg,helm` | `hop.zsh:55-69` | | generic examples in B's usage text |
| README examples (`terraform/payments/...`, `kubernetes/values/web/`) | `README.md:15` | | generic examples in the new README |
| Default parity repo `~/strava/configuration`, and Eric's paths in tests | | `main_test.go:119`, `realrepo_test.go:22`, `pty_test.go:105`, `test/parity/*.sh` | `HOP_PARITY_REPO` required with no default; R2 moves every test that needs Eric's repo into `eric_test.go`, skipped unless it's set |
| Comments citing Strava paths | `lib/match.zsh` throughout | `resolve/resolve.go:738`, `resolve/elsewhere.go:29`, `resolve/report.go:14`, `config/config.go:427` | reworded with generic examples |

Kept, because they're generic: the env-word map (`prd`, `stg`, `devel`...), `CLAUDE.md` in the dir preview, `target` and `tmp` in the dir skip list, and the default workspace guesses.

Gate: the grep above, run over the tree minus `testdata/eric.toml`, `eric_test.go`, `docs/spike/`, `docs/V1-PLAN.md` and `CHANGELOG.md`, prints nothing.

### 3.7 Eric's import

`hop import [CONFIG.zsh] [-o OUT] [--force]` runs `share/import.zsh` under `zsh -f`, replays the declarations, writes TOML, and loads it back to check it. The source defaults to `HOP_CONFIG` when it ends in `.zsh`, else `~/.config/hop/config.zsh`. Output goes to stdout unless `-o` names a file, and an existing file is refused without `--force`. It needs zsh, which only Eric's one-time migration does.

The rules that make the output reproduce 0.3.1 exactly:

- `hop_preset X` inlines 0.3.1's own definition of X from `internal/importer/v031/presets.toml`, a frozen copy that recipe changes never touch. `helm` inlines the sources in 3.5 and `dir` inlines `builtin = "dir"`.
- A redeclared kind replaces the preset's in place and `extend` is resolved at import, so the output is a flat, ordered list of complete `[[kind]]` tables in `_HOP_ALL_KINDS` order, with `recipes = []`.
- `--name-fn _hop_entity_name` becomes `name_from = "yaml:metadata.name"`. Any other `--fn` or `--name-fn` is an error naming the kind.
- `typeset` settings in config.zsh go to `[settings]`. 0.3.1's colour table always goes in: `env_colors = { prod = ["prod"], staging = ["staging"], dev = ["dev", "playground"] }`.
- A `HOP_HOPRC` or `.hoprc` use is reported as unsupported.

For Eric's config.zsh that yields 11 kinds in this order: tg, mod, helm, serverless, puppet, backstage, dir, file, mesos, conf, rules, with tg, mod, helm, dir and mesos in the default set. `testdata/eric.toml` is regenerated with `hop import ~/.config/hop/config.zsh -o testdata/eric.toml --force` and checked in.

It reproduces today's behaviour when `test/parity/rows.sh` prints IDENTICAL for all 11 kinds, the default set, ws and repo; `resolve.sh` shows zero diffs under auto, unique and never; and `e2e.sh` agrees on all 6,132 queries, all against `~/.local/share/hop` with `~/.config/hop/config.zsh`.

`.hoprc` isn't carried over: it runs repo code, Eric doesn't use it, and a declarative `.hop.toml` is a post-1.0 idea.

## 4. Workstreams

### 4.0 Order

```
R1 restructure  ->  R2 seams  ->  A interactive  \
                                  B ops           >  integration  ->  retirement
                                  C agnostic     /
```

R1 and R2 are serial, done by one agent on `v1/restructure` and merged into `v1/go` before anyone forks. A, B and C then run in parallel on `v1/interactive`, `v1/ops` and `v1/agnostic`, each in `~/worktrees/hop/v1-<name>` branched from `origin/v1/go`.

### 4.1 R1: restructure

Move the spike to the root, update imports, `build.sh` and the parity harness paths, and nothing else that changes behaviour. Steps:

1. `git mv` everything in `spike/hopx/` to the repo root; merge `spike/hopx/.gitignore` (`dist/`) into the root `.gitignore` and add `bin/hop` there too (`bin/` itself still holds zsh's scripts until retirement, so the ignore is the file, not the dir). Move `spike/parity` to `test/parity`, `spike/shell/test` to `test/shell`, `spike/docker` to `test/docker`, `spike/docs` to `docs/spike`, and `spike/hopx/build.sh` to `scripts/build.sh`.
2. `go.mod` module `github.com/etknorr/hop`; rewrite every import from `github.com/etknorr/hop/spike/hopx/internal/...`.
3. Name the binary `hop`: `go build` output, `scripts/build.sh` names (`hop-<os>-<arch>`), the prompt `hop ▸ `, every `hopx:` message to `hop:`, every callback string (`hopx __preview` to `hop __preview`), the init scripts (`init/hop.zsh` and friends, function default `hop`), and `HOPX_*` env names to `HOP_*` (`HOP_CONFIG`, `HOP_HISTFILE` with the default `~/.local/state/hop/history`, `HOP_CMDFILE`, `HOP_SESSION`, `HOP_LAYOUT` for the test-only fixed layout, `HOP_BIN`). The parity knobs become `HOP_PARITY_HOME` (the oracle install), `HOP_PARITY_REPO`, `HOP_PARITY_ZSHCONFIG` (the oracle's config.zsh, the spike's `HOP_PARITY_CONFIG`) and `HOP_PARITY_CONFIG` (the Go side's TOML, the spike's `HOPX_PARITY_CONFIG`, default `testdata/eric.toml`). `--cmd NAME` still renames the function.
4. The zsh widget can't be named `hop-widget`, because zsh hop's is. Name it `<cmd>-widget`, and skip binding ^G and alt-g only when `${widgets[hop-widget]}` is zsh hop's (`user:_hop_widget`). The completion function is `_<cmd>_complete`, so it never replaces zsh hop's `_hop`.
5. Point the live-zsh tests at `testfix.RefHome("v0.3.1")` (unpacked from the tag), not the worktree's `hop.zsh`: the four failures in section 0, `match_test.go`'s read of `lib/ui.zsh`, and every `HopHome()` use. Resolve comparisons run zsh with `HOP_VIM=0`. This is what lets the tests survive deleting `hop.zsh`.
6. Parity harness: paths for the new layout; the oracle is `HOP_PARITY_HOME` and the repo `HOP_PARITY_REPO`, both required, with a usage line and exit 2 when unset, so no Eric path lives in the scripts. Each side gets its own env (`HOP_CONFIG` and `HOP_HISTFILE` mean different files to the two hops).
7. `TestMain` in every package that runs the binary or writes history sets `HOME`, `XDG_STATE_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` to a temp dir.

Gates:

- `go build ./... && go vet ./... && gofmt -l .` (empty) and `go test ./...` all pass at the root, the four failures included.
- `HOP_PARITY_HOME=~/.local/share/hop HOP_PARITY_REPO=~/strava/configuration HOP_PARITY_ZSHCONFIG=~/.config/hop/config.zsh test/parity/rows.sh`, then `resolve.sh` and `e2e.sh` the same way, with the default `testdata/eric.toml`: identical, as the spike recorded.
- `test/shell/run-all.sh` passes zsh, bash 5.3, `/bin/bash` 3.2 and fish (docker).
- `git grep -n 'spike/hopx\|hopx'` prints nothing outside `docs/spike/` and `CHANGELOG.md`.
- The history checksum is unchanged.

Commits, for example: `refactor: move the hopx module to the repo root`, `refactor: rename the hopx binary and env to hop`, `test: compare live-zsh tests against v0.3.1`, `test: require the parity oracle and repo by env`.

### 4.2 R2: seams

Small, behaviour-neutral changes that give A, B and C files of their own. Same agent, same branch, after R1.

1. Verb registry: `main.go` gets `register(name string, public bool, fn func(args []string, stdout, stderr io.Writer) int)`, and each `cmd_*.go` registers its verbs in `init()`. Public verbs take the first word only when nothing precedes it, as `upgrade` does in 0.3.1. Split `callbacks.go`, the command half of `main.go` and their tests into `cmd_picker.go` (`__rows`, `__menu`, `__key`, `__header`, `__preview`, `__sh`, `__resolve-dump`), `cmd_shell.go` (`init`, `__complete`) and `cmd_config.go` (`config`, `kinds`, `rows`, `config import`).
2. Shrink the first-word verbs to `init`, `import` and `upgrade` (the last registered by B). `rows` becomes `__dump-rows`, `kinds` becomes `__kinds`, `config check|path` becomes `__config check|path`, `config import` becomes `import`, and `help` becomes a query again, as in 0.3.1. `hop config`, `hop rows` and `hop kinds` are then queries; a dir named `config` is common. Update `test/parity/*.sh` to match.
3. API stubs, so each workstream compiles against the others from day one:
   - `internal/debuglog`: `Printf(format string, args ...any)`, a no-op until B fills it in.
   - `internal/version`: `String() string` returning the current constant.
   - `act.CodeUsable() (ok bool, reason string)`, exported, with today's body.
   - `config.Settings` gains `Debug`, `DebugLog`, `FzfMin`, `GuardWindow` and `EnvColors`, each parsed from env and `[settings]` and otherwise unused.
4. `README.md` becomes a skeleton with one section per owner, each between a heading and an `<!-- end: X -->` line so git merges the three without conflict: Install and shell setup (B), Using the picker (A), Configuring kinds (C), Upgrading, releases and the environment (B). The 0.3.1 README stays readable with `git show v0.3.1:README.md`.
5. A ledger per workstream, `docs/v1/ported-interactive.md`, `ported-ops.md` and `ported-agnostic.md`, each listing the `t '...'` case names from its suites (below), to fill in as Go test name or `n/a: reason`.
6. `.gitignore`: `testdata/repos/`.
7. Move every test gated on `HOP_PARITY_REPO` (`realrepo_test.go`, the Eric-repo cases in `main_test.go` and `pty_test.go`) into `eric_test.go`, so Eric's paths live in one file.

| Suites (cases) | Ledger |
|---|---|
| keymap (71), guard (15), pty (9), pty_escape (11), pty_filter (4), pty_reload (1), actions (39), clipboard (12), editor_path (8), nottty (31), fzf_version (24), match (93), core (51) | interactive |
| upgrade (50), completions (10), smoke (51), harness (4), runner (2) | ops |
| dsl (44), providers (78), layout (16), cache (2), workspaces (52), integration (35) | agnostic |

Gates: R1's gates again, plus `hop config` and `hop kinds` resolving as queries in a test. Push `v1/restructure`, then fast-forward `v1/go` to it (the integration owner does this).

### 4.3 Ownership

Strict: a workstream edits only its own paths. Anything else goes through the integration owner, and a needed change to a frozen package is reported, not made.

| Path | A interactive | B ops | C agnostic |
|---|---|---|---|
| `hop.go`, `cmd_picker.go`, `pty_test.go`, `hop_test.go`, `eric_test.go` | owns | | |
| `internal/pick`, `keymap` (new), `guard` (new), `act`, `resolve`, `match`, `mru`, `ptytest` | owns | | |
| `test/parity/` | owns edits | runs | runs |
| `docs/SMOKE.md`, README "Using the picker", `docs/v1/ported-interactive.md` | owns | | |
| `main.go`, `main_test.go`, `cmd_shell.go` | | owns | |
| `internal/shell`, `debuglog`, `doctor` (new), `upgrade` (new), `version` | | owns | |
| `test/shell/`, `test/docker/`, `scripts/build.sh`, `.github/`, `.goreleaser.yaml`, `Formula/` | | owns | |
| `docs/RELEASING.md`, README "Install and shell setup" and "Upgrading, releases and the environment", `docs/v1/ported-ops.md` | | owns | |
| `cmd_config.go` | | | owns |
| `internal/config`, `kinds`, `importer`, `rows`, `gitls` | | | owns |
| `testdata/` (all of it), `config.example.toml`, `workspaces.example` | | | owns |
| README "Configuring kinds", `docs/v1/ported-agnostic.md` | | | owns |
| `internal/collate`, `tty`, `testfix`, `workspace`, `go.mod`, `go.sum` | frozen | frozen | frozen |
| `CHANGELOG.md`, `VERSION`, zsh files, `tests/` | integration only | | |

Tests that need a fixture from `testdata/` read it; only C changes it. A or B needing a new golden puts it under `testdata/golden/interactive/` or `testdata/golden/ops/`, which C leaves alone.

### 4.4 Interfaces between workstreams

| Interface | Provider | Consumers | Contract |
|---|---|---|---|
| `config.Load(path) (*Config, error)`, `config.Path()`, `cfg.Kinds`, `cfg.DefaultKinds()`, `cfg.AllKinds()`, `cfg.Settings`, `config.Recipes() []string` | C | A, B | signatures frozen after R2; C may add fields, never remove or rename |
| `kinds.Generate(cfg, root, names, stderr) []rows.Row`, `kinds.New(root, stderr).Emit(k)`, `kinds.WorkspaceRows`, `kinds.RepoRows` | C | A, B (doctor counts) | frozen; rows come out in kind order, then source order, unranked |
| `rows.List`, `rows.Row` | C | A | frozen |
| `act.CodeUsable() (bool, string)` | A | B (doctor) | the same check every code verb runs, so doctor can't disagree |
| `debuglog.Printf` | B | A (generate, resolve, pick, dispatch lines in 2.11) | never fails, no-op unless `Settings.Debug` |
| `version.String()`, `version.InitHash()` | B | A (none yet), B | |
| Shell to binary | B (init) | A (picker) | `HOP_CMDFILE` set per call; the binary writes one absolute path there with `O_EXCL`, mode 0600, no newline; the function `cd`s with plain `cd`; exit 0 success or cancel, 1 nothing chosen or matched, 2 usage. `hop -` never reaches the binary; `hopr` is `hop /`; `hopw` calls `hop __hopw`. The function exports `HOP_SHELL=<shell>` and `HOP_INIT_HASH=<hash>` for that call |
| Callbacks | A | | every fzf callback is `hop __<verb>` through `--with-shell '<abs hop> __sh'`; state is the session JSON named by `HOP_SESSION` |
| `hop __complete <words...>` | B | shells | one candidate per line, `word TAB description` |
| Public verbs | B registers `init`, `upgrade`; C registers `import` | | first word only, nothing before it; `hop -- init` searches |

### 4.5 A: interactive

Scope: the modal layer, levels, the kind menu on `:`, the `?` overlay, the escape guard, the rest of the A rows in section 2, and pty tests on fzf 0.60.3 and the latest.

Design:

- `internal/keymap` builds the modal binds from session state: the key table in 2.7, the headers, and the transforms. Every decision a bind can't make goes through `hop __key <key> [arg]`, which reads `FZF_PROMPT`, `FZF_QUERY` and `FZF_PREVIEW_LABEL`, so no POSIX `case` body runs under fish. Esc's four meanings, enter in the menu, `?`, c and alt-enter in the menu all go there.
- Letter verbs ride `print(<key>)+accept`, never `--expect`, because an `--expect` key stays live after `unbind`.
- `hop __keys` renders the `?` overlay (`bin/hop-preview --keys`), live keys and Enter mode from the session.
- `internal/guard`: `hop __guard mark` and `hop __guard check <action>`, state in the session dir. Port `bin/hop-guard`'s fail-open rules, re-arm and `HOP_GUARD_WINDOW` exactly. Measure the Go fork cost on an idle machine and at load, and record it in `docs/v1/ported-interactive.md`, since the 0.15 s window was sized for zsh's 15 to 22 ms fork.
- Levels run in-process in `hop.go`: a stack of {level, scope}. l/ctrl-l pushes (workspace to its repos, repo to its targets), h/ctrl-h pops, or from the top builds the level above (targets to all repos, repos to workspaces). Each level opens with an empty query. l and h are bound, in the legend and in the overlay only where that move exists. A repo opened by drilling isn't `cd`'d into; the final Enter decides.
- T4 hint reads the vim setting. Esc out returns 0. The four-line fzf floor message and `HOP_FZF_MIN`. `act.CodeUsable` gets the IPC socket, SSH, DISPLAY and WSL checks. `hop __hopw`.
- `docs/SMOKE.md`: the manual checks that need eyes (header wrapping at 80 columns, clipping, the overlay's width), rewritten from `SMOKE.md`.

Tests:

- Argv goldens for NORMAL start, SEARCH start, `HOP_VIM=0`, a workspace level, a repo level and a targets level, and every argv parses under fzf 0.60.3 and 0.67.0 (`fzf <argv> --filter x </dev/null` exits 0).
- pty tests through `internal/ptytest`, fullscreen (`HOP_FZF_HEIGHT=`), each run against `bin0603/fzf`, `bin0670/fzf` and the host's 0.73.1: j j k moves; `/` then `vpc` filters; esc keeps the query and j/k walk the filtered rows; esc esc restores all rows, including from a zero-match query; esc on an empty query exits 0; `:` opens the menu with the query cleared, enter switches with `-c` kept, esc goes back; `?` opens and j closes the overlay; o, O, e, y, Y, b and c with stub `code`, `gh`, editor and clipboard on PATH; l and h across workspace, repo and targets on a fixture with two workspaces; a forged `\e]11;rgb:...\e\\` burst followed by `b` doesn't run the stub `gh`, while `j j b` at 60 ms spacing does; `HOP_VIM=0` shows the plain legend and alt-a reloads.
- Every case in `docs/v1/ported-interactive.md` is a Go test or says why not.

Gates: `go vet`, `go test ./...` with the pty tests passing on all three fzf versions; `resolve.sh` and `e2e.sh` identical with the modal layer on and with `HOP_VIM=0` (A adds the `PARITY_VIM` loop to the harness); `rows.sh` identical; `test/shell/run-all.sh` still passes; history checksum unchanged.

### 4.6 B: ops

Scope: `--doctor`, upgrade, version, `-h`, init scripts and completion, release workflow and formula, CI, `docs/RELEASING.md` and the README install sections.

Design:

- Init: `hop init zsh|bash|fish [--cmd NAME]` prints the function, `-` as `cd -`, the widget, completion, and, only when NAME is `hop`, `hopr` and `hopw`. Keep every trap the spike's scripts carry (zsh `command hop`, `push-input`, `compdef` only after compinit; bash 4+ `bind -x` save and restore; bash 3.2's kill-ring macro and empty-word fix; fish `string collect`, plain `cd`, `commandline -f repaint`). Delete `init/hopx.ps1`, `test/docker/Dockerfile.pwsh`, `pwsh.sha256` and the pwsh shell tests: PowerShell isn't a 1.0 shell, and an untested init is worse than none. The Windows build and `exec_windows.go` stay for `scripts/build.sh`.
- Version: `version.String()` is the goreleaser `-X` value, else `debug.ReadBuildInfo().Main.Version` (`go install`), else `devel` plus `vcs.revision` and a dirty mark (a checkout build). `-V` prints `hop 1.0.0`, adds `(abc1234, dirty)` for a checkout build, and when `HOP_INIT_HASH` differs from the binary's template hash adds `hop: your shell integration predates this hop: run 'exec $SHELL' to reload it`. `-h` is `_hop_usage` reworded for the binary, with generic examples and `declare your own in <config path>`.
- Doctor: 2.11, plus install method (brew, go install, checkout, unknown) and binary path, the shell and its init staleness from `HOP_SHELL` and `HOP_INIT_HASH`, recipes available and loaded, each setting with its source (env, file or default), and the config.zsh-without-toml hint. Same `--doctor=short` rules.
- Upgrade, by install method:
  - brew (the executable resolves under `$(brew --prefix)/Cellar/hop/`): `hop upgrade` runs `brew upgrade etknorr/hop/hop`; a version argument is refused, naming `go install github.com/etknorr/hop@vX.Y.Z`.
  - go install (build info names module `github.com/etknorr/hop` with a semver): runs `go install github.com/etknorr/hop@<vX.Y.Z or latest>`, and warns when `go env GOBIN` (or `GOPATH/bin`) isn't the running binary's dir.
  - checkout (the executable sits in a git work tree whose `go.mod` is this module): every 0.3.1 rule in 2.12, then `go build -o <the executable> .`.
  - unknown: prints what it found and the three install commands.
  - `--check` for all of them: installed version against the newest strict `vX.Y.Z` from `git ls-remote --tags --refs https://github.com/etknorr/hop`, so it needs no API token.
- Release: `.goreleaser.yaml` builds darwin and linux on amd64 and arm64 with `CGO_ENABLED=0 -trimpath -ldflags '-s -w -X .../internal/version.Version={{.Version}}'`, archives, checksums, and the release body from the matching CHANGELOG section. `release.yml` runs on `v*` tags, fails unless the tag is `v$(cat VERSION)`, and runs goreleaser through its pinned action.
- Formula: `Formula/hop.rb` builds from source (`url "https://github.com/etknorr/hop.git", tag: "vX.Y.Z"`, `depends_on "go" => :build`, `depends_on "fzf"`, `head ... branch: "main"`), so it works on macOS and Linux, needs no bottles and needs no goreleaser Homebrew support. The release commit bumps its tag line with VERSION. Install: `brew tap etknorr/hop https://github.com/etknorr/hop` then `brew install etknorr/hop/hop`.
- CI (`ci.yml`, keeping the zsh jobs until retirement): `push` on `main` and `v1/**`, `pull_request` and `workflow_dispatch`. Jobs: test on macos-latest and ubuntu-latest (setup-go from `go.mod`, latest fzf, zsh, `actions/checkout` with `fetch-depth: 0` for the `v0.3.1` tag, then vet, gofmt and `go test ./...`); floor on ubuntu with fzf 0.60.3 and 0.67.0, checksum-verified as today, running the pty and argv tests; shells on ubuntu (zsh, bash 5, fish from apt) and macOS (zsh, `/bin/bash` 3.2, brew bash 5) running `test/shell/run-all.sh` with `NO_DOCKER=1` and host fish; cross running `scripts/build.sh` for all six targets; formula running `brew style` and `brew install --HEAD --build-from-source ./Formula/hop.rb` on macOS.
- `docs/RELEASING.md`: the same steps, with the formula tag bump added and the manual `gh release create` replaced by the release workflow.

Tests: `bash -n`, `/bin/bash -n`, `zsh -n` and `fish -n` on every init output; `run-all.sh` green on four shells; doctor goldens for full and short with a fake `HOME`; upgrade against a local bare-repo origin for every checkout refusal and move from `suite_upgrade.zsh`, and with stub `brew` and `go` on PATH for the other two methods; completion cases for comma lists, exclusions and `upgrade`; `-V` with and without a stale `HOP_INIT_HASH`; `go run github.com/goreleaser/goreleaser/v2@<pinned> release --snapshot --clean` produces four archives.

Gates: the above, plus a green CI run of `ci.yml` on the pushed `v1/ops` branch, linked from the branch report.

### 4.7 C: agnostic

Scope: section 3 in full, plus `config.example.toml` and the README "Configuring kinds" section.

Design: as in section 3. The config package gains `recipes`, the schema extensions in 3.4 and the zero-config rule in 3.1; kinds gains sources, marker lists, `min_depth`, `nested` and `skip`, and loses builtin helm and `compat.zsh`; rows reads `env_colors`; the importer works as in 3.7. The settings warnings get 0.3.1's wording.

Public test repos, pinned by commit in `testdata/repos.lock` and shallow-fetched by `testdata/fetch-repos.sh` into the gitignored `testdata/repos/` (`git fetch --depth 1 origin <sha>`):

| Repo | Exercises |
|---|---|
| `GoogleCloudPlatform/microservices-demo` | `project` across Go, Node, Python, Java and C# services, Dockerfiles everywhere |
| `gruntwork-io/terragrunt-infrastructure-live-example` | `terragrunt` without a `terraform/` root |
| `prometheus-community/helm-charts` | `helm` on `charts/*/Chart.yaml` |

Each gets goldens under `testdata/public/` for the zero-config set and its recipe. Tests skip when the repos aren't fetched; CI fetches them.

README "Configuring kinds" leads with the zero-config defaults and `project`, then recipes, then writing a kind (the three shapes, options, layouts, sources), with generic examples only.

Tests: config validation for every new key and error; recipe fixtures; the declarative helm against the builtin on a fixture holding all four families and the gap cases in 3.5, before the builtin is deleted; importer round trips on `config.example.zsh`, a fixture covering every option, and Eric's config; zero-config with and without a config.zsh beside it; `HOP_CONFIG` ending in `.zsh`; the ported-agnostic ledger.

Gates: `go vet`, `go test ./...`; `rows.sh` IDENTICAL for all 14 lists with the regenerated `eric.toml`, then `resolve.sh` and `e2e.sh` identical; the public-repo goldens reviewed and their counts recorded; the 3.6 grep prints nothing; history checksum unchanged.

## 5. Integration and retirement

The integration owner works in `~/worktrees/hop/go-1.0` on `v1/go`.

1. Merge C first, because it changes the config every parity run reads: `git merge --no-ff origin/v1/agnostic`. Re-run R1's gates.
2. Merge A next. A's parity runs used the old `eric.toml`, so re-run `resolve.sh` and `e2e.sh` (vim on and off) and the pty tests on all three fzf versions with C's config.
3. Merge B last, since its CI tests everything the others built. Push `v1/go` and wait for a green CI run.
4. Final parity run with the imported config: regenerate `testdata/eric.toml` with the merged binary's `hop import`, confirm it's byte-identical to C's, then `rows.sh`, `resolve.sh` under auto, unique and never, and `e2e.sh` under all three, against `HOP_PARITY_HOME=~/.local/share/hop` (0.3.1), `HOP_PARITY_REPO=~/strava/configuration` and `HOP_PARITY_ZSHCONFIG=~/.config/hop/config.zsh`. Zero diffs. Also `perf.sh`, checked against FINDINGS' medians: no measure more than 20% slower.
5. Retirement, on `v1/retire` from `v1/go`, then merged back:
   - delete `hop.zsh`, `hop.plugin.zsh`, `lib/`, `bin/` (zsh's scripts), `presets/`, `completions/`, `tests/`, `config.example.zsh`, `SMOKE.md`, `docs/spike/`, the three `docs/v1/ported-*.md` ledgers once every row is filled in, the 0.2 fixed layout and `HOP_LAYOUT`, and the zsh jobs in `ci.yml`;
   - rewrite `CONTRIBUTING.md` and the issue templates for Go;
   - re-run the full gate set: `go test ./...` (the `RefHome` tests still work, because they read the `v0.3.1` tag), the parity harness against the external oracle, `run-all.sh`, CI;
   - CHANGELOG: under `## [Unreleased]`, the 1.0.0 notes: Changed (hop is a Go binary; config is TOML; env beats the config file), Added (bash and fish, `project`, recipes, `[[kind.source]]`, `hop import`, Homebrew and `go install`, drilling from a repo into its targets), Removed (the zsh plugin and plugin-manager installs, `hop_kind`, `--fn`, `.hoprc`, the kind-count cache), and migration steps;
   - VERSION stays 0.3.1 here. Eric's release commit bumps it to 1.0.0 with the formula tag line and moves the CHANGELOG section, per `docs/RELEASING.md`, and `release.yml` refuses a tag that doesn't match it.
6. Hand off to Eric: `v1/go` ready to merge to `main`. Merging, tagging and releasing are his.

## 6. Eric's switch procedure

Done by Eric after the release, not by agents.

1. Install:
   ```zsh
   brew tap etknorr/hop https://github.com/etknorr/hop
   brew install etknorr/hop/hop
   ```
   or `go install github.com/etknorr/hop@v1.0.0`. In a shell with zsh hop loaded, the `hop` function shadows the binary, so use `command hop` until step 5.
2. Check it: `command hop -V` and `command hop --doctor`.
3. Import, which leaves config.zsh alone:
   ```zsh
   command hop import -o ~/.config/hop/config.toml
   command hop --doctor | sed -n '/^kinds/,/^$/p'
   ```
   The kinds section should list the 11 kinds, with tg, mod, helm, dir and mesos starred.
4. Try it first, with no `~/.zshrc` change, in the current shell next to zsh hop:
   ```zsh
   eval "$(command hop init zsh --cmd hop1)"
   ```
   That defines `hop1` and `hop1-widget` and leaves `hop`, `hopr`, `hopw` and ^G on zsh hop. Try `hop1`, `hop1 vpc prod`, `hop1 -w`, and bind the widget by hand if you want it: `bindkey '^[G' hop1-widget`. Both read and write `~/.local/state/hop/history`, so ranking is shared.
5. Switch: in `~/.zshrc`, replace the hop block at lines 202 to 206 (it's already after compinit, which completion needs) with:
   ```zsh
   if (( $+commands[hop] )); then
   	eval "$(hop init zsh)"
   else
   	print -ru2 -- 'hop: brew install etknorr/hop/hop'
   fi
   ```
   The one line that matters is `source ~/.local/share/hop/hop.zsh` becoming `eval "$(hop init zsh)"`. Then `exec zsh` and check `hop -V`.
6. Rolling back is restoring that block. `~/.local/share/hop`, `config.zsh`, the workspaces file and the history are all untouched and still work with 0.3.1. Keep `~/.local/share/hop` until you're done comparing, since it's the parity oracle.

## 7. Risks and acceptance gates

### Risks

| Risk | Mitigation | Owner |
|---|---|---|
| zsh hop exports `HOP_CONFIG` (pointing at config.zsh) into every child, so a Go `hop` run from Eric's shell would read the wrong file | a `.zsh` value is never loaded as TOML (2.15) | C |
| The binary's default history is Eric's real file | temp `HOP_HISTFILE` everywhere, `TestMain` isolation, checksum gate | R, all |
| Widget and completion names collide with zsh hop's in try-it mode | `<cmd>-widget`, `_<cmd>_complete`, zsh hop's widget detected by its function name | R, B |
| First-word verbs steal real queries (`hop config`) | only `init`, `import`, `upgrade` are verbs; `hop -- init` searches | R2 |
| fzf behaviour moves between 0.60.3 and the latest (`--filter` with `--accept-nth`, `--freeze-left`, bind parsing) | argv parse tests and pty tests on all three versions locally, floor job in CI | A, B |
| The modal layer forks `hop __key` per esc, enter and guarded verb | measure keypress-to-redraw on Eric's repo against zsh hop and record it; the guard window may need retuning | A |
| The declarative helm differs from the builtin on edge cases | the four gaps in 3.5 pinned in fixtures, `rows.sh` IDENTICAL on Eric's repo before the builtin goes | C |
| A tuned `project` kind is still noisy on some repo shapes | measured on three public repos; Makefile and Dockerfile are the first to drop | C |
| Homebrew support in goreleaser has changed (formulas deprecated for casks, casks macOS-only) | a source-building formula kept in this repo, independent of goreleaser | B |
| `go install` needs Go 1.26, the `go.mod` directive | documented in the README install section; brew needs no Go on the user's side beyond the build dependency it installs | B |
| Parity needs Eric's machine (the oracle and his repo), so CI can't run it | CI runs fixture-level live-zsh tests through `RefHome` and every golden; the harness runs at each merge in section 5 | A, I |
| Three branches still collide in shared files | the ownership table, R2's registry and README regions, no new dependencies; collisions go to the integration owner | all |
| Settings precedence flips (env beats file) | in the CHANGELOG; Eric's config sets nothing | C |
| Esc's exit status changes from the spike's 130 to 0 for parity, so a script can't tell cancel from success | as in 0.3.1; documented | A |
| Plugin-manager users lose their install path | CHANGELOG and README migration notes | B, I |
| Windows still never runs | out of scope; the cross-compile in CI only proves it builds | B |

### Acceptance gates

Every gate is a real run, with its output summarised in the branch report. Common to all: `go vet ./...` clean, `gofmt -l .` empty, `go test ./...` green, the history checksum unchanged, and no write outside the worktree.

| Step | Gates |
|---|---|
| R1, R2 | the four failing tests fixed; `rows.sh`, `resolve.sh` (3 modes) and `e2e.sh` identical to the spike's results; `run-all.sh` green on zsh, bash 5, bash 3.2 and fish; no `hopx` or `spike/hopx` left; `hop config` is a query |
| A | pty suite green on fzf 0.60.3, 0.67.0 and 0.73.1; argv parses on 0.60.3 and 0.67.0; `resolve.sh` and `e2e.sh` identical with the modal layer on and off; `rows.sh` identical; the interactive ledger complete |
| B | init parses in four shells; `run-all.sh` green; doctor, upgrade, completion and `-V` tests green; goreleaser snapshot builds four archives; a green CI run on `v1/ops`; the ops ledger complete |
| C | `rows.sh` IDENTICAL on all 14 lists with the regenerated `eric.toml`, then `resolve.sh` and `e2e.sh` identical; declarative helm equals builtin helm on the fixture; public-repo goldens reviewed with counts recorded; the 3.6 grep empty; the agnostic ledger complete |
| Integration | every workstream gate re-run after each merge; the final parity run in section 5 with zero diffs; `perf.sh` within 20% of FINDINGS; CI green on `v1/go` before and after retirement |
