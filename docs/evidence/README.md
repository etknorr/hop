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

Those 31 runs are also the most likely way to settle the rate contradiction recorded under
Caveats, since they are an actual sampled population rather than a remembered figure. `INDEX.txt`
is the map of the loop that produced them.

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
- **Do not quote a failure rate for the pty flake: the surviving figures disagree.** This file
  previously called it "~1-in-40", which was wrong on both halves. The 1-in-40 measurement belongs
  to the guard's own unit assertions failing open at loadavg 44, a different population, and the
  entry recording it calls that *a higher rate than the pty flake*, while the flake was filed at
  about 1 in 5. Those cannot both hold. The causes in `b3dd791` are verified and the rate is not, so
  cite the causes.
- **Both harness scripts hardcode `/private/tmp/hop-wt-tally-base` and
  `/private/tmp/hop-wt-tally-reap`**, the two worktrees they compared, which no longer exist. Point
  `tree` at any two checkouts to rerun them. They also write into `/private/tmp/hop-proof59-out`.
- **`hop-baseline.sh` reports its own wall time as `0.00s`**, because `EPOCHREALTIME` was unset in
  the shell that ran it. Every elapsed figure quoted above is the runner's own, which is sound
  because `tests/run` loads `zsh/datetime` itself. Ignore that column, do not trust it.
- All source directories lived under `/private/tmp`, which macOS reaps on an access-time clock and
  clears on reboot. That is why they are committed here.
