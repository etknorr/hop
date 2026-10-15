# What the hopx spike found

## The answer

Go if you want hop outside zsh. The spike rebuilt hop's core as one Go binary, hopx, that agrees with the installed hop 0.3.1 on every query tested against ~/strava/configuration, runs in zsh, bash, fish and PowerShell, and is about 6.5x faster end to end. Parity on macOS and Linux is about 11 engineer-weeks, so if zsh is the only shell you'll use, it isn't worth it.

## What the spike built

hopx lives under `spike/` on `spike/cross-shell`, next to hop, with its own shell function, config and history, so both run in one shell. It has config import from config.zsh to TOML, every kind, the resolver tiers and history ranking, the fzf picker without the modal layer, cd, open, reveal and copy, init scripts for four shells, and completion.

The verifier re-ran every check against hop 0.3.1 with your config:

- **End to end**: all 6,132 queries agree (2,044 under each of the three `HOP_JUMP` modes), including exit code, every byte of stderr and the remembered history.
- **Resolver**: all 13,797 queries agree under auto, unique and never.
- **Rows**: all 14 lists are byte-identical: the 11 kinds, default (1,042 rows), ws and repo. `file` alone is 12,046 rows.
- **By hand**: 18 new queries that appear in no set, and your nine headline cases, all match byte for byte.
- **Tests**: `go vet` is clean, and 338 tests in 17 packages pass, including the four that need the real repo.

It found one bug, a widget test that appended zsh history to a tracked file, fixed in 0d9a245.

## Parity with zsh hop

Not ported: the modal vim layer (hopx opens the kind menu with alt-k instead of `:`), the drill and up pickers (ctrl-l, ctrl-h), doctor and self-upgrade. Every hop release also has to be ported to hopx. The spike did that once, for the 0.2.0 to 0.3.1 changes, and the parity harness is what says a port is done.

## Speed

Medians of 11 runs on your repo. The machine was shared (load 3 to 6), so trust the ratios more than the milliseconds.

| measure | hop | hopx |
|---|---|---|
| default kinds, 1,042 rows | 374 ms | 43 ms |
| `file` kind, 12,046 rows | 1,955 ms | 63 ms |
| jump, `eks security` | 480 ms | 71 ms |
| `hop file aeraki.yaml` | 4,421 ms | 157 ms |
| literal path | 14.0 ms | 18.2 ms |

hopx is slower in two places, by a few milliseconds. A literal path is one, because hop handles it inside the shell and hopx starts a process. Paths into other repos typed from `~` are the other: 1.1x faster in one run, but 50.3 ms against 30.3 ms in another.

## Shells and platforms

| shell | pass | fail |
|---|---|---|
| zsh 5.9 | 31 | 0 |
| bash 5.3 | 31 | 0 |
| /bin/bash 3.2 | 31 | 0 |
| fish 3.7 (docker) | 33 | 0 |
| pwsh 7.5.3 (docker) | 32 | 0, plus 1 expected |

The expected pwsh failure is a backslash in a name on Unix. In every shell, `hopx security-tooling-prod` cd'd and completion listed the flags.

hopx cross-compiles for macOS, Linux and Windows on arm64 and amd64, at 3.3 to 3.9 MiB each with cgo off. The Windows binaries have never run, and linux/amd64 only ran under emulation with no fzf.

## What production needs

The modal layer and drill pickers, doctor and upgrade, hop's tests ported, the docker shell matrix in CI, and a release pipeline. Windows adds real Windows runs, a PSReadLine widget, and scoop or winget.

| option | engineer-weeks | at hop's agent-assisted pace |
|---|---|---|
| (a) parity, external fzf, macOS and Linux, zsh, bash and fish, brew | about 11 (8 to 13) | 6 to 7 |
| (b) (a) plus Windows and PowerShell | about 14 (11 to 17) | 7 to 9 |
| (c) (a) or (b) with fzf embedded as a library | about 0.5 more | about the same |

A custom picker instead of fzf would be about 17 weeks, and isn't worth it. The spike already passed the first milestone (enumeration, resolver and a green parity harness, about 3 weeks of the estimate), so what's left is known work, not discovery.

## Recommendation and next step

If you'd run hop in bash, fish or PowerShell, or hand it to teammates who don't use zsh, build (a) with fzf kept external. Keep zsh hop as the reference until hopx reaches parity, and leave Windows until after, since nothing has run there yet. If zsh is it, keep hop. Enumerating the default kinds takes 374 ms of hop's 480 ms jump, so that's where to speed hop up.

Next step: decide which shells you need. If it's a go, rebase `spike/cross-shell` onto main so every test compares against one hop version, then port the modal layer, because that's the gap you'd notice every day.
