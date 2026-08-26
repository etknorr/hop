# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project adheres to
[Semantic Versioning][semver].

## [Unreleased]

### Added

- `hop --doctor=short`, a paste-safe diagnostic mode for public bug reports: it omits `PWD`, the
  git toplevel, workspace names and paths, and kind names, replacing them with counts, and shows
  a config path only when it still matches hop's shipped default.
- `HOP_FZF_HEIGHT` sets the picker's height, defaulting to the previous hardcoded `80%`. An empty
  value drops `--height` entirely and gives fzf the whole screen.
- Repo governance for the now-public project: README badges (CI, MIT license, zsh), a
  `CONTRIBUTING.md`, GitHub issue and pull request templates, and a `.editorconfig` matching the
  project's real per-file indentation.
- `hop upgrade`, which moves a manual clone onto a release. Bare `hop upgrade` fast-forwards local
  `main` and stays on it, so `git pull` keeps working; `hop upgrade 0.1.0` pins to that tag,
  detached. `hop upgrade --check` reports installed versus released and changes nothing. It refuses
  rather than acts on a dirty tree, a side branch, a non-tag detached HEAD, a missing `origin`, a
  diverged `main`, or an untracked file the release also ships, and it never cleans, resets, merges
  or forces anything.
- A real install section in the README covering zinit, antidote, sheldon, oh-my-zsh and a manual
  clone, each shown both unpinned and pinned to a release tag.
- `hop.plugin.zsh`, the filename plugin managers look for, so `hop` needs no per-manager
  configuration. It sources `hop.zsh` and nothing else.

### Fixed

- The copy verb (`y`/`Y`, `ctrl-y`/`alt-y`) no longer hard-requires `pbcopy`: it now falls back to
  `wl-copy`, `xclip`, `xsel`, or `clip.exe`, so it works on Linux (Wayland or X11) and WSL, not just
  macOS. `HOP_CLIPBOARD` overrides the probe entirely for a custom clipboard command.
- `esc` out of a non-matching SEARCH query no longer lands you in NORMAL with a permanently empty
  list. `disable-search` only stops future matching, so nothing re-filtered; the mode transition now
  ends in `search()` to re-match, after `clear-query`.
- An fzf older than 0.60.3 is now refused with an explanation naming the version found, the version
  needed, and the upstream download, instead of failing as a bare `unknown option: --accept-nth`.
  `--accept-nth` arrived in fzf 0.60.0 and only worked alongside `--select-1` from 0.60.3, and the
  picker passes both. Debian and Ubuntu package 0.44.x. `HOP_FZF_MIN` overrides the floor, the
  version is read at most once per shell, and a version hop cannot parse proceeds rather than
  blocking.

## [0.1.0] - 2026-08-25

First release.

### Added

- `hop`, a modal, fzf-driven navigator for large configuration monorepos: enumerates deployable
  units instead of walking directories, and `cd`s to the one you meant.
- The `hop_kind` DSL for declaring a family of navigable things, in four shapes: `--dirs` (child
  directories of a base), `--files` (tracked files matching a pathspec), `--marker` (any directory
  containing a given file), and `--fn` (a hand-written provider for irregular families).
- Shipped presets covering common config-repo layouts: `terragrunt`, `terraform-modules`, `helm`,
  `serverless`, `puppet`, `backstage`, `dir` and `file`.
- A modal fzf UI in the style of `k9s` and vim: NORMAL mode where keys are verbs, `/` for SEARCH,
  and `:` to switch kinds in place without a nested fzf process.
- Workspaces: `-w`/`--workspaces` to pick a workspace root and drill into its repos, and `hopw` to
  `cd` to the workspace containing `$PWD`, deepest match winning.
- `hopr` to `cd` to the repo root, `hop -` for `cd -`, and the `^G`/`alt-g` widget to launch `hop`
  from a half-typed command line without losing it.
- `-c`/`--cwd`, `-k`/`--kinds`, `-a`/`--all` and `-R`/`--repos` to narrow or widen a search.
- `hop --doctor` and `HOP_DEBUG=1` for bug reports: install path, config, tool versions, workspace
  membership, live kind counts, and the last 15 dispatched keys.
- MIT license.

### Fixed

- `HOP_HOME` is now derived unconditionally from `hop.zsh`'s own path rather than inherited from
  the environment, so a stale exported value can no longer point a sourced shell at the wrong
  install.

[keepachangelog]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
[Unreleased]: https://github.com/etknorr/hop/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/etknorr/hop/releases/tag/v0.1.0
