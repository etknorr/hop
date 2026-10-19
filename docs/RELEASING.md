# Releasing hop

The steps to cut a release, in order. A tag push does the building and publishing; everything before
it is the release commit.

## Two names for one version

`VERSION` holds a bare semver, such as `1.0.0`, with no `v`. A checkout's `hop upgrade` reads it as
the installed version.

The git tag for the same release is `vX.Y.Z`, such as `v1.0.0`. goreleaser stamps the binary with
the tag minus its `v`, through `-X github.com/etknorr/hop/internal/version.Version`, so `hop -V`
prints `hop 1.0.0`. `Formula/hop.rb` names the tag too.

`release.yml` fails unless the tag is exactly `v` plus `VERSION` and `Formula/hop.rb` names that
tag, so all three move in the release commit.

## Steps

1. Start from a clean, up-to-date `main`:
   ```sh
   git checkout main
   git pull --ff-only
   ```

2. Decide the version with [Semantic Versioning](https://semver.org/). A breaking change to the
   config schema, the command line or an environment variable is major. A backward-compatible
   feature is minor. Anything else is a patch.

3. Bump `VERSION` to the bare number, one line:
   ```sh
   echo '1.1.0' > VERSION
   ```

4. Bump the formula's tag to match (drop the `''` after `-i` with GNU sed):
   ```sh
   sed -i '' 's/tag: "v[0-9.]*"/tag: "v1.1.0"/' Formula/hop.rb
   ```

5. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new dated heading, and leave
   `## [Unreleased]` in place above it, empty:
   ```markdown
   ## [Unreleased]

   ## [1.1.0] - 2026-11-01

   ### Added
   - ...
   ```
   Use today's date, `YYYY-MM-DD`. Add the link definitions for the new version at the bottom,
   beside the others, and repoint `[Unreleased]`:
   ```markdown
   [Unreleased]: https://github.com/etknorr/hop/compare/v1.1.0...HEAD
   [1.1.0]: https://github.com/etknorr/hop/compare/v1.0.0...v1.1.0
   ```
   The release workflow publishes this section as the GitHub release body, and fails when the
   section is missing or empty.

6. Check that it builds and passes. The snapshot builds the four archives into `dist/` and
   publishes nothing:
   ```sh
   go vet ./... && test -z "$(gofmt -l .)" && go test ./...
   go run github.com/goreleaser/goreleaser/v2@v2.18.3 release --snapshot --clean
   ```

7. Commit the release. One line, under 72 characters, no ticket reference:
   ```sh
   git add VERSION Formula/hop.rb CHANGELOG.md
   git commit -m 'release 1.1.0'
   ```

8. Tag it with the `v`, as an annotated tag whose message is `hop` plus the bare version:
   ```sh
   git tag -a v1.1.0 -m 'hop 1.1.0'
   ```

9. Push the commit, then the tag:
   ```sh
   git push
   git push origin v1.1.0
   ```

10. Watch the release workflow. The tag push runs `.github/workflows/release.yml`, which checks the
    tag against `VERSION` and the formula, builds darwin and linux archives for amd64 and arm64 with
    goreleaser, uploads them with `checksums.txt`, and uses the `CHANGELOG.md` section as the
    release notes. Its last job taps this repo on macOS and Linux, runs
    `brew install etknorr/hop/hop`, and checks that `hop -V` names the tag:
    ```sh
    gh run watch --repo etknorr/hop "$(gh run list --repo etknorr/hop --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
    ```

`go install github.com/etknorr/hop@v1.1.0` works as soon as the tag is pushed, since the Go module
proxy fetches tags from GitHub on demand.

## If the workflow fails

A failure before the goreleaser step publishes nothing. Fix the cause on `main`, delete the tag with
`git tag -d v1.1.0 && git push origin :refs/tags/v1.1.0`, then tag and push again. Once the release
exists on GitHub, or the module proxy has fetched the tag, don't move the tag. Cut the next patch
release instead, because the proxy keeps a tag's contents for good.
