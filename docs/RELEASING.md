# Releasing hop

The exact, ordered steps to cut a release. Follow them in order; nothing here is optional.

## Two names for one version, and why they differ

`VERSION` holds a **bare** semver, e.g. `0.1.0`, with no `v` prefix. `hop --version` reads it
verbatim, and anything that parses `VERSION` programmatically (`hop upgrade` compares its contents
against a target release) can treat it as a plain `X.Y.Z` string with no stripping required.

The git tag for the same release is `vX.Y.Z`, e.g. `v0.1.0`. The `v` prefix is the conventional
git tag spelling, and `git describe --tags` needs an actual tag to describe against — `hop
--version`'s `(describe)` suffix comes from that tag, not from `VERSION`.

Keep the two in sync (`VERSION` says `0.1.0` exactly when the tag is `v0.1.0`), but never write the
`v` into `VERSION`, and never drop it from the tag.

## Steps

1. **Start from a clean, up-to-date `main`.**
   ```zsh
   git checkout main
   git pull --ff-only
   ```

2. **Decide the new version number** using [Semantic Versioning](https://semver.org/): a breaking
   change to the `hop_kind` DSL, verbs, or environment variables is major; a backward-compatible
   feature is minor; anything else is a patch.

3. **Bump `VERSION`** to the bare number, no `v`, no trailing content beyond the one line:
   ```zsh
   echo '0.2.0' > VERSION
   ```

4. **Move the `## [Unreleased]` entries** in `CHANGELOG.md` under a new dated heading, and leave
   `## [Unreleased]` in place above it, empty, ready for the next round of changes:
   ```markdown
   ## [Unreleased]

   ## [0.2.0] - 2026-09-01

   ### Added
   - ...
   ```
   Use today's date, `YYYY-MM-DD`. Add the link-reference definitions for the new version at the
   bottom of the file, alongside the existing ones:
   ```markdown
   [Unreleased]: https://github.com/etknorr/hop/compare/v0.2.0...HEAD
   [0.2.0]: https://github.com/etknorr/hop/compare/v0.1.0...v0.2.0
   ```
   and repoint the previous version's `[Unreleased]` comparison, which is now superseded.

5. **Run the suite** and confirm it is still green:
   ```zsh
   tests/run
   ```

6. **Commit the release.** One line, under 72 characters, no ticket reference:
   ```zsh
   git add VERSION CHANGELOG.md
   git commit -m 'release 0.2.0'
   ```

7. **Tag it**, with the `v` prefix, as an annotated tag:
   ```zsh
   git tag -a v0.2.0 -m 'v0.2.0'
   ```

8. **Push the commit, then the tag:**
   ```zsh
   git push
   git push origin v0.2.0
   ```

9. **Create the GitHub release**, using the tag and the matching `CHANGELOG.md` section as the
   notes:
   ```zsh
   gh release create v0.2.0 --title v0.2.0 --notes-from-tag
   ```
   or paste the `## [0.2.0]` section body into `--notes-file` if `--notes-from-tag` picks up the
   annotated tag message instead of the changelog prose.
