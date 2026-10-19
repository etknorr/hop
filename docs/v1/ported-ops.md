# Ported cases: ops

Every `t '...'` case in the five suites the plan gives workstream B (`suite_upgrade`, `suite_completions`, `suite_smoke`, `suite_harness`, `suite_runner`, 114 cases), with the Go test that now holds it or `n/a` and why. Test names are `package.TestName/subtest`, where `main` is the repo root.

The suites cut across owners, so a few `suite_smoke` cases name another workstream's test or ledger rather than a B test.

## suite_upgrade (50)

| Case | Go test |
|---|---|
| the fixture remote really has two release tags | `upgrade.TestFixtureHasTwoReleases` |
| a HOP_HOME that is not a git checkout is refused | `upgrade.TestCheckoutRefusals/not_a_git_checkout` |
| a copy vendored inside another repo is refused, so that repo is never moved | `upgrade.TestCheckoutRefusals/vendored_inside_another_repo` |
| a checkout with no origin remote is refused | `upgrade.TestCheckoutRefusals/no_origin` |
| a dirty install is refused and the local edit survives | `upgrade.TestCheckoutRefusals/dirty` |
| a side branch is refused, because that is work in progress | `upgrade.TestCheckoutRefusals/side_branch` |
| HEAD detached at a commit that is not a release tag is refused | `upgrade.TestCheckoutRefusals/detached_off_a_release` |
| an unknown release is refused, and the ones that exist are named | `upgrade.TestCheckoutRefusals/unknown_release_names_the_real_ones` |
| a prerelease or topic tag can never become the newest release | `upgrade.TestCheck/an_older_pin_reports_both_and_an_update`, `upgrade.TestSortTags` |
| a tag origin does not publish cannot become the newest release | `upgrade.TestCheck/a_local_tag_origin_doesn't_publish_can't_be_newest` |
| a column.ui setting cannot hide every release tag | `upgrade.TestCheck/column.ui_and_tag.sort_change_nothing` |
| a tag.sort setting cannot reorder the releases | `upgrade.TestCheck/column.ui_and_tag.sort_change_nothing` |
| detached at a tag that is not a release reads as loose, and is refused | `upgrade.TestCheckoutRefusals/detached_at_a_topic_tag_reads_as_loose` |
| --check with a version is a usage error, not a report about the wrong thing | `upgrade.TestUsageErrors` |
| a dirty install hears about the dirt, not about the network | `upgrade.TestCheckoutRefusals/dirt_before_the_network` |
| a malformed version is rejected before anything is fetched | `upgrade.TestUsageErrors` |
| an unknown option is rejected with status 2 | `upgrade.TestUsageErrors`, `main.TestUpgradeIsFirstWordOnly` |
| two versions at once is rejected | `upgrade.TestUsageErrors` |
| a remote with no release tags is refused rather than guessed at | `upgrade.TestUntaggedRemote` |
| --check on an older pin reports both versions and exits 0 | `upgrade.TestCheck/an_older_pin_reports_both_and_an_update` |
| the installed version is read from VERSION, not inferred from the tag | `upgrade.TestCheck/VERSION_is_the_installed_version` |
| with no VERSION file the version falls back to git describe | `upgrade.TestCheck/no_VERSION_falls_back_to_git_describe` |
| --check on the newest release says up to date, and still exits 0 | `upgrade.TestCheck/the_newest_release_is_up_to_date` |
| --check leaves a dirty tree alone and still reports | `upgrade.TestCheck/a_dirty_tree_is_left_alone_and_named` |
| --check against a remote with no releases exits 0 and says so | `upgrade.TestUntaggedRemote` |
| --check on a checkout that is not a git repo fails, since there is nothing to report | `upgrade.TestCheck/not_a_checkout_fails` |
| a bare upgrade fast-forwards main and LEAVES YOU ON IT | `upgrade.TestCheckoutMoves/bare_upgrade_fast-forwards_main_and_stays_on_it,_then_rebuilds` |
| a bare upgrade never merges: main advances by fast-forward only | `upgrade.TestCheckoutMoves/bare_upgrade_fast-forwards_main_and_stays_on_it,_then_rebuilds` |
| a bare upgrade from a pin says it is leaving the pin, and returns to main | `upgrade.TestCheckoutMoves/from_a_pin_says_it_leaves_the_pin_and_returns_to_main` |
| upgrade to a bare semver pins to that exact release | `upgrade.TestCheckoutMoves/a_named_version_0.1.0_pins,_detached` |
| upgrade to a v-prefixed version pins to the same release | `upgrade.TestCheckoutMoves/a_named_version_v0.1.0_pins,_detached` |
| naming a version pins the install, detached, and says how to get back | `upgrade.TestCheckoutMoves/a_named_version_0.1.0_pins,_detached` |
| a main already ahead of the newest release is up to date, not an error | `upgrade.TestCheckoutMoves/main_ahead_of_the_release_is_up_to_date,_not_an_error` |
| --check on a main ahead of the newest release also says up to date | `upgrade.TestCheck/main_ahead_of_the_release_is_up_to_date` |
| a main that has diverged from the release is refused, never rebased or merged | `upgrade.TestCheckoutRefusals/diverged_main` |
| a bare upgrade from a pin fast-forwards the main REF, not just the worktree | `upgrade.TestCheckoutMoves/from_a_pin_with_main_behind_fast-forwards_the_main_ref` |
| an untracked file the release also ships is refused BEFORE the pin is left | `upgrade.TestCheckoutMoves/an_untracked_file_the_release_ships_is_refused_before_the_pin_is_left` |
| a pin with no local main branch is refused, and is told how to make one | `upgrade.TestCheckoutRefusals/pin_with_no_local_main` |
| upgrading to the release already pinned changes nothing | `upgrade.TestCheckoutMoves/the_release_already_pinned_changes_nothing` |
| an upgrade that changes nothing still says to reload when the shell loaded an older VERSION | `upgrade.TestCheckoutMoves/a_no-op_repeats_a_stale-shell_warning,_and_only_then`. In 1.0 "older" means the shell's init hash differs from the binary's |
| an upgrade that changes nothing says nothing about reloading when the shell is current | `upgrade.TestCheckoutMoves/a_no-op_repeats_a_stale-shell_warning,_and_only_then` |
| pinning to the release main is already standing on still detaches | `upgrade.TestCheckoutMoves/pinning_the_release_main_stands_on_still_detaches` |
| an untracked file does not block an upgrade, and is not removed by one | `upgrade.TestCheckoutMoves/an_untracked_file_elsewhere_neither_blocks_nor_is_removed` |
| upgrade --help prints usage and exits 0 without touching anything | `upgrade.TestUsageErrors`, `main.TestUpgradeIsFirstWordOnly` |
| the upgrade code never cleans, hard-resets or forces anything | `upgrade.TestNoDestructiveGit` |
| sourcing hop.zsh defines _hop_upgrade | n/a: there's no zsh source. `main.TestUpgradeIsFirstWordOnly` runs the registered verb |
| the usage text lists the upgrade verb | `main.TestUsageText` |
| the completion offers upgrade and can list local release tags | `shell.TestComplete` offers `upgrade` and its flags. Listing local tags is n/a: a brew or `go install` binary has no checkout to read tags from (plan 2.14) |
| hop.plugin.zsh parses, and is nothing but a shim onto hop.zsh | n/a: plugin-manager installs end with 1.0, and the shim is deleted at retirement |
| upgrade is only the verb as the first word, so a query can still contain it | `main.TestUpgradeIsFirstWordOnly` |

1.0 adds `upgrade.TestBrew`, `upgrade.TestGoInstall`, `upgrade.TestUnknown` and `upgrade.TestDetect` for the install methods 0.3.1 didn't have.

## suite_completions (10)

| Case | Go test |
|---|---|
| _hop_versions offers every tag, newest first, by default | n/a: release tags aren't completed, since a binary install has no checkout (plan 2.14) |
| _hop_versions still offers every tag as SEPARATE candidates under column.ui=always | n/a: as above |
| _hop_versions has nothing to offer when the repo has no release tags | n/a: as above |
| every option hop parses has a completion spec | `shell.TestCompleteCoversEveryFlag` reads `parseHop` in `hop.go` |
| --action completes exactly the modes hop accepts, in the same order | `shell.TestComplete` (`--action=`), `main.TestInitAndComplete` takes the modes from `config.Actions` |
| -o and -e exclude each other and --action, which is what hop refuses | `shell.TestComplete` (`-o\|-`, `-e\|-`, `-o\|--action=`) |
| --action excludes --cd, -o and -e, and --cd excludes --action alone | `shell.TestComplete` (`--action=open\|-`, `--cd\|-`, `--cd\|--action=`) |
| -p and --pick are one option | `shell.TestComplete` (`-p\|-`) |
| -v completes, and is described exactly as -V | `shell.TestComplete` |
| the header names every flag the specs define | n/a: `completions/_hop` and its comment header are deleted; every shell's completion comes from one table, `shell.hopFlags` |

## suite_smoke (48)

| Case | Go test |
|---|---|
| every component of the file list found files | n/a: an inventory of the zsh sources, which are deleted |
| bin/hop-preview is executable | n/a: previews are `hop __preview` |
| bin/hop-kinds is executable | n/a: the menu is `hop __menu` |
| sourcing hop.zsh defines hop, hopr and hopw | `shell.TestInitText`; `test/shell/run-all.sh` runs `hopr` and `hopw` in every shell |
| sourcing hop.zsh in a non-interactive shell is silent | `shell.TestInitSilent` |
| an inherited HOP_HOME naming the wrong install is overridden, not honoured | n/a: `HOP_HOME` is gone, and the binary finds itself with `os.Executable` |
| sourcing with a stale HOP_HOME emits nothing on stderr | n/a: as above |
| hop --help exits 0 and lists the registry, not a hardcoded kind list | `main.TestUsageText` |
| hop --help marks the default kinds with a star and names the config path | `main.TestUsageText` |
| hop --doctor exits 0 and reports install, config, tools and the confusable keys | `doctor.TestDoctorGolden`, `main.TestOptionLoopCases` |
| hop --doctor works outside a git repo, where it is most often needed | `doctor.TestDoctorOutsideARepo` |
| hop --doctor collapses $HOME to ~ and never prints it literally | `doctor.TestDoctorGolden`, `doctor.TestDoctorHomeForcedIntoOutput` |
| hop --doctor=short never prints $HOME, even forced to try | `doctor.TestDoctorHomeForcedIntoOutput` |
| hop --doctor=short exits 0, inside and outside a git repo | `doctor.TestDoctorGolden`, `doctor.TestDoctorOutsideARepo` |
| hop --doctor=short omits a sentinel kind name and workspace name that hop --doctor shows | `doctor.TestDoctorGolden` |
| hop --doctor shows HOP_ACTION, HOP_JUMP and HOP_CODE, and that VS Code is reachable | `doctor.TestDoctorSourcesAndModes` |
| hop --doctor names an invalid mode together with what hop does instead | `doctor.TestDoctorGolden` (`HOP_ACTION`), `doctor.TestDoctorSourcesAndModes` (`HOP_JUMP`) |
| hop --doctor says why VS Code is not reachable, with the reason the code verbs use | `doctor.TestDoctorGolden`. Doctor checks the launcher itself until `act.CodeUsable` exists (R2's stub, not on `v1/go`), so the integration owner points `doctor.Options.CodeUsable` at it |
| hop --doctor=short withholds a custom launcher path and any reason naming it, and keeps a known name | `doctor.TestDoctorGolden` (short golden), `doctor.TestDoctorSourcesAndModes` |
| VERSION is a bare semver, no v prefix | `main.TestReleaseFiles` |
| hop --version exits 0 and contains the VERSION contents | n/a: the binary's version comes from the build (goreleaser's `-X`, or build info), not `VERSION`. `version.TestRead`, `main.TestOptionLoopCases` |
| hop -V is the same as --version | `main.TestOptionLoopCases` |
| hop -v is the same as -V | `main.TestOptionLoopCases` |
| hop --version is exactly "hop VERSION (describe)" when the shell loaded what is on disk | `version.TestRead`: `hop 1.0.0`, and `hop devel (abc1234, dirty)` for a checkout build |
| the copied install prints exactly "hop VERSION" while nothing has changed on disk | `version.TestRead` (the `go install` and release forms carry no suffix) |
| after an upgrade under a live shell, --version names the loaded and the installed version | `main.TestVersionStaleness`, `version.TestStale`: 1.0 compares the shell's init hash with the binary's |
| after an upgrade under a live shell, --doctor flags the loaded version in one line | `doctor.TestDoctorGolden` (the `shell` line) |
| CHANGELOG.md keeps an Unreleased heading, so a release cannot strand entries | `main.TestReleaseFiles` |
| hop --help does not star an opt-in kind | `main.TestUsageText` |
| every hop setting the product reads is covered by the fixture pin list | n/a: `testfix.Isolate` drops every inherited `HOP_*` and `FZF_*` for every package |
| the fzf settings hop never names, and so cannot be scanned for, are pinned anyway | n/a: as above |
| a probe child gets the throwaway $HOME and XDG roots, never the real ones | n/a: `testfix.Isolate` (R1) |
| fixture_repo builds a throwaway git repo | n/a: `testfix.Build` (R1, frozen) |
| the fixture repo is under the temp root, never anywhere in $HOME | n/a: `testfix.Build` writes under `t.TempDir()` |
| _hop_generate runs against a fixture with no interactive fzf | n/a: the agnostic ledger's kinds tests |
| stub_bin shadows code, gh and bat on PATH | n/a: the interactive ledger's `act` tests |
| a stubbed command records its argv and opens nothing | n/a: as above |
| stub_bin redirects $EDITOR away from a real editor | n/a: as above |
| fzf --filter matches a row without opening a terminal | n/a: the interactive ledger's `match` tests |
| the .github yml glob finds exactly the files that are there | stays in `suite_smoke` until retirement, now listing `release.yml`. After that, `actionlint` and GitHub's own parse of each workflow cover it |
| the draining wrapper really is the only fzf a probe can see | `doctor.TestDoctorGolden` (every stub tool reads stdin to its end) |
| _hop_fzf_ver returns even when fzf is a wrapper that drains stdin | n/a: the interactive ledger's fzf version check |
| hop --doctor returns too, which is the command a bug report is told to run | `doctor.TestDoctorGolden`: tools get `/dev/null` as stdin and 3 s each |
| and hop --doctor=short returns, since both bodies share _hop_doctor_tool | `doctor.TestDoctorGolden` |
| the shipped file list found files, or the inventory below matches nothing and passes | n/a: an inventory of the zsh sources |
| the fzf invocations in the shipped source are exactly the reviewed set | n/a: the interactive ledger, since `pick` and `match` build every fzf argv |
| every _hop_pick and _hop_filter call site is fed by a pipe, so what it inherits is rows and never a terminal | n/a: zsh-only plumbing |
| a completed suite_core run leaves no fixture behind in its own temp root | n/a: `t.TempDir` removes its dirs |

## suite_harness (4)

| Case | Go test |
|---|---|
| the pty spawn scan can see pty.zsh and really does match a spawn | n/a: `tests/lib/pty.zsh` goes with `tests/`; Go's pty helper is `internal/ptytest` |
| every zpty spawn in tests/lib/pty.zsh sits inside a function | n/a: as above |
| the append scan counts appends, proven on a fixture whose count is known | n/a: the zsh harness's stub logging; the Go stubs log one line per call |
| a generated stub appends exactly once, so two of them cannot interleave | n/a: as above |

## suite_runner (2)

| Case | Go test |
|---|---|
| a bound-killed suite reports the passes it had already printed | n/a: `tests/run` is deleted; `go test` reports each test as it finishes, and `-timeout` bounds a hang |
| the bound-killed tally is the KILL path, not a trapped signal | n/a: as above |
