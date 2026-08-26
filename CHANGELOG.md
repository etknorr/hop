# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project adheres to
[Semantic Versioning][semver].

## [Unreleased]

### Added

- `hop --doctor=short`, a paste-safe diagnostic mode for public bug reports: it omits `PWD`, the
  git toplevel, workspace names and paths, and kind names, replacing them with counts, and shows
  a config path only when it still matches hop's shipped default.

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
