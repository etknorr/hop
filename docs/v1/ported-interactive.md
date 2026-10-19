# Ported: interactive (workstream A)

Every `t '...'` case of the zsh suites whose behaviour lives in A's packages, with the Go test that now holds it or why none does. R2 never sorted the 713 cases, so this ledger takes the 13 suites the plan says mostly land in interactive whole; a case that belongs to B or C says so rather than being dropped.

Generated from `tests/suite_*.zsh` at 0.3.1. Counts: keymap 71, guard 15, pty 9, pty_escape 11, pty_filter 4, pty_reload 1, actions 39, clipboard 12, editor_path 8, nottty 31, fzf_version 24, match 93, core 51, 369 in all.

## suite_keymap

| line | case | Go test or n/a |
|---|---|---|
| 131 | j is down, restoring the preview | TestBindsLiveZsh (byte-equal to zsh's _hop_vim_binds), TestVerbs |
| 134 | k is up, restoring the preview | TestBindsLiveZsh (byte-equal to zsh's _hop_vim_binds), TestVerbs |
| 137 | g is first, restoring the preview | TestBindsLiveZsh (byte-equal to zsh's _hop_vim_binds), TestVerbs |
| 140 | G is last, restoring the preview | TestBindsLiveZsh (byte-equal to zsh's _hop_vim_binds), TestVerbs |
| 143 | ctrl-d is half-page-down, restoring the preview | TestBindsLiveZsh (byte-equal to zsh's _hop_vim_binds), TestVerbs |
| 146 | ctrl-u is half-page-up, restoring the preview | TestBindsLiveZsh (byte-equal to zsh's _hop_vim_binds), TestVerbs |
| 149 | o prints ctrl-o and accepts (open in code) | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 152 | O prints ctrl-t and accepts (open folder) | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 155 | e prints alt-o and accepts (edit) | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 158 | y prints ctrl-y and accepts (copy) | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 161 | Y prints alt-y and accepts (copy file) | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 164 | b prints ctrl-g and accepts (browse/github) | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 170 | c prints alt-enter and accepts (cd, whatever Enter does), except in the : menu | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 173 | p toggles the preview | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 176 | q aborts | TestBindsLiveZsh, TestVerbs, TestPickerVerbs |
| 179 | r reloads the restore command, when one was given | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 182 | l prints ctrl-l and accepts, when a drill target was given | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 185 | h prints ctrl-h and accepts, when an up-level target was given | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 188 | ? toggles the keys overlay, reading its own state from FZF_PREVIEW_LABEL | TestKey, TestKeyCallback, TestPickerModal |
| 192 | esc resolves from FZF_PROMPT and FZF_QUERY, never a file | TestKey, TestKeyCallback |
| 201 | esc back to NORMAL keeps search on, so a cleared query re-filters | TestBindsLiveZsh (TO_NORMAL), TestPickerModal (esc esc from a zero-match query) |
| 205 | / switches to SEARCH: unbinds the vim keys, enables search, re-prompts | TestBindsLiveZsh, TestPickerModal |
| 213 | : switches to the kind menu in place, reloading from hop-kinds | TestBindsLiveZsh (TO_MENU), TestPickerModal |
| 222 | unmapped letters, digits and symbols default to ignore | TestBindsLiveZsh, TestVerbs |
| 236 | with no drill, up or restore target, l, h and r all fall back to ignore | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 241 | l is live only when a drill target was actually given | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 246 | h is live only when an up-level target was actually given | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 251 | r is live only when a restore command was actually given | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 260 | with no root, : falls back to ignore (no menu to switch into) | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 263 | with no root, c needs no menu test, so it is the plain always-cd action | TestBindsLiveZsh (targets, workspaces, repos shapes), TestVerbs |
| 266 | with no root, enter is never bound at all (plain accept needs no help) | TestBindsLiveZsh (workspaces, repos), TestArgvShape |
| 278 | every key unbound entering SEARCH is rebound returning to NORMAL, and both match the owned key list | TestBindsLiveZsh (start and TO_NORMAL), TestVerbs (Keys) |
| 356 | the real, full bind set parses against this machine's installed fzf | TestArgvParses (every argv, on fzf 0.60.3, 0.67.0 and 0.73.1, with a bogus-action control) |
| 364 | the resolver's ordered-mode picker argv parses against this machine's installed fzf | TestArgvParses (every argv, on fzf 0.60.3, 0.67.0 and 0.73.1, with a bogus-action control) |
| 371 | the picker argv at a non-cd mode parses against this machine's installed fzf | TestArgvParses (every argv, on fzf 0.60.3, 0.67.0 and 0.73.1, with a bogus-action control) |
| 379 | sanity: a bind action with a stray leading comma is rejected, not silently accepted | TestArgvParses (every argv, on fzf 0.60.3, 0.67.0 and 0.73.1, with a bogus-action control) |
| 390 | sanity: a backslash-escaped comma inside unbind(...) is rejected, not silently accepted | TestArgvParses (every argv, on fzf 0.60.3, 0.67.0 and 0.73.1, with a bogus-action control) |
| 427 | the guarded probe produced a bind set at all | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 431 | every action that leaves the picker is wrapped in the guard | TestBindsLiveZsh (guarded and unguarded shapes) |
| 445 | the navigation keys stay fork-free, exactly as they were | TestBindsLiveZsh (guarded and unguarded shapes) |
| 455 | the in-picker actions are left alone, r included | TestBindsLiveZsh (guarded and unguarded shapes) |
| 463 | a key gated off by its own missing target is never guarded | TestBindsLiveZsh (guarded and unguarded shapes) |
| 472 | every escape introducer fzf can surface as alt-<char> writes a mark | TestBindsLiveZsh (guarded and unguarded shapes) |
| 486 | the guard lists are matched exactly, not as globs | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 492 | the alt- keys hop and fzf already own are never turned into marks | TestBindsLiveZsh (guarded and unguarded shapes) |
| 501 | the mark set is exactly the owned key list minus the twelve already-taken keys | TestBindsLiveZsh (guarded and unguarded shapes) |
| 541 | both picker probes captured a real argument list | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 549 | ctrl-g is inert, so a bare BEL byte cannot reach the browse verb | TestArgvShape, TestArgvGolden, TestBindsLiveZsh |
| 554 | ctrl-g is gone from --expect, in both modes, because --expect outranks every bind | TestArgvShape, TestArgvGolden, TestBindsLiveZsh |
| 560 | browse moved to alt-B, printing the key _hop_dispatch already knows | TestArgvShape, TestArgvGolden, TestBindsLiveZsh |
| 565 | browse did not land on alt-g or alt-b, which are both already taken | TestArgvShape, TestArgvGolden, TestBindsLiveZsh |
| 570 | alt-enter prints alt-enter and accepts, in both modes, except in the : menu | TestArgvShape, TestArgvGolden, TestBindsLiveZsh |
| 675 | the overlay probe actually rendered the keys overlay | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 680 | the ? overlay names exactly the gated keys the picker actually bound | TestOverlayLiveZsh, TestKeyCallback |
| 686 | the repo and workspace pickers advertise only the one gated key each really has | TestOverlayLiveZsh, TestKeyCallback |
| 691 | the NORMAL legend names : view only where a root makes the kind menu real | TestHeaderLiveZsh, TestArgvShape |
| 697 | dropping : view leaves the rest of the NORMAL legend intact | TestHeaderLiveZsh, TestArgvShape |
| 704 | the legends at HOP_ACTION=cd say enter cd and name no c or M-enter | TestHeaderLiveZsh, TestArgvShape |
| 710 | the legends at HOP_ACTION=open say enter open, and c and M-enter cd | TestHeaderLiveZsh, TestArgvShape |
| 722 | the legends on workspace and repo rows name reveal as the open it runs | TestHeaderLiveZsh, TestArgvShape |
| 729 | the non-modal legend is no wider at the longest mode than at cd | TestLegend (35 columns at every mode) |
| 806 | all three transform bodies were actually extracted from the bind set | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 820 | esc in the kind menu goes back to the view you came from | TestKey, TestKeyCallback, TestPickerModal |
| 824 | esc in SEARCH returns to NORMAL with the query kept | TestKey, TestKeyCallback, TestPickerModal |
| 829 | esc in SEARCH on an empty query still returns to NORMAL rather than quitting | TestKey, TestKeyCallback, TestPickerModal |
| 832 | esc in NORMAL with a query clears it and stays in NORMAL | TestKey, TestKeyCallback, TestPickerModal |
| 835 | esc in NORMAL with no query quits | TestKey, TestKeyCallback, TestPickerModal |
| 838 | enter in the kind menu switches to the picked kind | TestKey, TestKeyCallback, TestPickerModal |
| 842 | enter outside the menu is a plain accept | TestKey, TestKeyCallback, TestPickerModal |
| 845 | ? opens the keys overlay when it is not already showing | TestKey, TestBindsLiveZsh (HELP_ON, HELP_OFF), TestPickerModal |
| 849 | ? closes the keys overlay and restores the real preview when it is showing | TestKey, TestBindsLiveZsh (HELP_ON, HELP_OFF), TestPickerModal |

## suite_guard

| line | case | Go test or n/a |
|---|---|---|
| 10 | bin/hop-guard is executable | n/a: the guard is `hop __guard`, a verb of the binary |
| 29 | mark writes a clock reading a check can compare against | TestMarkAndCheck |
| 45 | a verb landing inside the window is refused | TestMarkAndCheck |
| 49 | the same verb outside the window runs untouched | TestMarkAndCheck |
| 55 | the window is a real threshold, not a constant answer | TestMarkAndCheck |
| 68 | a refused verb pushes the window forward, so a long payload cannot outlast it | TestRearm |
| 76 | a verb that RUNS does not re-arm, so the chain ends at the first real keypress | TestRearm |
| 88 | no mark at all means no escape arrived, so the verb runs | TestFailOpen |
| 92 | an unreadable state file fails open rather than closed | TestFailOpen |
| 95 | a corrupt mark fails open instead of aborting | TestFailOpen |
| 99 | a mark from the future fails open, so a backwards clock cannot quarantine the verbs | TestFailOpen |
| 112 | a malformed window falls back to the default instead of aborting | TestWindow |
| 130 | HOP_GUARD_WINDOW=0 is the off switch a timing heuristic has to have | TestFailOpen, TestGuardCallback |
| 134 | check with no action prints nothing, rather than inventing an ignore | TestGuardCallback |
| 138 | an unknown subcommand is silent and successful, since fzf shows a bind error as a dead key | TestGuardCallback |

## suite_pty

| line | case | Go test or n/a |
|---|---|---|
| 50 | pty: canary reaches fzf with one keystroke | n/a: zpty harness self-check; ptytest's TestTerm covers the Go helper |
| 62 | pty: j moves the cursor in NORMAL | TestPickerModal |
| 82 | pty: o fires the open verb on the focused row | TestPickerVerbs |
| 100 | pty: o on a dir-preview row opens a new window, never code -r | TestKeys (ctrl-o on a dir preview is code -n), TestPickerVerbs |
| 118 | pty: enter cds to the focused row | TestPickerModal |
| 138 | pty: / enters SEARCH and letters type | TestPickerModal |
| 159 | pty: esc returns to NORMAL and keeps the filter | TestPickerModal |
| 184 | pty: a query matching nothing survives two escs | TestPickerModal |
| 219 | pty: the : view menu comes back with esc | TestPickerModal |

## suite_pty_escape

| line | case | Go test or n/a |
|---|---|---|
| 186 | pty-esc: a bare BEL byte reaches no verb | TestPickerGuard |
| 201 | pty-esc: an OSC 11 background-colour reply reaches no verb | TestPickerGuard |
| 209 | pty-esc: the same OSC 11 reply BEL-terminated reaches no verb | TestPickerGuard |
| 217 | pty-esc: a truncated OSC 11 reply reaches no verb | TestPickerGuard |
| 224 | pty-esc: an OSC 10 foreground-colour reply reaches no verb | TestPickerGuard |
| 232 | pty-esc: an OSC 52 clipboard reply reaches no verb | TestPickerGuard |
| 240 | pty-esc: a DCS version reply reaches no verb | TestPickerGuard |
| 257 | pty-esc: a long APC payload cannot outlast the guard | TestPickerGuard |
| 276 | pty-esc: a real b still browses, so the negatives are not vacuous | TestPickerGuard |
| 292 | pty-esc: a real y still copies, so the negatives are not vacuous | TestPickerGuard |
| 314 | pty-esc: with the guard off, the reply reaches browse unless fzf drops it | TestPickerGuard |

## suite_pty_filter

| line | case | Go test or n/a |
|---|---|---|
| 50 | pty-filter: enter in NORMAL cds to a row of the kept filter | TestPickerModal |
| 68 | pty-filter: esc in NORMAL clears the query, and the next esc quits | TestPickerModal |
| 89 | pty-filter: / after esc edits the kept query from its end | TestBindsLiveZsh (end-of-line in the / action) |
| 105 | pty-filter: hop <words> opens in SEARCH, and esc keeps the words | TestPickerModal (a relaxed pick opens in SEARCH), TestArgvShape |

## suite_pty_reload

| line | case | Go test or n/a |
|---|---|---|
| 57 | pty: alt-a reloads with the user config, not the shipped presets | TestPickerVerbs (HOP_VIM=0 alt-a reaches a non-default kind of the user's config) |

## suite_actions

| line | case | Go test or n/a |
|---|---|---|
| 26 | ctrl-o on a file preview opens it with code -r | TestEnterModes, TestKeys |
| 32 | ctrl-o on a dir preview opens a new window with code -n, never code -r | TestEnterModes, TestKeys |
| 40 | ctrl-t opens the dir with code -n | TestEnterModes, TestKeys |
| 46 | no verb ever hands code -r a directory | TestEnterModes, TestKeys |
| 63 | HOP_CODE names the launcher, word-split, and its flags come before -r | TestEnterModes, TestKeys (HOP_CODE word-split into the Actor) |
| 205 | matrix: the probe ran every case | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 213 | (one case per loop pass) matrix: ${ac_f[1]} on ${ac_f[3]}, code ${ac_f[2]} | TestEnterModes, TestKeys |
| 221 | matrix: code -r never received a directory, across every mode, target and state | TestEnterModes, TestKeys |
| 239 | a code call that fails after the cd keeps the cd and returns code's status | TestCdKeepsCdWhenCodeFails |
| 249 | headless open of a file with code absent launches no editor, prints the path, and fails | TestNoCode |
| 260 | Enter under open still teaches the MRU the dir | TestEnterModes, TestKeys |
| 267 | ctrl-o and ctrl-t teach the MRU the row's dir as well | TestEnterModes, TestKeys |
| 272 | alt-enter cds whatever the mode, and calls no code | TestEnterModes, TestKeys |
| 279 | a row whose dir is not absolute, as a : menu row is, moves nothing and opens nothing | TestKeys |
| 292 | ctrl-o with VS Code unreachable says why and falls back to the editor | TestCodeUsable |
| 340 | _hop_code_usable: the pinned test environment can reach the stub | TestCodeUsable |
| 343 | _hop_code_usable: a launcher that is not installed, or does not exist, is unusable with _hop_need's reason | TestCodeUsable |
| 347 | _hop_code_usable: a stale VSCODE_IPC_HOOK_CLI is unusable | TestCodeUsable |
| 351 | _hop_code_usable: a live IPC socket is usable even over SSH on a Linux host with no DISPLAY | TestCodeUsable |
| 354 | _hop_code_usable: an SSH session with no IPC hook is unusable, by SSH_CONNECTION or SSH_TTY | TestCodeUsable |
| 359 | _hop_code_usable: Linux with neither DISPLAY nor WAYLAND_DISPLAY is unusable, and either one is enough | TestCodeUsable |
| 366 | _hop_code_usable: WSL with no DISPLAY is usable, since code there is the Windows-side shim | TestCodeUsable |
| 503 | flags: the probe ran every flag case | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 518 | (one case per loop pass) flags: ${ac_fl} sets the matching mode, alone and with -k, -a, -c, -w, -R and an empty query | TestFlagsAgainstHop, TestEnterModes |
| 540 | flags: -o and -e are exclusive, either way round | TestFlagsAgainstHop (against zsh hop 0.3.1) |
| 544 | flags: --action cannot be mixed with --cd, -o or -e | TestFlagsAgainstHop (against zsh hop 0.3.1) |
| 548 | flags: an unknown --action mode, or --action with no MODE, is refused | TestFlagsAgainstHop (against zsh hop 0.3.1) |
| 554 | flags: hop / and hop - still refuse every other argument, an action flag included | TestFlagsAgainstHop (against zsh hop 0.3.1) |
| 560 | HOP_ACTION from the environment sets the mode, and a flag replaces it for the call | TestFlagsAgainstHop (against zsh hop 0.3.1) |
| 565 | an invalid HOP_ACTION warns exactly once and cds | TestHeadlessSettingsAgainstHop |
| 572 | hopr, hop / and hopw are navigation by name, so HOP_ACTION=open still only cds | TestFlagsAgainstHop (against zsh hop 0.3.1) |
| 578 | a literal path jumps with the mode: a dir opens with -n and reveals its top file, a file opens with -r | TestSuiteMatch, TestGoldenTable (actions per case), TestEnterModes |
| 584 | a J2 directory jump reveals the account dir's top file, with the note, and --cd keeps the cd | TestSuiteMatch, TestGoldenTable (actions per case), TestEnterModes |
| 588 | reveal on a dir with no file at its top explains itself: a failure alone, a note after a cd | TestEnterModes, TestNoCode |
| 592 | reveal with no VS Code names the file it would have shown, and what -o does instead | TestEnterModes, TestNoCode |
| 596 | J1b reads the mode hop resolved: two files in one dir jump under cd, and need a pick under -o or --cd -e | TestSuiteMatch, TestGoldenTable (actions per case), TestEnterModes |
| 602 | HOP_ACTION set in config.zsh is honoured over the environment, and --cd still replaces it | n/a: 1.0 lets the environment beat the config file (2.15); C's TestSettingsPrecedence |
| 645 | picker: alt-enter on row 2 under HOP_ACTION=open cds there and calls no code | TestPickerVerbs (c and Enter under HOP_ACTION=open) |
| 656 | picker: Enter on row 2 under HOP_ACTION=open opens its dir and leaves the shell where it was | TestPickerVerbs (c and Enter under HOP_ACTION=open) |

## suite_clipboard

| line | case | Go test or n/a |
|---|---|---|
| 135 | pbcopy is chosen when every candidate is present | TestClipboardProbe, TestKeys |
| 141 | wl-copy is chosen when pbcopy is absent | TestClipboardProbe, TestKeys |
| 147 | xclip is chosen when pbcopy and wl-copy are absent | TestClipboardProbe, TestKeys |
| 153 | xsel is chosen when pbcopy, wl-copy and xclip are absent | TestClipboardProbe, TestKeys |
| 159 | clip.exe is the last resort, chosen only when nothing else is present | TestClipboardProbe, TestKeys |
| 168 | HOP_CLIPBOARD overrides the probe even when pbcopy is available | TestClipboardProbe, TestKeys |
| 174 | HOP_CLIPBOARD word-splits so extra arguments reach the command | TestClipboardProbe, TestKeys |
| 183 | the exact text handed to hop is what reaches the clipboard tool, unmodified | TestClipboardProbe, TestKeys |
| 188 | the copy is a stdin pipe, never an argv, even for tools that take extra flags | TestClipboardProbe, TestKeys |
| 197 | no clipboard tool available: one clear stderr line, non-zero exit, nothing invoked | TestClipboardProbe, TestKeys |
| 210 | no clipboard tool available: the message names install options, not a stack trace | TestClipboardProbe, TestKeys |
| 235 | a failing clipboard command is reported, not swallowed as success | TestClipboardProbe, TestKeys |

## suite_editor_path

| line | case | Go test or n/a |
|---|---|---|
| 30 | _hop_need accepts a bare name found on PATH | TestNeed |
| 36 | _hop_need rejects a bare name missing from PATH, with the original wording | TestNeed |
| 45 | _hop_need accepts an absolute path to an executable | TestNeed |
| 51 | _hop_need rejects an absolute path that does not exist, without claiming "not installed" | TestNeed |
| 57 | _hop_need rejects an absolute path that exists but is not executable | TestNeed |
| 66 | _hop_need accepts a relative path (contains a slash) resolved against the cwd | TestNeed |
| 80 | a real absolute-path $EDITOR is invoked to edit a file (alt-o) | TestNeed |
| 88 | an absolute-path $EDITOR that does not exist fails, and the editor is never invoked | TestNeed |

## suite_nottty

| line | case | Go test or n/a |
|---|---|---|
| 125 | the fixture built | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 133 | no ctty, MULTI-match query: a diagnostic naming the count, not a hang | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 142 | no ctty, EMPTY query: the diagnostic still names the count | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 153 | no ctty, ZERO-match query: says nothing matched rather than hanging | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 166 | no ctty, UNIQUE-match query: still cds, exactly as before the fix | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 175 | no ctty, ONE-ROW list and an EMPTY query: still cds | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 201 | headless: a 3-field and a 4-field row both come back from _hop_filter with their own dir and preview | TestFilter |
| 223 | the shared matcher never matches the colour codes, only the text the picker shows | TestFilter, TestHeadlessAgainstHop |
| 229 | no ctty, a query spelled from colour codes: nothing matched, as the picker would say | TestFilter, TestHeadlessAgainstHop |
| 255 | no ctty, an ambiguous query names the count and the best matches | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 265 | no ctty, a typo says what it was read as and leaves the shell where it was | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 274 | no ctty, a relaxed pick names the words to drop or fix | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 280 | no ctty, -p on one match says -p always picks, instead of advising a narrower query | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 287 | no ctty, over the row cap a typo says it was not corrected, and why | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 293 | no ctty, a query every match sits under jumps to that dir and says so | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 303 | no ctty, an ordinary query logs its generate step, so the T0 case below can test for its absence | n/a here: HOP_DEBUG is B's log (2.11); A's generate, resolve, pick and dispatch call sites wait for debuglog.Printf |
| 308 | no ctty, a literal path jumps without enumerating anything | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 320 | no ctty, WORKSPACE picker: a diagnostic naming the count, not a hang | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatchDetails |
| 335 | --filter and --select-1 agree on what "unique" means | TestEmptyQuery, TestSuiteMatch |
| 383 | the shared matcher flags are exactly the set both fzf calls were written against | TestFlagsMatchHop, TestArgvGolden, TestArgvShape |
| 395 | the flag pattern still matches something, so the two zero counts below mean absence | n/a: a check on the zsh test harness's own probe; the Go tests build the argv directly |
| 398 | the picker hardcodes no matcher flag of its own | TestFlagsMatchHop, TestArgvGolden, TestArgvShape |
| 401 | the resolver's filter hardcodes no matcher flag of its own | TestFlagsMatchHop, TestArgvGolden, TestArgvShape |
| 409 | the picker passes the shared matcher flags | TestFlagsMatchHop, TestArgvGolden, TestArgvShape |
| 412 | the resolver's filter passes the shared matcher flags | TestFlagsMatchHop, TestArgvGolden, TestArgvShape |
| 422 | --accept-nth is the picker's alone, never part of what --filter is handed | TestFlagsMatchHop, TestArgvGolden, TestArgvShape |
| 427 | the picker asks for dir, preview and rel, in that order | TestArgvShape (--accept-nth=2,3,4), TestParse |
| 434 | the resolver's filter passes neither --no-sort nor --freeze-left | TestFlagsMatchHop, TestArgvGolden, TestArgvShape |
| 461 | no ctty: the predicate is false in every redirected shape | TestHeadlessAgainstHop (every case runs with no controlling terminal), internal/tty TestIs |
| 480 | the predicate reads /dev/tty and never tests a file descriptor | TestHeadlessAgainstHop (every case runs with no controlling terminal), internal/tty TestIs |
| 540 | a ctty present: the predicate is true in every redirected shape | TestPickerModal, TestPickerStatus (a pty is a controlling terminal), internal/tty TestIs |

## suite_fzf_version

| line | case | Go test or n/a |
|---|---|---|
| 68 | the fzf stub is in place, so nothing below touches the real fzf | n/a: zsh harness self-check; TestHeadlessSettingsAgainstHop wraps the real fzf in a version stub |
| 73 | the only fzf a probe can reach is the stub | n/a: zsh harness self-check; TestHeadlessSettingsAgainstHop wraps the real fzf in a version stub |
| 78 | the stub refuses to emulate the picker, so a stray UI call fails instead of passing | n/a: zsh harness self-check; TestHeadlessSettingsAgainstHop wraps the real fzf in a version stub |
| 84 | sourcing hop.zsh forks nothing, because every shell pays for that | n/a: the binary is not sourced; hop init's cost is B's |
| 90 | an fzf older than the minimum is refused, with the version, the need and the fix | TestVersion |
| 99 | the message names the flag combination that actually breaks | TestVersion |
| 103 | the exact minimum passes | TestVersion |
| 109 | one patch release below the minimum is refused | TestVersion |
| 116 | a newer fzf passes, including a two-digit minor | TestVersion |
| 121 | a major-version bump passes rather than reading as older | TestVersion |
| 126 | a two-field version is compared as if the patch were zero | TestVersion |
| 131 | an unparseable version proceeds, because locking out a working fzf is worse | TestVersion |
| 137 | no version output at all also proceeds | TestVersion |
| 143 | the version is read at most once per shell, however often hop runs | n/a: one process per call; match.FZF.Version memoises within it |
| 149 | an unparseable version is memoized too, so it cannot fork on every call | n/a: one process per call; match.FZF.Version memoises within it |
| 155 | the floor covers what esc reads: a transform's FZF_PROMPT and FZF_QUERY | TestPickerModal and TestPickerGuard, run on fzf 0.60.3, 0.67.0 and 0.73.1 |
| 171 | HOP_FZF_MIN can be lowered, for an fzf that is fine despite its version string | TestVersion, TestHeadlessSettingsAgainstHop |
| 176 | a HOP_FZF_MIN with a non-numeric field still returns a verdict, not a math error | TestVersion, TestHeadlessSettingsAgainstHop |
| 183 | a garbage HOP_FZF_MIN fails open rather than blocking every hop | TestVersion, TestHeadlessSettingsAgainstHop |
| 189 | the shipped minimum is the one the changelog justifies | TestVersion |
| 196 | the picker passes --freeze-left=1 from fzf 0.67.0 on, and never below it or on an unknown version | TestFeatures, TestArgvParses (on 0.60.3, 0.67.0 and 0.73.1) |
| 214 | _hop_ver_lt orders versions field by field, not as strings | TestVersion |
| 222 | _hop_ver_lt is false for equal and for newer versions | TestVersion |
| 233 | hop itself refuses on a too-old fzf, before it reaches the picker | TestHeadlessSettingsAgainstHop |

## suite_match

| line | case | Go test or n/a |
|---|---|---|
| 152 | the table runner answered every case, silently | TestGoldenTable, TestLiveZsh |
| 183 | (one case per loop pass) $REPLY | TestGoldenTable, TestLiveZsh (the 126 table cases), TestSuiteMatch |
| 200 | (one case per loop pass) $REPLY | TestGoldenTable, TestLiveZsh (the 126 table cases), TestSuiteMatch |
| 239 | resolve: terraform/nope/x falls through to the matcher | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 250 | resolve: a path no row is close to is NONE, which is the only verdict that looks in other repos | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 256 | resolve: a literal path under HOP_JUMP=never opens the picker instead | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 274 | resolve: acct sec prod puts the account dir first, then its own units | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 347 | (one case per loop pass) resolve: ${w} is fzf syntax, so its typo is left for the user to fix | TestGoldenTable, TestLiveZsh (the 126 table cases), TestSuiteMatch |
| 361 | resolve: abg is exact-unique, and only because of --exact | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 368 | (one case per loop pass) resolve: ${w} | TestGoldenTable, TestLiveZsh (the 126 table cases), TestSuiteMatch |
| 391 | resolve: _hop_hits answers in zsh exactly as fzf --filter does, word by word | TestSuiteMatchDetails, TestAncestors, TestApproxAgainstZsh |
| 412 | resolve: the relaxed tier decides its kept words in zsh, without an fzf per word | TestSuiteMatchDetails, TestAncestors, TestApproxAgainstZsh |
| 436 | resolve: -c keeps every candidate and every injected ancestor inside $PWD | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 456 | _hop_ancestors walks every strict ancestor, drops dirs already matched, and honours the -c subtree | TestSuiteMatchDetails, TestAncestors, TestApproxAgainstZsh |
| 463 | resolve: an OR group drops every alternative that holds a shorter one, which matches no extra row | TestSuiteMatchDetails, TestAncestors, TestApproxAgainstZsh |
| 480 | resolve: a kind word never J2-jumps, even when every match sits under one dir | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 486 | resolve: no nonsense word jumps, and none of them occurs in the fixture | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 498 | resolve: every pick in the table is exactly fzf's own row set for its picker query | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 507 | the one --filter call site hands fzf neither --no-sort nor --accept-nth | TestFlagsMatchHop, TestFilter |
| 514 | a 4-field row comes back from _hop_filter whole, on the installed fzf | TestFlagsMatchHop, TestFilter |
| 538 | resolve: a visited vpc is the first picker row, and the verdict is still pick | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 541 | resolve: the exact name thanos still outranks a visited thanos-legacy | TestSuiteMatch, TestGoldenTable, TestLiveZsh, TestMRU |
| 558 | resolve: a legacy 3-field --fn provider still resolves, by its derived rel | n/a here: --fn providers go in 1.0 (3.2); C's ledger |
| 574 | hop --doctor names the kind that printed legacy 3-field rows, and no other | n/a here: --doctor is B's; legacy 3-field rows are C's (--fn goes in 1.0) |
| 615 | picker: an ambiguous vpc opens on --query=vpc in ordered mode, without --select-1 | TestArgvShape, TestArgvGolden, TestEmptyQuery |
| 622 | picker: the vpc rows are the first rows of its stdin | TestSuiteMatch, TestHeadlessAgainstHop, TestPickerModal |
| 627 | picker: Enter on row 2 cds to row 2's dir | TestPickerModal (j j k then enter) |
| 635 | picker: acct sec prod opens with the synthetic account row first, still coloured | TestSuiteMatch, TestHeadlessAgainstHop, TestPickerModal |
| 643 | picker: a T2 pick opens on the rewrite, with a header saying so | TestSuiteMatch, TestHeadlessAgainstHop, TestPickerModal |
| 651 | picker: nothing close opens on the query as typed, with a header saying so | TestSuiteMatch, TestHeadlessAgainstHop, TestPickerModal |
| 656 | picker: without the modal layer, the nothing-close header names ctrl-u, since esc quits there | TestLiveZsh (HOP_VIM off and on), TestSuiteMatch, TestHeadlessSettingsAgainstHop |
| 673 | picker: an empty query keeps --select-1, which is the one-row auto-accept | TestArgvShape, TestArgvGolden, TestEmptyQuery |
| 684 | picker: -p opens the picker despite a unique match | TestSuiteMatch, TestHeadlessAgainstHop, TestPickerModal |
| 692 | picker: HOP_JUMP=unique opens the picker where J2 would have jumped | TestSuiteMatch, TestHeadlessAgainstHop, TestPickerModal |
| 695 | picker: an invalid HOP_JUMP warns once and behaves as auto | TestHeadlessSettingsAgainstHop |
| 707 | (one case per loop pass) picker: --freeze-left=1 follows the fzf version, here ${w} | TestFeatures, TestArgvParses |
| 739 | workspaces: hop -w with a unique name jumps there | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 743 | workspaces: hop -w matching two workspaces names the count | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 748 | workspaces: outside a repo, a name no workspace answers falls back to the repos | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 754 | workspaces: outside a repo, an exact repo match beats a workspace pick that ignored a word | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 758 | workspaces: the repo fallback resolves the repos once, not again inside the repo picker | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 763 | repos: a name exactly one repo has jumps past the repos that only contain it | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 767 | repos: a name two repos share exactly still opens the picker | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 772 | workspaces: and a name neither level answers still says nothing matched | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 777 | repos: hop -R matches by the ~ rel | TestHeadlessAgainstHop, TestHeadlessAgainstHop03 |
| 784 | T0 through hop: a path followed by more words is a query, not a path | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatch |
| 788 | T0 through hop: -p and HOP_JUMP=never open the picker on a path instead of jumping | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatch |
| 799 | T0 through hop: -R names the repo level, so a path in this repo is a repo query | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatch |
| 806 | T0 through hop: ~/x, ~name/x, an absolute path off the root, and a path outside any repo | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatch |
| 816 | T0 through hop: inside a repo, a path the repo spells differently is still a typo, not a cross-repo lookup | TestHeadlessAgainstHop, TestHeadlessAgainstHop03, TestSuiteMatch |
| 831 | elsewhere: outside any repo, a repo-relative path jumps into the one repo that has it, and says where | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 836 | elsewhere: from a workspace root, the same path jumps the same way | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 840 | elsewhere: a path that starts with its repo name jumps from outside any repo | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 847 | elsewhere: a workspace-relative path that names no repo jumps too, and says which workspace | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 852 | elsewhere: one repo reached by two spellings is one target, so it still jumps | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 857 | elsewhere: the wrong case lands on the on-disk spelling | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 861 | elsewhere: a path in no repo still says nothing matched | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 866 | elsewhere: a misspelt path no repo has names the repo that holds its first dir | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 873 | elsewhere: a path two repos have never jumps, and the report names both | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 881 | elsewhere: of two, the repo visited most recently comes first | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 887 | elsewhere: with a terminal, the two open in the picker on the path, and Enter cds to the one picked | TestHeadlessAgainstHop03, TestElsewhereWordShape |
| 898 | elsewhere: a visit inside hop.old ranks hop.old, never the hop whose name it starts with | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 906 | elsewhere: the picker names each repo and lines its rows up as one list, from outside a repo or inside one | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 939 | (one case per loop pass) $MT_SORT_T | TestGoldenTable, TestLiveZsh (the 126 table cases), TestSuiteMatch |
| 979 | elsewhere: of two checkouts of one origin, the one on its default branch is jumped to, and the note says why | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 984 | elsewhere: HOP_JUMP=unique keeps the default-branch checkout a pick, since the path names two targets | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 989 | elsewhere: a linked worktree on main beats its primary on a branch, with main as the default when origin/HEAD is unset | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1003 | elsewhere: with no origin/HEAD and no main, a packed master is the default branch | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1008 | elsewhere: two on main, different origins, a checkout with no origin, and a detached HEAD all still pick | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1015 | elsewhere: inside a repo, a path only another repo has jumps there, because this repo has nothing close | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1020 | elsewhere: inside a repo, a path that starts with that repo's own name finds it, with no workspace holding it | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1026 | elsewhere: inside a repo, its own match wins: a T0 path, a J2 jump, and a typo pick all stay here | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1035 | elsewhere: -c and -R never look in other repos | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1043 | elsewhere: -p and HOP_JUMP=never still look in other repos, and open the picker on even one hit | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1054 | elsewhere: the lookup logs as T0 with its own timing | n/a here: HOP_DEBUG is B's log (2.11) |
| 1068 | elsewhere: every action flag applies to a cross-repo jump | TestHeadlessAgainstHop03, TestGitFacts, TestElsewhereWordShape |
| 1073 | resolve: an injected dir previews its top-level README, and a dir with none previews itself | TestSuiteMatchDetails, TestGoldenTable |
| 1107 | resolve: hostile FZF_DEFAULT_OPTS and an fzf alias change no resolve | TestHostileDefaults |
| 1139 | eval_real: without HOP_TEST_REPO it skips, and succeeds | n/a: eval_real is replaced by test/parity/*.sh against the installed hop |
| 1146 | eval_real: an unknown set is refused with status 2 | n/a: eval_real is replaced by test/parity/*.sh against the installed hop |
| 1153 | eval_real: over the fixture, every jump today is kept and the run succeeds | n/a: eval_real is replaced by test/parity/*.sh against the installed hop |
| 1162 | eval_real: the four query sets are all derived and swept | n/a: eval_real is replaced by test/parity/*.sh against the installed hop |
| 1171 | eval_real: the fixture's scope+env pairs jump to the account dirs as new jumps | n/a: eval_real is replaced by test/parity/*.sh against the installed hop |
| 1174 | eval_real: HOP_EVAL_JUMP=never loses every jump today, and the run fails naming them | n/a: eval_real is replaced by test/parity/*.sh against the installed hop |
| 1209 | kind word: file as the first word is -k file, says so, and the action still applies | TestHeadlessAgainstHop03, TestKindWordGuard |
| 1217 | kind word: file alone opens on the file kind and never jumps | TestHeadlessAgainstHop03, TestKindWordGuard |
| 1223 | kind word: a kind with one row alone still waits for a pick | TestHeadlessAgainstHop03, TestKindWordGuard |
| 1237 | kind word: a rest that matches nothing is reported with -k, never as an ignored word | TestHeadlessAgainstHop03, TestKindWordGuard |
| 1242 | kind word: puppet, which a row holds, tg, an active kind, a typed -k, and a later word all stay plain words | TestHeadlessAgainstHop03, TestKindWordGuard |
| 1258 | kind word: a kind that is only part of a word some row holds is still read as -k | TestHeadlessAgainstHop03, TestKindWordGuard |
| 1262 | kind word: a kind with no rows in this repo stays a plain word | TestHeadlessAgainstHop03, TestKindWordGuard |
| 1267 | kind word: a typed -k whose kind has no rows here still finds a path in another repo | TestHeadlessAgainstHop03, TestKindWordGuard |
| 1272 | kind word: -w and -R keep it a plain word, and outside a repo it is read only before a path | TestHeadlessAgainstHop03, TestKindWordGuard |

## suite_core

| line | case | Go test or n/a |
|---|---|---|
| 89 | the stub fzf really is the only fzf a probe can see | n/a: zsh harness self-check |
| 93 | hop -w reports a non-zero fzf status instead of swallowing it | TestPickerStatus |
| 98 | hop -R reports the same status the same way, so the two pickers cannot drift | TestPickerStatus |
| 103 | hop -w on a no-match says so, rather than printing nothing at all | TestPickerStatus |
| 108 | hop -w on a user cancel stays silent and succeeds | TestPickerStatus |
| 113 | esc out of the repo picker is silent too, which is what makes 130 a shared rule | TestPickerStatus |
| 118 | both pickers route through the one _hop_fzf_status, so the ladder cannot be duplicated | TestPickerStatus |
| 124 | _hop_ws_picker leaves no _hop_key, _hop_rel or _hop_st behind in the calling shell | n/a: a process leaves nothing in the calling shell |
| 134 | _hop_parse_result reads dir, preview and rel, and strips the dim from rel | TestParse |
| 141 | _hop_parse_result keeps an empty preview empty, so it falls back to dir and rel stays rel | TestParse |
| 170 | HOP_DEBUG=1 logs a pick that found no match, which used to log nothing at all | n/a here: HOP_DEBUG is B's log (2.11); A's pick call site waits for debuglog.Printf |
| 176 | HOP_DEBUG=1 logs a user cancel, so an abandoned pick is distinguishable from a crash | n/a here: HOP_DEBUG is B's log (2.11); A's pick call site waits for debuglog.Printf |
| 180 | HOP_DEBUG=1 logs a hard fzf failure, the case a bug report cannot diagnose without it | n/a here: HOP_DEBUG is B's log (2.11); A's pick call site waits for debuglog.Printf |
| 185 | the row count reaches the log, so "empty list" and "list did not match" are tellable apart | n/a here: HOP_DEBUG is B's log (2.11); A's pick call site waits for debuglog.Printf |
| 189 | HOP_DEBUG unset still writes nothing, so the new call site stays opt-in | n/a here: HOP_DEBUG is B's log (2.11); A's pick call site waits for debuglog.Printf |
| 219 | the fixture really is reached through a symlink, or the cases below prove nothing | TestFlagsAgainstHop (symlinked -c), TestHeadlessAgainstHop (-c cases) |
| 228 | hop -c finds targets in a subtree entered through a symlink | TestFlagsAgainstHop (symlinked -c), TestHeadlessAgainstHop (-c cases) |
| 235 | and the surviving rows are the ones under that subtree, not the whole repo | TestFlagsAgainstHop (symlinked -c), TestHeadlessAgainstHop (-c cases) |
| 242 | hop -c still narrows, so the symlink fix did not turn the filter off | TestFlagsAgainstHop (symlinked -c), TestHeadlessAgainstHop (-c cases) |
| 249 | hop -c under a subtree with no targets still says so, by its own message | TestFlagsAgainstHop (symlinked -c), TestHeadlessAgainstHop (-c cases) |
| 257 | a directory whose name holds a backslash is not mangled, which awk -v did | TestFlagsAgainstHop (symlinked -c), TestHeadlessAgainstHop (-c cases) |
| 267 | and that backslash subtree offers its own row, not a sibling | TestFlagsAgainstHop (symlinked -c), TestHeadlessAgainstHop (-c cases) |
| 274 | the -c filter no longer forks awk, per the same rule providers.zsh already follows | n/a: zsh fork-count rules; Go filters in process |
| 287 | _hop_filter_under keeps the dir itself and everything beneath it, in order, and nothing beside it | TestHeadlessAgainstHop (-c cases), TestRowsCallback |
| 311 | _hop_rank floats visited dirs in history order, stably, and leaves the rest in input order | TestRank, TestRankAgainstZsh |
| 319 | _hop_rank with no history, or none naming a row, returns the rows byte for byte | TestRank, TestRankAgainstZsh |
| 326 | _hop_rank reads field 2 through _hop_dirs_of, not per row | n/a: zsh fork-count rules; Go filters in process |
| 341 | _hop_remember drops entries that are no longer dirs, and keeps the rest literally and in order | TestRemember, TestRememberAtomic |
| 349 | pruning runs before the HOP_HIST_MAX bound, so a stale entry never takes the place of a live one | TestRemember, TestRememberAtomic |
| 373 | a plainly assigned HOP_CONFIG is exported, which is what a .zshrc line needs | n/a here: config export is zsh-only; HOP_HOPRC is C's (3.7) |
| 382 | HOP_HOPRC is not invented when it was never set | n/a here: config export is zsh-only; HOP_HOPRC is C's (3.7) |
| 386 | HOP_HOPRC is exported once the user does set it, so the opt-in survives into a child | n/a here: config export is zsh-only; HOP_HOPRC is C's (3.7) |
| 394 | bin/hop-kinds sees the user kinds, which is what the : menu renders | TestRowsCallback, TestMenuCallback, TestPickerVerbs (alt-a with the user's config) |
| 402 | the reload command forwards HOP_CONFIG, so alt-a regenerates with the user kinds | TestRowsCallback, TestMenuCallback, TestPickerVerbs (alt-a with the user's config) |
| 409 | and running that reload command really does emit the user rows, not unknown kind | TestRowsCallback, TestMenuCallback, TestPickerVerbs (alt-a with the user's config) |
| 417 | the reload child keeps zsh -f, so a reload can never source the user rc files | TestRowsCallback, TestMenuCallback, TestPickerVerbs (alt-a with the user's config) |
| 422 | a HOP_CONFIG assigned AFTER hop.zsh was sourced still reaches the reload child | TestRowsCallback, TestMenuCallback, TestPickerVerbs (alt-a with the user's config) |
| 451 | a reload ranks visited dirs first, as the list it replaces was ranked | TestRowsCallback, TestMenuCallback, TestPickerVerbs (alt-a with the user's config) |
| 458 | a HOP_HISTFILE that was never exported still reaches the reload child | TestRowsCallback, TestMenuCallback, TestPickerVerbs (alt-a with the user's config) |
| 467 | an empty HOP_HISTFILE goes to the child as /dev/null, so a reload cannot turn history back on | TestRowsCallback, TestMenuCallback, TestPickerVerbs (alt-a with the user's config) |
| 472 | a reload under -c keeps only the rows under that dir | TestRowsCallback, TestPickerModal (a menu switch keeps -c) |
| 477 | _hop_rows says which way it came up empty, so hop() can word each case | TestHeadlessAgainstHop (both no-targets messages) |
| 484 | hop -c hands its subtree to the alt-a and r reloads it gives the picker | TestRowsCallback, TestPickerModal (a menu switch keeps -c) |
| 500 | bin/hop-kinds rows ranks visited dirs first, and --under narrows it | TestRowsCallback, TestPickerModal (a menu switch keeps -c) |
| 509 | the : kind switch carries the -c dir, and its reload runs under sh as fzf runs it | TestRowsCallback, TestPickerModal (a menu switch keeps -c) |
| 543 | with HOP_FZF_HEIGHT unset the picker still gets its default 80% geometry | TestArgvGolden, TestArgvShape |
| 551 | and an empty HOP_FZF_HEIGHT asks for no height at all, which is what a pty needs | TestArgvGolden, TestArgvShape |
| 571 | the stub answers --version without reading stdin, exactly as the real fzf does | n/a: zsh harness self-check |
| 580 | and it does so wherever --version sits in argv, not only as the first word | n/a: zsh harness self-check |
| 586 | and a whole probe finishes when the runner is handed stdin that never reaches EOF | n/a: zsh harness self-check |
| 598 | a picker reaps a hop-guard directory that a killed picker could not clean up | TestSession (a day-old hop-pick-* dir is reaped) |

## Guard fork cost

The 0.15 s window was sized for zsh's 15 to 22 ms `hop-guard` fork. Go's `hop __guard` is a whole hop process per key, so it was measured rather than assumed. Other sessions kept this machine's load average at 5 or above, so no truly idle run exists; the quietest row stands in for it. Each figure is 200 runs of the built binary against a guarded session, macOS arm64, `time.perf_counter` around the fork.

| load avg | `__guard mark` | `__guard check o` | `__key esc` | zsh `hop-guard check` |
|---|---|---|---|---|
| 4.9 (quietest reached) | median 8.4 ms, p90 10.9 ms | median 7.8 ms, p90 9.7 ms | median 7.8 ms, p90 9.6 ms | median 11.9 ms, p90 13.6 ms |
| 18.0 (parity running) | median 15.3 ms, p90 26.4 ms | median 12.9 ms, p90 24.3 ms | median 11.0 ms, p90 20.0 ms | median 16.4 ms, p90 25.8 ms |

The Go callback is no slower than the zsh one it replaces at either load, so `DefaultWindow` stays 0.15 and `HOP_GUARD_WINDOW` keeps its meaning. `TestPickerGuard` holds the window end to end: seven escape classes and a BEL-terminated OSC run nothing, `j j b` typed 60 ms apart still browses, and a plain `y` still yanks.

## Deviations from 0.3.1

- `/` in the `:` menu prompts `:/ ` rather than `/ `, so esc and enter still know the list holds kinds after a filter.
- Enter on a menu row records that kind as the session's view, so `r` and esc out of a later menu return to it rather than to the first kind.
- `l` on a workspace lists that workspace's repos; 0.3.1 showed a single row.
- `l` on a repo opens that repo's targets, which 0.3.1 had no level for.
- `h` is bound only where a level above exists, so the `?` overlay never teaches a dead key.
- Cancelling the picker (fzf 130) exits 0, as the shell wrappers' tests now expect.

## Known gaps

R2's seams never landed on `v1/go`, so A worked inside its own files and left these for whoever lands R2 or B:

- `-h`, `-V` and `--doctor` are not parsed by `parseHop`.
- No `debuglog.Printf` call sites, since there is no debuglog stub to call.
- No README "Using the picker" section, since there is no README skeleton to fill.
- `HOP_GUARD_WINDOW`, `HOP_FZF_MIN`, the raw `HOP_JUMP` and `HOP_ACTION`, and `HOP_CODE` are read from the environment in A's code, not from `config.Settings`, so none has a `[settings]` key.
- `wsFor` lives in `cmd_picker.go` rather than as `workspace.For`.
- The `eric_test.go` consolidation was not done.
- Docker Desktop doesn't share `~/worktrees/hop` paths into `test/shell/run-all.sh`'s container, so its g6 step can't see `testdata/`. The pty tests now write their own config, which sidesteps it rather than fixing the mount.
