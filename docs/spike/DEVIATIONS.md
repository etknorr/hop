# Deviations from SPEC.md

Each entry names the phase, what the spec says, what the build does, and why.

## Phase 1

1. **Preset location**: the spec's layout puts presets at `hopx/presets/*.toml`. They're at `hopx/internal/config/presets/*.toml`, because `//go:embed` can't reach a parent directory of the package that embeds them.
2. **Shared zsh files**: `import.zsh` is at `internal/importer/share/import.zsh`, and `compat.zsh` is at `internal/kinds/compat.zsh`, since the exec provider is what materialises it at runtime.
3. **Extra packages**: `internal/workspace` (the workspaces parser and repo discovery), `internal/collate` (zsh's sort order) and `internal/testfix` (the fixture repo builder) aren't in the spec's layout. The first is singular because the repo's `.gitignore` ignores any path named `workspaces`, and changing `.gitignore` is out of bounds for the spike.
4. **Row commands**: the spec names `hopx rows [-k kinds] [--root DIR] [--all]`. That exists, plus the hidden `hopx __rows <root> <kind...>` the phase task asked for, which is the form an fzf reload will call. `hopx rows -w` and `hopx rows -R` print workspace and repo rows until the phase 3 pickers exist.
5. **A literal preview candidate that is a directory**: the spec lists this as deliberately not matched. hopx matches it, using `-s` semantics as `_hop_dsl_preview` does, because the fixture showed the difference and byte parity is the gate. It's listed under "Found in hop" in `RESULTS.md`.
6. **Locale-dependent sort order and equal-width layout ties**: the spec lists both as deliberately not matched. hopx matches them through `internal/collate`, an approximation of macOS's en_US.UTF-8 collation, because Eric's repo rows came out in a different order without it (`identifiers` and `iPhone`). Layout ties use zsh's reverse `(O)` sort of the zero-padded key. Under `LANG=C`, zsh sorts bytewise and hopx still collates, so the two can differ there.
7. **Unknown keys are errors**: the prototype warned on an unknown top-level key or setting. hopx rejects every unknown key, at top level, in `[settings]` and in `[[kind]]`, with its line.
8. **`repo` isn't a builtin kind**: hop keeps the repo and ws providers out of `_HOP_ALL_KINDS`, so hopx does too, and the only builtins a `[[kind]]` can name are `dir` and `helm`.
9. **Pathspec magic**: `gitls` matches `:(glob)` and bare pathspecs in memory. Any other magic (`:(icase)`, `:(exclude)`) is an error rather than a second `git ls-files` call. No preset or Eric's config uses one.
10. **Named directories**: `_hop_rel` uses zsh's `${(D)p}`, which also abbreviates `hash -d` names. hopx only abbreviates `$HOME`. The parity harness runs `zsh -f`, where they agree.
11. **`-x` on a workspace**: `_hop_ws_parse` tests `-x`, which is `access(2)`. hopx checks the mode's execute bits, so an ACL or a root-owned dir can disagree.

## Phase 2

1. **hopx speaks as `hop:`** in resolver notes and the headless report, so a report diffs byte for byte against zsh hop's. Messages that only hopx has (the cmdfile, an fzf failure, the missing picker) say `hopx:`.
2. **Subcommands own the first word**: `rows`, `kinds`, `config`, `help` and the hidden `__*` verbs. Any other first word is hop's command line, so a target literally named `rows` needs `hopx -- rows`.
3. **No picker yet**: with a terminal, a non-jump prints one `hopx: the picker arrives in phase 3` line, then the headless report. Without one, the output is hop's exactly.
4. **Actions other than cd**: `-o`, `-e` and `--action=` parse and reach the resolver, where J1b reads them, but a jump under them exits 2 naming the target. Open and reveal are phase 3.
5. **`hopx -`** exits 2, because it is the shell function's own `cd -` (phase 4). `hopx /` works.
6. **Settings warnings keep the config's wording**: an invalid `HOP_JUMP` warns as `hopx: warning: jump "x" is not one of auto, unique, never; using auto`, where hop says `hop: HOP_JUMP=x is not one of ...`. Same fallback, different words.
7. **The fzf floor is one line**: hop prints four lines when fzf is too old; hopx prints one naming the version and the floor.
8. **`~name/x` in T0** reads the passwd entry, which is zsh's `userdirs`. `hash -d` named dirs aren't modelled, as in phase 1 (#10).
9. **History is written by temp file and rename**, as the spec asks. hop rewrites the file in place, so a reader racing a write can see it truncated.
10. **Orchestration lives in `hop.go`**, a second file in package main holding `hop()`'s flow (T0, levels, enumerate, rank, resolve, jump or report), so `main.go` stays dispatch. `internal/act` has only the cd half of `_hop_act_cd` so far.
11. **`_hop_repos`' status 2** ("no readable repos in $HOP_REPOS") isn't modelled. Both "none configured" and "none readable" give hop's status-1 message.
12. **`__resolve-dump` has two extra flags**: `--full` prints the whole line `testdata/resolve_runner.zsh` prints, so parity compares every column, and `--stats` reports fzf forks and time per query. Without them it prints the spec's six columns.
13. **`resolve.sh` runs three extra stress sets** (corpus, typo, relaxed) after the spec's five. The go/no-go exit status reads only the five.

## Phase B3 (spec phases 3 and 4: picker, actions, shell init)

1. **Kind menu key**: alt-k. hop's `:` lives in the NORMAL mode of the modal layer, which the spec leaves out, so in plain fzf search `:` would just type. With the menu bound, enter, esc and alt-enter ask `hopx __key` whether the list holds kinds or targets. The menu clears the query when it opens and when it closes, since the query typed there filtered kinds.
2. **Prompt**: `hopx ▸ `, so a hopx picker can't be mistaken for hop's. The legend's last line names alt-a and alt-k.
3. **Cancel status**: 130, as the spec's cd protocol says. hop returns 0 on esc.
4. **Menu counts**: live. hop caches them per HEAD and index and warms the cache in the background, because a zsh sweep takes about 1.6 s. hopx counts all 11 of Eric's kinds from one listing in 43 ms, so there is no cache.
5. **Two `__rows` forms**: with an absolute root as the first word it is phase 1's unranked enumeration, which the parity harness compares. Inside a picker, `__rows [kind...]` reads root and `-c` dir from the session and ranks by history, as `_hop_rows` does for a reload.
6. **Remember order**: ctrl-o and ctrl-t remember before they run. hop remembers after `_hop_act_open` succeeds, but hopx may exec the editor (the no-code fallback) and never come back.
7. **VS Code check**: `_hop_code_usable` is "on PATH or not", as the spec allows. The VSCODE_IPC_HOOK_CLI, SSH and DISPLAY checks aren't ported.
8. **No drill or up pickers** (ctrl-l, ctrl-h), as the spec says, so the workspace picker has no ctrl-l into a workspace's repos.
9. **Init script location**: `internal/shell/init/`, not `spike/shell/`, because `//go:embed` can't reach a parent directory. `spike/shell/test/` holds the shell tests.
10. **zsh ^G when hop is loaded**: if `hop-widget` exists, `hopx init zsh` defines `hopx-widget` but binds no key, so the two coexist in Eric's shell. Bind it by hand to try it there.
11. **zsh completion**: `compadd -d`, not `_describe`, which offered nothing for `--wor` because it won't complete option-shaped words outside `_arguments`.
12. **pwsh cd failure**: a failed `Set-Location` returns 1 instead of throwing. The prototype's `-ErrorAction Stop` ended the caller's whole script on the backslash case.
13. **`init` subcommand**: it takes the first word, like `rows` and `config`, so a target named `init` needs `hopx -- init`.
14. **Editor split**: on whitespace, as hop's `${=REPLY}` is. The prototype's quote-aware split isn't kept.
15. **fish completion**: goes through a function, since an empty `(commandline -ct)` substitutes to no argument at all. The binary then saw `-k` as the current word and offered flags instead of kinds.
16. **Docker images**: built from release tarballs on ubuntu:24.04, because `mcr.microsoft.com/powershell` pulls a 32-bit arm image on this host. Both images verify fzf 0.73.1 and pwsh 7.5.3 against checksums pinned in `spike/docker/*.sha256`.
17. **G6 in docker**: the Go pty test, cross-compiled with `go test -c`, runs in the containers with the worktree mounted read-only at its own path for `testdata`. The bench mounts `~/strava/configuration` at `/repo` instead, because a `~/strava` path mounted at itself shows up empty under Docker Desktop.
18. **Newline case**: T0 only. A directory name holding a newline splits its row in hop and in hopx alike (see "Found in hop"), so the cd tests reach it by path.

## Phase B4 (parity and performance)

1. **Reference hop**: the spec holds hopx to the worktree's `hop.zsh`, which is 0.2.0. B4 holds it to Eric's install, 0.3.1, released while the spike ran, and ports the 0.3.1 delta: the fitted layout, unclipped names in J3, the first-word kind, `_hop_elsewhere` with its main-checkout rule, the report lines that go with them, and `-v`. Not ported: 0.3.0's modal-layer change (esc keeps the query), since hopx has no modal layer, and the loaded-versus-installed `--version` text, which is about sourcing zsh.
2. **`HOPX_LAYOUT=fixed`** keeps hop 0.2's per-row layout. The default is 0.3's. The phase 1 to 3 goldens and the live tests against the worktree's 0.2.0 still pass either way, because they render rows one at a time or compare rels. `rows.sh`, `resolve.sh`, `e2e.sh` and `perf.sh` set the layout from the reference's `VERSION`.
3. **Two references in the Go tests**: the phase 1 to 3 live-zsh tests still compare against the worktree's 0.2.0. The new layout, unclip and headless tests compare against 0.3.1, unpacked from the worktree's git objects by `testfix.RefHome`. Rebasing the spike onto main would make that one reference, but it would change existing hop files in this branch, which the hard rules forbid.
4. **T4 hint**: `nothing close to: q (ctrl-u clears)`, which is hop 0.3's wording with `HOP_VIM=0`. hopx's picker has no modal layer and esc cancels it, so 0.2's `(esc clears)` and 0.3's `(esc twice clears)` were both wrong for hopx. `resolve.sh` runs zsh with `HOP_VIM=0`, and against 0.2.0 it reads the old hint in the new wording. The resolve goldens get the same rewrite in `byKey`.
5. **`e2e.sh` is new**: the spec's parity is `rows.sh` and `resolve.sh`, which call hop's internals. `e2e.sh` runs each tool's own shell function, so the flow around the resolver is covered too: T0, the kind word, `_hop_elsewhere`, `-c`, the levels, the report, rc and the history. Its two hand-written sets, `v03` and `away`, are not eval_real's.
6. **History in the harness**: the task asked for a temp history. `e2e.sh` uses a temp file emptied before every query, so one jump never re-ranks the next query and both sides start equal. `rows.sh` and `resolve.sh` keep `/dev/null`, as eval_real does.
7. **`__resolve-dump --ms`** prints each query's resolve time, T0 included, for perf.sh's per-tier table.
8. **`_hop_elsewhere`'s `~` form** goes through `rows.Tilde`, which models only `$HOME`, as in phase 1 (#10): a hop named directory would show differently in the "found in" note.
