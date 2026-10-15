# Deviations from SPEC.md

Each entry names the phase, what the spec says, what the build does, and why.

## Phase 1

1. **Preset location**: the spec's layout puts presets at `hopx/presets/*.toml`. They're at `hopx/internal/config/presets/*.toml`, because `//go:embed` can't reach a parent directory of the package that embeds them.
2. **Shared zsh files**: `import.zsh` is at `internal/importer/share/import.zsh`, and `compat.zsh` is at `internal/kinds/compat.zsh`, since the exec provider is what materialises it at runtime.
3. **Extra packages**: `internal/workspace` (the workspaces parser and repo discovery), `internal/collate` (zsh's sort order) and `internal/testfix` (the fixture repo builder) aren't in the spec's layout. The first is singular because the repo's `.gitignore` ignores any path named `workspaces`, and changing `.gitignore` is out of bounds for the spike.
4. **Row commands**: the spec names `hopx rows [-k kinds] [--root DIR] [--all]`. That exists, plus the hidden `hopx __rows <root> <kind...>` the phase task asked for, which is the form an fzf reload will call. `hopx rows -w` and `hopx rows -R` print workspace and repo rows until the phase 3 pickers exist.
5. **A literal preview candidate that is a directory**: the spec lists this as deliberately not matched. hopx matches it, using `-s` semantics as `_hop_dsl_preview` does, because the fixture showed the difference and byte parity is the gate. It's listed under "Found in hop" in `RESULTS.md`.
6. **Locale-dependent sort order and equal-width layout ties**: the spec lists both as deliberately not matched. hopx matches them through `internal/collate`, an approximation of macOS's en_US.UTF-8 collation, because Eric's repo rows came out in a different order without it (`identifiers` and `iPhone`). Layout ties use zsh's reverse `(O)` sort of the zero-padded key. Under `LANG=C`, zsh sorts bytewise and hopx still collates, so the two can differ there.
7. **Unknown keys are errors**: the prototype warned on an unknown top-level key or setting. hopx rejects every unknown key, at top level, in `[settings]` and in `[[kind]]`, with its line.
8. **`repo` isn't a builtin kind**: hop keeps the repo and ws providers out of `_HOP_ALL_KINDS`, so hopx does too, and the only builtins a `[[kind]]` can name are `dir` and `helm`.
9. **Pathspec magic**: `gitls` matches `:(glob)` and bare pathspecs in memory. Any other magic (`:(icase)`, `:(exclude)`) is an error rather than a second `git ls-files` call. No preset or Eric's config uses one.
10. **Named directories**: `_hop_rel` uses zsh's `${(D)p}`, which also abbreviates `hash -d` names. hopx only abbreviates `$HOME`. The parity harness runs `zsh -f`, where they agree.
11. **`-x` on a workspace**: `_hop_ws_parse` tests `-x`, which is `access(2)`. hopx checks the mode's execute bits, so an ACL or a root-owned dir can disagree.
