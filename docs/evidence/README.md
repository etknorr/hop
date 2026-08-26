# Investigation evidence

Preserved artifacts from three 0.1.x investigations. **Nothing here is part of the test suite, and
nothing here is run by CI.**

They are kept because they are the only record of what a mechanism *cannot* be. Re-deriving a
withdrawn finding is expensive, and several of these probes are what bound one.

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
| `exp3.zsh` | Models the real `_hop_pty_onexit` preamble faithfully (`_hop_t_report`, then `pty_reap_all`, which forks `ps -A`, only then `fixture_cleanup`) and measures how often the poll wins the race. **This is the artifact bearing on the still-open ~1-in-40 flake**, which exp1 could not explain because its trap went straight to cleanup and won every time. |
| `sabotage.zsh` | A sabotage matrix: each guard reverted in turn to prove the corresponding test fails when the thing it protects is removed. |
| `bound2.pl` | The `tests/run` process bound verbatim (fork, child `setpgrp`, parent alarm, `KILL` on the negative pid), for cases that must keep a controlling terminal where `setsid` would destroy the thing under test. |

## `pty-flake/`

A capture loop over the full suite on **unmodified `main` at `87be1ed`**, run under a strict
capture-not-reason protocol: every run's complete output is retained in its own file, pass or fail,
with the machine state appended to that same file so each artifact is self-contained. Task #46.

These exist because the flake's **rate** is the number that reframed #46 from archaeology to
something debuggable, and the rate is not recoverable from the files without the accounting below.

| File | What it establishes |
| --- | --- |
| `run-001.txt` to `run-031.txt` | One full-suite run each. Complete output, then a `### capture metadata` block with exit status, elapsed seconds, and `loadavg` before and after. A failing run also gets a `### failure snapshot`: the failing test names, five lines of context each, a process list, and the surviving fixture dirs. |
| `INDEX.txt` | One line per run, written as the loop went. **Its `load=` column is empty for every row**, a formatting bug in the loop (`${load_before%% *}` strips everything, because `sysctl -n vm.loadavg` returns a leading space). The real figure is in each run file and in the table below. |
| `flakeloop.zsh` | The loop itself, verbatim, so the protocol can be audited rather than described. Note its own bound is 400s, which is what invalidated four runs. |

### The accounting, which the files do not carry

**31 files, 26 valid runs, 5 failures.** Not 5 in 31.

- **Runs 22 to 25 are invalid**, killed by the **loop's own 400s bound**, not by the subject. Each
  has `exit: 142` and **no summary line at all**. The suite was running normally and slowly.
- **Run 31 is invalid**, killed by the `pkill` that stopped the loop at operator request. Its
  `exit 143` and `exit 137` on two suites are that signal, and its two `HOP_FZF_HEIGHT` failures are
  collateral of the kill rather than findings.
- The loop was stopped at 31 of a requested 45 because it had become a major contributor to the
  machine contention it was measuring.

**Failure distribution across the 26 valid runs**, all in `suite_pty_escape`:

| Failing test | Runs | Count |
| --- | --- | --- |
| `pty-esc: a long APC payload cannot outlast the guard` | 4, 16, 19 | 3 |
| `pty-esc: a real b still browses, so the negatives are not vacuous` | 12 | 1 |
| Four OSC negatives at once, plus `suite_pty_escape: suite did not finish (exit 142)` | 26 | 1 |

So **~1 in 5**, against the ~1-in-40 the task was filed with, and consistent with an independent
1-in-4 measured on the pty suite in isolation. Run 26 is also the only capture of the
multi-failure mode, and the only one where the suite itself hit its bound.

### What these files kill, and it is not what was expected

`loadavg` sampled before each run, against the outcome:

| Outcome | `loadavg` values |
| --- | --- |
| **Failed** | 3.25, 8.81, 9.30, 21.72, 85.79 |
| **Passed** | 3.42, 4.14, 4.29, 4.31, 4.40, 4.97, 5.36, 6.00, 6.19, 6.23, 6.32, 6.58, 6.63, 6.70, 8.54, 9.07, 16.34, 43.70, 92.38, 118.47, **142.90** |

**Run 12 failed at 3.25 and run 30 passed at 142.90.** The two distributions overlap across a 44x
range, so *which* run fails is not predicted by the load reading. Elapsed time does not separate
them either: run 29 passed in 485s at load 16.34 while run 30 passed in 70s at load 142.90.

**The likely reason the instrument fails, which matters more than the negative result.**
`loadavg` is a one-minute decaying average sampled *before* a run that then lasts 55 to 485
seconds. It describes the minute before the measurement window rather than the window itself, so it
cannot align with a phenomenon inside it. **Three separate agents obtained a negative load
correlation from variants of this instrument.** A negative result from a badly-timed metric is not
evidence that load is irrelevant, only that this sample cannot see it, and both agents who proposed
a load mechanism retracted on data of this shape.

The narrow claim these files do support: **a `loadavg` reading cannot predict which run fails, so
nothing should be calibrated against one.** The broader claim, that load does not set the failure
*rate*, is **not** supported, because every run here sits inside a contended regime. **Nobody has
sampled a quiet machine**, and that measurement was deliberately deferred rather than taken badly.

### What is not in here

**No stderr from the failing pty tests.** The harness records the recorded-verb value that the
assertion compares, not the child's stderr, so these files cannot answer whether a failing
`a real b` run printed `hop: not in a git repository`. That question needs
`suite_pty_escape` instrumented to retain stderr; it cannot be answered from this set.

## Caveats

- **`sabotage.zsh` uses `pgrep -x fzf` and `pgrep -x zpty` for its leftover check.** That check is
  now known to be unreliable: the suite writes a stub executable literally named `fzf` onto `PATH`,
  so a name match cannot tell a stub from the real binary, and `zpty` is a zsh builtin whose child
  carries the spawned command's name rather than `zpty`. Resolve the executable path instead. The
  file is left as written; treat those two lines as a record of the era, not as a method to copy.
- **`realcanary.zsh` hardcodes `/private/tmp/hop-pristine`**, which no longer exists. It documents
  the experiment rather than being runnable as-is.
- Both source directories lived under `/private/tmp`, which macOS reaps on an access-time clock and
  clears on reboot. That is why they are committed here.
