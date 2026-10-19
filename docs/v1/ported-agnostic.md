# Ported: agnostic

Every case in the six zsh suites whose cases mostly land in workstream C, each with the Go test that covers it or why it has none. `kinds.TestLiveZsh` and `kinds.TestGoldenRows` compare every fixture kind (named in brackets) with zsh hop 0.3.1's own rows. The suites' cases that belong to A or B say so and point at their ledger.

Also decided here:

- `testdata/fixture.toml`'s `fx` kind, an `--fn` provider, is now an exec kind, `testdata/fx.sh`. zsh hop reads it from `testdata/fixture-fn.zsh`, and the goldens didn't move.
- `internal/kinds/compat.zsh` is deleted with `--fn` support, so no 1.0 kind needs zsh at runtime.

## suite_dsl

| Line | Case | Go test |
|---|---|---|
| 165 | --dirs emits one row per child directory | kinds.TestLiveZsh, kinds.TestGoldenRows (svc) |
| 170 | --dirs at --depth 2 names parent/child, and never the container alone | kinds.TestLiveZsh, kinds.TestGoldenRows (svc2) |
| 175 | --dirs at depth 1 over the same tree returns the containers instead | kinds.TestLiveZsh, kinds.TestGoldenRows (svc: svc/ns at depth 1) |
| 181 | --dirs takes a comma-separated list of bases | kinds.TestLiveZsh, kinds.TestGoldenRows (svc: svc and the absent nope); importer.TestImportEveryOption |
| 187 | --dirs on an absent base emits nothing, silently | kinds.TestLiveZsh, kinds.TestGoldenRows (svc's absent base, and the empty-stderr check) |
| 199 | --marker maps path segments onto columns through the matching layout | kinds.TestLiveZsh, kinds.TestGoldenRows (tg); kinds.TestColumns |
| 204 | a shorter layout catches a shorter path | kinds.TestColumns; kinds.TestLiveZsh, kinds.TestGoldenRows (tg) |
| 208 | layouts are tried LONGEST first, so a deep path cannot fall into a shallow layout | kinds.TestColumns; kinds.TestLiveZsh, kinds.TestGoldenRows (tie) |
| 214 | a trailing ... joins every remaining segment into the name | kinds.TestColumns (rbac/reader) |
| 219 | a path matching NO layout is not a target, which is what excludes a shared include | kinds.TestColumns (lonely); kinds.TestLiveZsh, kinds.TestGoldenRows (tg's infra/shared) |
| 224 | with no --layout at all the name is the basename and the scope its parent | kinds.TestLiveZsh, kinds.TestGoldenRows (tgroot); kinds.TestColumns |
| 229 | a marker with no --under scans the whole repo | kinds.TestLiveZsh, kinds.TestGoldenRows (tgroot, tgx) |
| 237 | --files maps segments onto columns, and - discards one | kinds.TestLiveZsh, kinds.TestGoldenRows (cfg) |
| 243 | --strip-ext runs before the layout, so the extension never lands in a column | kinds.TestLiveZsh, kinds.TestGoldenRows (cfg) |
| 247 | without --strip-ext the extension stays in the column it landed in | kinds.TestLiveZsh, kinds.TestGoldenRows (odd) |
| 254 | --files rows point at the file, with its directory as the cd target | kinds.TestLiveZsh, kinds.TestGoldenRows (cfg); kinds.TestRecipes (backstage) |
| 261 | --name-template composes a name out of other columns | kinds.TestLiveZsh, kinds.TestGoldenRows (tgx); kinds.TestColumns |
| 268 | --trim strips a naming prefix off a column | kinds.TestLiveZsh, kinds.TestGoldenRows (tg); kinds.TestColumns |
| 275 | --name-template runs AFTER --trim, so it sees the trimmed value | kinds.TestColumns (template after trim) |
| 283 | --exclude drops a matching path before it becomes a row | kinds.TestLiveZsh, kinds.TestGoldenRows (tgx, odd) |
| 290 | without --exclude that same path IS a row, so the option is doing the work | kinds.TestLiveZsh, kinds.TestGoldenRows (tgroot keeps what tgx excludes) |
| 298 | --scope-literal overrides the scope column on every row | kinds.TestLiveZsh, kinds.TestGoldenRows (svc2, ents) |
| 306 | --preview walks its candidate list in order | kinds.TestLiveZsh, kinds.TestGoldenRows (tg, svc) |
| 311 | a 0-byte candidate is SKIPPED, because an empty pane is worse than the next candidate | kinds.TestLiveZsh, kinds.TestGoldenRows (tg: the empty main.tf) |
| 316 | a glob candidate expands alphabetically and also skips 0-byte files | kinds.TestZglob |
| 321 | --preview-skip removes a generated file from a glob match | kinds.TestLiveZsh, kinds.TestGoldenRows (tg: provider_aws.tf) |
| 327 | without --preview-skip that generated file wins, so the option is doing the work | kinds.TestPreviewSkipDoesTheWork |
| 332 | a directory with no candidate at all falls back to the directory itself | kinds.TestLiveZsh, kinds.TestGoldenRows (svc); kinds.TestDirSkipAndPreview |
| 340 | redeclaring a kind REPLACES it rather than adding a second entry | config.TestExtendAndRedeclare; importer.TestImportEveryOption |
| 348 | and it keeps its ORIGINAL position in the menu order | config.TestExtendAndRedeclare; importer.TestImportEveryOption |
| 351 | the redeclaration is what takes effect | config.TestExtendAndRedeclare |
| 356 | a redeclaration can also change the default flag | config.TestExtendAndRedeclare (dir loses default) |
| 368 | hop_kind with no shape option is rejected | config.TestValidationErrors (no shape); importer.TestImportErrors |
| 373 | hop_kind with an unknown option is rejected, and the option is named | config.TestValidationErrors (unknown kind key); importer.TestImportErrors (--bogus) |
| 379 | a value-taking option with no value is rejected rather than eating the next flag | importer.TestImportErrors (--desc needs a value) |
| 384 | --fn naming an undefined function is rejected | importer.TestImportErrors (--fn f has no hop equivalent) |
| 389 | --fn naming a real function is accepted | n/a: 1.0 has no --fn. Import refuses every provider but dir and helm (importer.TestImportErrors), and an exec kind replaces one (kinds.TestLiveZsh, fx) |
| 394 | a non-numeric --depth is rejected | importer.TestImportErrors (--depth two); config.TestValidationErrors (bad depth) |
| 399 | a zero --depth is rejected, since depth 0 would name the base itself | config.TestValidationErrors (bad depth); importer.TestImportErrors (--depth 0) |
| 404 | a missing kind name is rejected | config.TestValidationErrors (missing name) |
| 412 | hop_preset on an unknown name fails loudly rather than loading nothing | importer.TestImportErrors (no such preset); config.TestValidationErrors (bad recipe) |
| 417 | hop_preset loads the kinds a shipped preset declares | importer.TestPresetsMatchHop |
| 425 | asking for a kind nobody declared says so on stderr | kinds.TestUnknownKindAndOrder |
| 430 | a bare _hop_provider_<name> function still works without any registration | n/a: a bare provider function has no 1.0 equivalent; import warns about one (importer.TestImportBareProviderWarns) |

## suite_providers

| Line | Case | Go test |
|---|---|---|
| 190 | the shipped presets register exactly the kinds the repo ships | n/a: presets are recipes now; config.TestEveryRecipeLoadsClean, and importer.TestPresetsMatchHop for 0.3.1's own |
| 193 | every registered kind declares both a shape and a description | config.TestEveryRecipeLoadsClean |
| 200 | the default kind set comes from --default, not from a hardcoded list | config.TestZeroConfigDefaults; kinds.TestRecipes (defaults) |
| 206 | a fixture config REPLACES the shipped presets, so this suite is hermetic | config.TestZeroConfigDefaults (a config declaring a kind gets exactly that kind) |
| 213 | and clearing the fixture config brings the shipped presets back | config.TestZeroConfigDefaults (a missing file) |
| 238 | dir: a config-free repo yields exactly the <root> row | kinds.TestConfigFreeRepo |
| 245 | file: a config-free repo yields exactly its one tracked file | kinds.TestConfigFreeRepo |
| 252 | every shipped kind together emits zero stderr bytes in a config-free repo | kinds.TestConfigFreeRepo (every recipe together) |
| 357 | tg: the four-segment layout fills scope, env and region | kinds.TestLiveZsh, kinds.TestGoldenRows (tg); test/parity/rows.sh (tg) |
| 366 | tg: an env wider than its column is clipped with an ellipsis, never overflowed | rows.TestListLiveZsh03, rows.TestFit |
| 371 | tg: the row still carries the FULL path, so clipping is display-only | rows.TestListLiveZsh03, rows.TestRenderLiveZsh |
| 376 | tg: a unit is a dir target, so its rel is the repo-relative dir with a trailing / | rows.TestRel |
| 381 | tg: the two-segment layout renders env and region as - | kinds.TestColumns (the two-segment policies path) |
| 387 | tg: a trailing ... renders a nested unit as parent/child | kinds.TestColumns |
| 392 | tg: a shared include at depth 1 matches no layout and is excluded | kinds.TestLiveZsh, kinds.TestGoldenRows (tg: infra/shared) |
| 397 | tg: a dir with a .tf but no terragrunt.hcl is not a target | kinds.TestRecipes (modules/net is no tg row) |
| 401 | tg: a 0-byte main.tf loses to a real .tf beside it | kinds.TestLiveZsh, kinds.TestGoldenRows (tg: vpc's empty main.tf) |
| 407 | tg: a --preview-skip pattern loses to a real .tf that sorts after it | kinds.TestLiveZsh, kinds.TestGoldenRows (tg: vpc) |
| 413 | tg: a unit with no .tf at all falls back to its terragrunt.hcl | kinds.TestLiveZsh, kinds.TestGoldenRows (tg: the unit with only a terragrunt.hcl) |
| 423 | mod: --depth 2 names a module namespace/module, never the namespace alone | kinds.TestLiveZsh, kinds.TestGoldenRows (svc2); test/parity/rows.sh (mod) |
| 427 | mod: a module with no .tf falls back to its README | kinds.TestLiveZsh, kinds.TestGoldenRows (svc's README.md fallback); test/parity/rows.sh (mod) |
| 437 | helm: a dir whose only tracked file is .gitkeep is skipped | kinds.TestLiveZsh, kinds.TestGoldenRows (svc/empty, the dirs shape helm's first source uses); kinds.TestHelmSourcesMatchZsh |
| 441 | helm: a chart one level deeper renders as parent/child | kinds.TestHelmSourcesMatchZsh (scaffold/inner) |
| 446 | helm: the file-per-app family is one row per FILE, with the dir as the cd target | kinds.TestHelmSourcesMatchZsh |
| 455 | helm: an app file is a file target, so its rel is the file with no trailing / | kinds.TestHelmSourcesMatchZsh |
| 460 | helm: a Chart.yaml chart stays a dir target | kinds.TestHelmSourcesMatchZsh |
| 465 | helm: a tests/ dir under the app family is not an app | kinds.TestHelmSourcesMatchZsh (grp/tests) |
| 468 | helm: a 0-byte values.yaml loses to a real file beside it | kinds.TestHelmSourcesMatchZsh (loose's empty a.yaml) |
| 475 | helm: the one-chart-plus-templates family emits one row per template | kinds.TestHelmSourcesMatchZsh |
| 481 | helm: a template in the one-chart family is a file target (reworded) | kinds.TestHelmSourcesMatchZsh |
| 491 | serverless: a README at the family root is a file, not a unit | kinds.TestLiveZsh, kinds.TestGoldenRows (svc/rootfile); kinds.TestRecipes (serverless) |
| 495 | serverless: a unit with no serverless.yml falls through to template.yaml | importer.TestPresetsMatchHop (0.3.1's chain); kinds.TestRecipes (sam/app) |
| 500 | puppet: top-level modules/ is the family, not terraform/modules | importer.TestPresetsMatchHop; test/parity/rows.sh (puppet); kinds.TestRecipes (puppet) |
| 512 | backstage: --name-fn takes the name from metadata.name, not the filename | kinds.TestLiveZsh, kinds.TestGoldenRows (ents); kinds.TestEntityName |
| 517 | backstage: a file with no metadata.name falls back to its basename | kinds.TestEntityName |
| 521 | backstage: a key nested under something other than metadata cannot win | kinds.TestEntityName |
| 524 | backstage: dir is the containing dir and preview is the file | kinds.TestLiveZsh, kinds.TestGoldenRows (ents, backstage) |
| 532 | backstage: a --files row is a file target, so rel is the file itself | kinds.TestLiveZsh, kinds.TestGoldenRows (backstage); rows.TestRel |
| 537 | backstage: --scope-literal puts the same scope on every row | kinds.TestLiveZsh, kinds.TestGoldenRows (backstage) |
| 547 | dir: the root row comes first and previews the README | kinds.TestLiveZsh, kinds.TestGoldenRows (dir) |
| 556 | dir: the root row has rel ./, so it is reachable and still a dir target | rows.TestRel; kinds.TestDirSkipAndPreview |
| 560 | dir: build output and scratch space are not destinations | kinds.TestDirSkipAndPreview |
| 565 | dir: every tracked top-level directory is offered | kinds.TestLiveZsh, kinds.TestGoldenRows (dir); kinds.TestDirSkipAndPreview |
| 578 | file: dir is the containing directory and preview is the file itself | kinds.TestLiveZsh, kinds.TestGoldenRows (file) |
| 587 | file: a root-level file has the repo root as its dir | kinds.TestLiveZsh, kinds.TestGoldenRows (file); kinds.TestConfigFreeRepo |
| 595 | file: even a 0-byte tracked file is offered, because the question is "which file" | kinds.TestLiveZsh, kinds.TestGoldenRows (file: the empty main.tf) |
| 632 | a repo-root .hoprc is not sourced when HOP_HOPRC is unset | n/a: 1.0 never reads .hoprc (V1-PLAN 3.7); config.TestHoprcWarns |
| 637 | the unopted kind is genuinely undefined, not silently empty | n/a: as above |
| 640 | HOP_HOPRC=1 sources .hoprc, so the opt-in really is the only difference | n/a: HOP_HOPRC now only warns; config.TestHoprcWarns |
| 679 | every component of the enumeration-source list found files | n/a: a scan of zsh sources; Go lists the index once, in gitls.List |
| 682 | only _hop_ls talks to git ls-files, across lib, bin and presets | n/a: gitls.List is the only `git ls-files` call, one per run |
| 686 | _hop_ls adds :(glob), so a * in a magic-free spec cannot cross / | gitls.TestMatchAgreesWithGit |
| 692 | _hop_ls still matches at the depth a spec actually names | gitls.TestMatchAgreesWithGit |
| 710 | _hop_row_split keeps an empty field in its slot, so field 3 is always the preview | rows.TestSplitAndStrip |
| 715 | _hop_row_split reads a real _hop_row as display, dir, preview, rel | rows.TestSplitAndStrip |
| 720 | _hop_dirs_of returns field 2 of every row, one per row, even where a row is empty | n/a: a zsh helper; Go reads rows.Row.Dir |
| 724 | _hop_dirs_of agrees with _hop_row_split on real 4-field rows | n/a: as above |
| 741 | _hop_row: rel is the dir relative to the root, dimmed, with a trailing / for a dir target | rows.TestRel |
| 748 | _hop_row: f makes the preview the target, so rel is that file with no trailing / | rows.TestRel |
| 755 | _hop_row: the root itself is ./, and a dir that merely shares the prefix is not under it | rows.TestRel |
| 764 | _hop_row: with no root, rel is the ~ form, as the ws and repo pickers need | rows.TestRel |
| 771 | _hop_provider_repo: rel is the ~ form even inside a generate, so -R matches by it | kinds.TestWorkspaceAndRepoRowsMatchZsh |
| 787 | _hop_generate appends a derived dir rel to a legacy 3-field row, and leaves a 4-field one alone | n/a: 1.0 has no 3-field providers; an exec row always names its path |
| 795 | a registered --fn kind gets the same legacy upgrade as a bare provider | n/a: 1.0 has no --fn |
| 813 | real checkout: enumerating every shipped kind is silent on stderr | TestParityRows and test/parity/rows.sh, on HOP_PARITY_REPO |
| 817 | real checkout: the dir kind always finds the root row | test/parity/rows.sh (dir) |
| 827 | real checkout: every row points inside the repo it was asked about | test/parity/rows.sh; kinds.TestFixtureRowsAreReal on the fixture |

## suite_layout

| Line | Case | Go test |
|---|---|---|
| 186 | layout: the main picker keeps every column, because each holds a value on some row | rows.TestListLiveZsh03, against 0.3.1's _hop_layout |
| 191 | layout: a 73-character name is clipped to 56, keeping its start and its end | rows.TestListLiveZsh03, against 0.3.1's _hop_layout (the capped list) |
| 199 | layout: the clipped row keeps its full path in rel, so the hidden middle of its name still matches | rows.TestListLiveZsh03, against 0.3.1's _hop_layout |
| 210 | layout: a list whose env and region are always - drops both columns | rows.TestListLiveZsh03, against 0.3.1's _hop_layout |
| 215 | layout: a repo row is only its name and kind, because scope, env and region are always - | kinds.TestWorkspaceAndRepoRowsMatchZsh; rows.TestListLiveZsh03, against 0.3.1's _hop_layout |
| 220 | layout: a 41-character retired copy fits under the cap, so it shows whole beside the live repo | rows.TestListLiveZsh03, against 0.3.1's _hop_layout (the retired repo) |
| 227 | layout: a row built from _hop_row_like drops the same columns as its list | rows.TestListLiveZsh03, against 0.3.1's _hop_layout (the list laid out like the one before it) |
| 232 | layout: a list of short names is padded to the 20-column floor | rows.TestListLiveZsh03, against 0.3.1's _hop_layout; rows.TestListWidths |
| 237 | layout: a workspace row drops region, which is - on every one, and keeps its path and repo count | kinds.TestWorkspaceAndRepoRowsMatchZsh; rows.TestListLiveZsh03, against 0.3.1's _hop_layout |
| 242 | layout: the injected account dir is the first row the picker gets | n/a here: the resolver's ancestor injection, in the interactive ledger |
| 250 | layout: a row with no raw display, as a legacy provider prints, passes through untouched | rows.TestListWidths |
| 264 | layout: a separator byte inside a name reads as ?, so it adds no cell and shifts no column | rows.TestListLiveZsh03, against 0.3.1's _hop_layout (the separator byte) |
| 278 | layout: a dir row added to a tg-only list shows its kind whole, not as d… | rows.TestListLiveZsh03, against 0.3.1's _hop_layout (the dir row) |
| 293 | layout: a few long names are clipped to 28, so they do not widen the name column of every row | rows.TestListLiveZsh03, against 0.3.1's _hop_layout (the fit list) |
| 305 | resolve: a match whose name is clipped, but whose rel spells it whole, does not block a display jump | n/a here: the resolver's unclipped names, in the interactive ledger (resolve.unclip_test) |

## suite_cache

| Line | Case | Go test |
|---|---|---|
| 94 | a kind with zero targets warms to a real 0 and is then hidden | n/a: 1.0 has no kind-count cache; counts are live (DEVIATIONS B3 #4) |
| 114 | git add with HEAD unchanged surfaces a newly staged kind instead of hiding it forever | n/a: as above |

## suite_workspaces

| Line | Case | Go test |
|---|---|---|
| 194 | a config full of shell payloads yields only the legitimate entry | workspace.TestPayloadsAreInert |
| 200 | parsing a payload config says nothing on stderr | n/a: Parse writes no stderr; workspace.TestPayloadsAreInert |
| 209 | no payload of any shape reached a shell | workspace.TestPayloadsAreInert (the sentinel) |
| 212 | the sentinel mechanism can actually detect execution | n/a: Go's parser starts no process, so there is no shell to catch; the sentinel is an os.Stat |
| 222 | _hop_ws_for over a payload config executes nothing | n/a here: workspace.For is R2's, not on v1/go yet; hopw is the interactive ledger's |
| 229 | _hop_ws_repos and _hop_provider_ws over a payload config execute nothing | workspace.TestPayloadsAreInert (Repos, RepoList) |
| 236 | a payload in the NAME field is inert text, not a command | workspace.TestPayloadsAreInert |
| 248 | name = path, a bare path, tab separators and no spaces all parse | workspace.TestParseMatchesZsh; workspace.TestFileRules |
| 260 | a RUN of leading and trailing spaces is stripped, not a single space | workspace.TestFileRules |
| 267 | the first = splits, so a path may contain = itself | workspace.TestFileRules |
| 273 | a full-line comment and an indented one are dropped | workspace.TestParseMatchesZsh |
| 282 | a trailing comment is dropped but a # inside a path survives | workspace.TestParseMatchesZsh (#notcomment) |
| 290 | CRLF line endings parse | workspace.TestParseMatchesZsh (crlf) |
| 297 | a file with no trailing newline parses its last line | workspace.TestFileRules |
| 303 | an empty file means no workspaces, not the built-in default | workspace.TestFileRules |
| 310 | a comments-only file means no workspaces | workspace.TestFileRules |
| 316 | a missing file falls back to the built-in default, and only to the dirs that exist | workspace.TestFileRules |
| 323 | the built-in default offers every conventional checkout directory | workspace.TestFileRules |
| 336 | a missing file with no default directory reports nothing, silently | workspace.TestParseListBeatsFile (an empty HOME) |
| 342 | duplicate names: the first occurrence wins | workspace.TestParseMatchesZsh (one, twice) |
| 354 | a leading ~ expands, and a bare ~ is $HOME itself | workspace.TestExpand; workspace.TestFileRules |
| 362 | $HOME and ${HOME} both expand | workspace.TestExpand |
| 370 | an unset variable expands to empty, the way a shell would treat it | workspace.TestExpand |
| 377 | a mid-path ~ stays literal, because it is a legal filename character | workspace.TestExpand |
| 388 | a missing dir, a file, a dangling symlink and an unreadable dir are all skipped | workspace.TestParseMatchesZsh; workspace.TestFileRules |
| 403 | an unusable path is skipped with nothing on stderr | n/a: Parse writes no stderr |
| 406 | a config of nothing but unusable paths reports failure | workspace.TestFileRules |
| 419 | $HOP_WORKSPACES beats the file | workspace.TestParseListBeatsFile; config.TestWorkspaceSettings |
| 426 | $HOP_WORKSPACES splits on colons | config.TestWorkspaceSettings |
| 431 | the file beats the built-in default | workspace.TestParseMatchesZsh; workspace.TestFileRules |
| 438 | the default config path is derived from $XDG_CONFIG_HOME, not from the code directory | config.TestWorkspaceSettings |
| 446 | and it falls back to ~/.config when XDG_CONFIG_HOME is unset | config.TestWorkspaceSettings |
| 483 | a dir inside nested workspaces resolves to the DEEPER one | n/a here: workspace.For (R2), tested where hopw lands |
| 488 | the deeper workspace still wins when it is listed first | n/a here: as above |
| 492 | a dir under only the shallow workspace resolves to it | n/a here: as above |
| 496 | a workspace directory resolves to itself | n/a here: as above |
| 500 | a dir in no workspace fails and leaves REPLY empty | n/a here: as above |
| 506 | a sibling whose name merely starts with the workspace name is not inside it | n/a here: as above |
| 530 | a .git directory and a git WORKTREE both count as a repo | workspace.TestReposAndRepoList (wt-repo) |
| 536 | the worktree fixture really does have a FILE at .git | workspace.TestReposAndRepoList |
| 543 | depth 1 only: a repo one level deeper is not found | workspace.TestReposDepthOne |
| 548 | a directory with no .git is not a repo | workspace.TestReposDepthOne; workspace.TestReposAndRepoList |
| 552 | a workspace holding no repos fails | workspace.TestReposDepthOne |
| 558 | a workspace that does not exist fails, silently | workspace.TestReposDepthOne |
| 576 | one row per workspace, with the absolute dir in field 2 | kinds.TestWorkspaceAndRepoRowsMatchZsh |
| 583 | every row carries the ws kind and its own name | kinds.TestWorkspaceAndRepoRowsMatchZsh |
| 591 | the repo count is pluralised per row | kinds.TestWorkspaceAndRepoRowsMatchZsh |
| 597 | $HOME is collapsed to ~ in the displayed path | kinds.TestWorkspaceAndRepoRowsMatchZsh |
| 603 | a workspace row has the ~ form as its rel, so the path column never searches $HOME itself | kinds.TestWorkspaceAndRepoRowsMatchZsh |
| 608 | no workspaces means no rows, and still exits 0 | kinds.TestNoWorkspacesNoRows |
| 619 | no test in this suite executed anything from a config file | workspace.TestPayloadsAreInert |

## suite_integration

| Line | Case | Go test |
|---|---|---|
| 278 | default-kind enumeration is under its 5000ms budget | n/a: timing is test/parity/perf.sh, an integration gate |
| 281 | default-kind enumeration yields every target in the fixture, silently | kinds.TestFixtureRowsAreReal; kinds.TestGoldenRows |
| 285 | every enumerated row carries an absolute dir that exists | kinds.TestFixtureRowsAreReal |
| 336 | a --version query neither reads stdin nor erases the records the other tests read | n/a: the zsh suite's fzf stub |
| 356 | the stub exits on a --version query even when stdin never reaches EOF | n/a: as above |
| 388 | the recorded fzf call is the interactive picker, not the headless matcher | n/a here: the picker, in the interactive ledger |
| 392 | the picker passes --exact to fzf | n/a here: the picker, in the interactive ledger |
| 395 | an empty query passes --select-1, the one-row auto-accept | n/a here: the picker, in the interactive ledger |
| 425 | hop -c in a subtree shows fewer rows than the repo root | n/a here: hop()'s -c, in the interactive ledger (TestHeadlessAgainstHop's -c cases) |
| 430 | every row hop -c offers is inside $PWD | n/a here: as above |
| 442 | hop -c with no match in the subtree says so and returns non-zero | n/a here: as above |
| 462 | hopr cds to the repo root from a nested directory | n/a here: hopr is the shell function, in the ops ledger |
| 470 | hopr outside a git repo says so and returns non-zero | n/a here: as above |
| 477 | hopw cds to the workspace containing $PWD | n/a here: hopw, in the interactive and ops ledgers |
| 485 | hopw outside every configured workspace errors cleanly | n/a here: as above |
| 505 | a scratch repo produces no rows for the shaped kinds | kinds.TestConfigFreeRepo |
| 510 | hop in a scratch repo degrades to one stderr line and a non-zero exit | n/a here: hop()'s message, in the interactive ledger |
| 519 | the dir kind still gets a scratch repo out of trouble | kinds.TestConfigFreeRepo |
| 539 | the worktree fixture is a real second checkout | kinds.TestWorktreeRows |
| 543 | enumerating a worktree yields paths inside the worktree, never the main checkout | kinds.TestWorktreeRows |
| 554 | the worktree preview target is the worktree copy of the file | kinds.TestWorktreeRows |
| 565 | every component of the become() scan list found files | n/a here: the picker, in the interactive ledger |
| 568 | no become() anywhere in the executable source | n/a here: the picker, in the interactive ledger |
| 584 | the no-bat PATH really has no bat on it | n/a here: the preview pane, in the interactive ledger |
| 590 | hop-preview on a directory exits 0 with empty stderr | n/a here: as above |
| 597 | hop-preview on a text file exits 0 with empty stderr and shows the content | n/a here: as above |
| 605 | hop-preview on a missing path exits 0 with empty stderr and one warning | n/a here: as above |
| 612 | hop-preview with no arguments exits 0 with empty stderr | n/a here: as above |
| 619 | hop-preview --keys renders both modes for the ? overlay | n/a here: the ? overlay, in the interactive ledger |
| 646 | real checkout: default-kind enumeration is under its 10000ms budget | n/a: test/parity/perf.sh |
| 649 | real checkout: enumeration is silent on stderr | TestParityRows and test/parity/rows.sh |
| 652 | real checkout: every row carries an absolute dir that exists | test/parity/rows.sh |
