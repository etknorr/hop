# Investigation evidence

Preserved artifacts from two 0.1.x investigations. **Nothing here is part of the test suite, and
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
