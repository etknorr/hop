# Investigation evidence

Preserved artifacts from three 0.1.x investigations. **Nothing here is part of the test suite, and
nothing here is run by CI.**

They are kept because they are the only record of what a mechanism *cannot* be. Re-deriving a
withdrawn finding is expensive, and several of these probes are what bound one.

## Not all of it is on this branch

**The 0.1.x evidence lives on two sibling branches, and neither contains the other**, so no single
ref holds all of it. Both descend from `b0ac7b1`, which is the last commit they share.

- **`evidence/0.1.1-investigations`**, this branch: `escape-audit/`, `pty-trap/` and
  `tally-bound/`, described below.
- **`evidence/046-pty-flake-captures`** at `4aedcf4`: `docs/evidence/pty-flake/`, holding
  **31 capture runs**, `run-001.txt` through `run-031.txt` with no gaps, plus `INDEX.txt` and
  `flakeloop.zsh`. Nothing else on that branch is unique to it.

**If you arrived on `4aedcf4` first, do not trust its copy of this file.** It branched before the
`exp3.zsh` correction below, so its `pty-trap/` table still calls the flake still-open at about
1-in-40, and both halves of that are false. **Treat this branch as the current text and that one as
the capture set.**

Those 31 runs are what settled the flake's rate at about 1 in 6, which Caveats records along with
the reason its `INDEX.txt` cannot be counted at face value. They were captured at `87be1ed`, an
ancestor of the fix in `b3dd791`, so they measure the flake as it actually behaved.

## Why they live here rather than under `tests/`

`tests/run` discovers suites with a non-recursive glob over `tests/suite_*.zsh`, and
`fixture_sources parseable` scans the same path. Putting `suite_zz*.zsh` back under `tests/` would
therefore enrol them in the suite: they would run, hang on a pty, and inflate the test count. Every
file here is `zsh -n` clean, so the repo-wide `find . -name '*.zsh'` lint leg passes over them, but
that is the only automation that touches them.

Each file's own header says "not for commit", which was true of its original purpose. They are
committed here as evidence instead, with their bytes unmodified.

## `escape-audit/`

Scratch pty probes written while closing the escape-sequence verb hole. Headers cite the
originating task #31; the lasting value is noted per file.

| File | What it establishes |
| --- | --- |
| `suite_zzesc.zsh` | Drives the real picker under a pty and injects undecoded escape sequences as input: OSC 11/10 colour replies, DA1, CPR, DCS XTVERSION, OSC 52, bracketed paste, and truncated variants. This is the reproduction behind the guard that shipped in 0.1.1. |
| `suite_zzctrl.zsh` | A single raw control **byte** with no escape sequence around it, run under both `HOP_VIM=1` and `HOP_VIM=0`. **This is the evidence for the deferred task on `\b`/`\f` arriving as `ctrl-h`/`ctrl-l`.** Those are `--expect` keys, and `--expect` outranks every bind, so the guard structurally cannot cover them. Moving the remaining `--expect` keys onto guarded binds is the queued follow-up. |
| `suite_zztty.zsh` | Whether a proposed `/dev/tty` guard would pass while the picker still works, across redirected stdin shapes (`< /dev/null`, `0<&-`, a pipe, stdout to `cat`). Bears on the no-tty fallback that shipped in 0.1.1. |
| `suite_zzwidget.zsh` | The same sequences reaching the real zle widget, via an interactive `zsh -i` under the pty, rather than reaching the picker directly. |

## `pty-trap/`

Artifacts bounding a **withdrawn** finding: the claim that `pty.zsh`'s inherited `EXIT` trap was
destroying fixtures mid-run. It was not. These are what stop someone re-deriving the wrong answer.
Headers cite task #43.

| File | What it establishes |
| --- | --- |
| `decide.zsh` | The decisive one. A `zpty -b` spawned at a script's **top level** versus inside a **function**, which is what `pty.zsh` actually does. Distinguishes the two cases the finding conflated. |
| `realcanary.zsh` | Whether the real, unmodified `pty_canary` wipes the fixtures it depends on. Answer: no. |
| `exp1.zsh`, `exp2.zsh` | Instrumented models of `pty_canary`'s shape, with the trap tagged by `$$` so the log names which process ran it. Note `exp2.zsh` carries `exp1`'s header verbatim; the header was not updated when it was copied. |
| `exp3.zsh` | Models the real `_hop_pty_onexit` preamble faithfully (`_hop_t_report`, then `pty_reap_all`, which forks `ps -A`, only then `fixture_cleanup`) and measures how often the poll wins the race, which exp1 could not do because its trap went straight to cleanup and won every time. **The flake it was chasing is SOLVED, in `b3dd791`, and this race was not the cause.** `bin/hop-guard` timed each verb against the previous check's clock reading, so its discriminator was the cost of its own fork: 12.7ms mean idle against 425ms mean at loadavg 35, past the 150ms threshold. Separately, the pty stubs wrote each log line as three appends, so a concurrent `bat` render recorded `batgh browse` in place of `gh browse`. **Do not rerun this hunting an open bug.** |
| `sabotage.zsh` | A sabotage matrix: each guard reverted in turn to prove the corresponding test fails when the thing it protects is removed. |
| `bound2.pl` | The `tests/run` process bound verbatim (fork, child `setpgrp`, parent alarm, `KILL` on the negative pid), for cases that must keep a controlling terminal where `setsid` would destroy the thing under test. |

## `tally-bound/`

Captures proving that a suite killed by its bound used to discard every result it had already
printed, and the baseline showing the fix changes nothing on a clean run. Only the two harness
headers carry a task reference, #59; the bound raise beside it was #58, and the captures are raw
runner output with no header. `hop_bound` kills the process group with `KILL`, which no trap can catch, so the child's
sentinel line never arrived and the parent counted zero; the parent now counts the markers it is
already holding instead.

**`pr59-tally/` is the expensive set: the two `*.color.txt` files can only be regenerated under a
pty**, because the runner decides colour from `[[ -t 1 ]]` and it cannot be forced by an
environment variable. They were captured by running the harness under `script -q /dev/null`. Do not
delete them on the assumption that a rerun would reproduce them from a normal shell.

| File | What it establishes |
| --- | --- |
| `pr59-tally/hop-wt-tally-base.{color,nocolor}.txt` | The defect, before the fix. One suite under `HOP_T_TIMEOUT=5` prints 15 checkmark lines and reports `0 passed, 1 failed`. `base` is the tree at `origin/main`. |
| `pr59-tally/hop-wt-tally-reap.{color,nocolor}.txt` | The same run after the fix: 15 printed, `15 passed, 1 failed`. `reap` names the `fix/tally-reap-timeout` branch, not the fixture reap. |
| `baseline/full.hop-wt-tally-{base,reap}.txt` | Full-suite runs on both trees, **`579 passed, 0 failed, 7 skipped` on each**. The delta is zero because nothing approached the bound at loadavg ~5, so every suite emitted its sentinel and the new counting branch never ran. This is the negative check that the fix cannot double-count. |
| `tripwire/tw2.txt`, `tripwire/tw6.txt` | Fixtures for the counter's own tripwire: two marker lines at two-space indent, and one detail line at six-space indent. The counter must answer 2 for the first and 0 for the second, which is what distinguishes a working counter from one that always reports zero. |
| `harness/hop-proof59.sh` | Produced everything in `pr59-tally/`. Counts markers with its own `perl` rather than the runner's logic, so the check shares no mechanism with what it verifies. |
| `harness/hop-baseline.sh` | Produced everything in `baseline/` and `tripwire/`. Runs the tripwire first, then the two full suites. |

## Caveats

- **`sabotage.zsh` uses `pgrep -x fzf` and `pgrep -x zpty` for its leftover check.** That check is
  now known to be unreliable: the suite writes a stub executable literally named `fzf` onto `PATH`,
  so a name match cannot tell a stub from the real binary, and `zpty` is a zsh builtin whose child
  carries the spawned command's name rather than `zpty`. Resolve the executable path instead. The
  file is left as written; treat those two lines as a record of the era, not as a method to copy.
- **`realcanary.zsh` hardcodes `/private/tmp/hop-pristine`**, which no longer exists. It documents
  the experiment rather than being runnable as-is.
- **The pty flake ran at about 1 in 6, settled from the captures rather than from memory.** Four of
  the 25 runs in which `suite_pty_escape` completed failed it: 16%, 95% exact interval 4.5% to 36%,
  or 1 in 2.8 to 1 in 22. That interval contains the ~1-in-5 figure and excludes ~1-in-40, and it
  does so under every denominator worth arguing about (25, 30 or 31). The ~1-in-40 measurement
  belongs to the guard's own unit assertions at loadavg 44, a **different population**, so the two
  numbers were never in competition. Do not use this rate as a constant: see the load caveat below.
- **The FAIL column in `pty-flake/INDEX.txt` conflates three failure modes, so 9 of 30 is wrong.**
  Only 4 rows are the flake, each reporting `566 passed, 1 failed` with the single failure inside
  `suite_pty_escape`: runs 4, 12, 16 and 19. Three failed on "a long APC payload cannot outlast the
  guard" and one on "a real b still browses", which are the fork-timing and stub-log-race causes
  respectively, so both known causes appear. Runs 22 to 25 emitted **no tally at all**, run 26 shows
  `suite_pty_escape: suite did not finish (exit 142)` so the bound killed the suite before the flake
  could be observed, and run 31 shows exits 137 and 143, external kills. Those six cannot testify
  either way and are excluded from both numerator and denominator.
- **The rate is a function of load, not a constant, and this sample understates a loaded machine.**
  The guard compares against a 150ms threshold measured across its own fork, and fork latency climbs
  with load, so the flake is load-driven by construction. Run wall times climb 57s to 85s to 400s+
  across the loop, and all four flake hits sit in the *faster* half. The loaded runs did not flake,
  they got bound-killed, which **masked** the flake behind a louder failure. Treat 16% as a floor.
- **`pty-flake/INDEX.txt` disagrees with its own directory, and never recorded load.** It indexes
  `run-1` through `run-30` while the directory holds `run-001` through `run-031`, so **`run-031` is
  unindexed**; it is also the run with the external kills, consistent with the loop dying before it
  could write that row. The header says `runs requested: 45`, so 31 of 45 completed. Every row's
  `load=` field is **empty**, which is the one covariate that would have settled the paragraph above.
- **Both harness scripts hardcode `/private/tmp/hop-wt-tally-base` and
  `/private/tmp/hop-wt-tally-reap`**, the two worktrees they compared, which no longer exist. Point
  `tree` at any two checkouts to rerun them. They also write into `/private/tmp/hop-proof59-out`.
- **`hop-baseline.sh` reports its own wall time as `0.00s`**, because `EPOCHREALTIME` was unset in
  the shell that ran it. Every elapsed figure quoted above is the runner's own, which is sound
  because `tests/run` loads `zsh/datetime` itself. Ignore that column, do not trust it.
- All source directories lived under `/private/tmp`, which macOS reaps on an access-time clock and
  clears on reboot. That is why they are committed here.
