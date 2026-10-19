# hop

[![CI](https://img.shields.io/github/actions/workflow/status/etknorr/hop/ci.yml?branch=main&label=CI)](https://github.com/etknorr/hop/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/etknorr/hop?sort=semver&label=release)](https://github.com/etknorr/hop/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An fzf-driven navigator for big repos. `hop` lists the things you work on (projects, services, charts, units), not every directory, and takes you to the one you meant.

```
<root>                   dir   -   ./
src                      dir   -   src/
adservice                proj… src src/adservice/
cartservice              proj… src src/cartservice/
```

The zsh hop 0.3.1 README is `git show v0.3.1:README.md`.

## Install and shell setup

<!-- end: install -->

## Using the picker

<!-- end: picker -->

## Configuring kinds

A kind is one sort of target: a project, a terragrunt unit, a chart. Every row in the picker belongs to a kind, and `hop -k KIND` lists just that kind. The config is `$HOP_CONFIG`, else `~/.config/hop/config.toml`. [config.example.toml](config.example.toml) is a working config to copy.

### With no config

hop loads three recipes:

| Kind | Default | Rows |
|---|---|---|
| `dir` | yes | the repo root, as `<root>`, plus every top-level tracked dir except `target` and `tmp` |
| `project` | yes | every dir holding a build manifest, outermost only |
| `file` | no | every tracked file; `hop -k file` or `hop file NAME` lists them |

`project` looks for `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `setup.py`, `Gemfile`, `pom.xml`, `build.gradle`, `build.gradle.kts`, `composer.json`, `mix.exs`, `Package.swift`, `CMakeLists.txt`, `*.csproj`, `*.sln`, `Dockerfile` and `Makefile`. It skips the repo root, which `dir` already covers, and a match inside another match, so `packages/web/examples/demo` stays inside `packages/web`. It ignores hidden dirs and anything under `node_modules`, `vendor`, `third_party`, `testdata` or `fixtures`.

### Recipes

A recipe is a shipped set of kinds. Name the ones you want:

```toml
recipes = ["dir", "project", "file", "terragrunt", "helm"]
```

| Recipe | Kind | Default | Rows |
|---|---|---|---|
| `dir` | `dir` | yes | as above |
| `project` | `project` | yes | as above |
| `file` | `file` | no | as above |
| `terragrunt` | `tg` | yes | every dir below the root holding a `terragrunt.hcl` |
| `terraform-modules` | `mod` | yes | every outermost dir holding a `main.tf` or `variables.tf` |
| `helm` | `helm` | yes | every dir holding a `Chart.yaml`, subcharts included |
| `serverless` | `serverless` | no | every dir holding `serverless.yml`, `serverless.yaml`, `template.yaml` or `samconfig.toml` |
| `puppet` | `puppet` | no | every dir holding `manifests/init.pp` |
| `backstage` | `backstage` | no | every `catalog-info.yaml`, named by its `metadata.name` |

A config gets the zero-config three only when it names no recipes and declares no kind. Once it does either, it gets exactly what it names, so `recipes = []` with your own kinds means only your kinds. Recipes load in the order you list them, then your `[[kind]]` tables, and that's the order of the `:` menu.

### Writing a kind

```toml
[[kind]]
name = "svc"
desc = "application services"
default = true
dirs = ["services"]
preview = ["README.md"]
```

`name` is required and can't hold a comma or a space. `desc` shows in the `:` menu. `default = true` puts the kind in a bare `hop`'s list; `default_kinds` in `[settings]` (or `HOP_DEFAULT_KINDS`) overrides every kind's flag.

A kind has exactly one shape:

| Shape | A row is |
|---|---|
| `dirs = ["base", ...]` | each child dir of a base, `depth` levels down (default 1) |
| `files = ["pathspec", ...]` | each tracked file matching a git glob pathspec, with its dir as the cd target |
| `marker = "file"` or `marker = ["a", "b"]` | each dir holding any of the markers. A marker is a file name, a basename glob such as `*.csproj`, or a relative path such as `manifests/init.pp`, which puts the row on the dir holding `manifests/` |
| `builtin = "dir"` | the `dir` kind above |
| `exec = "command"` or `exec = ["argv", ...]` | each line the command prints, run in the repo root with `HOP_ROOT` set: `name TAB path [TAB preview [TAB scope [TAB env [TAB region]]]]`, paths relative to the root. A path naming a file makes a file target |

Every row has four columns, `scope`, `env`, `region` and `name`. With no `layout`, the name is the dir's (or file's) basename and the scope its parent path. These options shape the columns:

| Option | Shapes | What it does |
|---|---|---|
| `under = "dir"` | files, marker | strips this prefix before the layout; a marker kind only looks below it |
| `layout = ["scope,env,name...", "scope,name..."]` | files, marker | maps path segments to columns. `-` drops a segment, and a last column ending in `...` takes the rest. The longest layout that fits wins, and a path no layout fits isn't a row |
| `trim = { scope = "team-", env = ["env-", "e-"] }` | files, marker | strips prefixes from a column after the layout; it needs a `layout` |
| `name_template = "{scope}/{env}"` | files, marker | builds the name from the other columns, after `trim`; it needs a `layout` |
| `strip_ext = true` | files | drops the extension before the layout |
| `name_from = "yaml:metadata.name"` | files | names the row from the file's YAML `metadata.name` |
| `scope = "text"` | dirs, files, marker | sets the scope column on every row |
| `exclude = ["pattern", ...]` | files, marker | drops a file, or a marker file, whose repo path fits a zsh-style pattern. `*` crosses `/` here, and `(*/\|)x/*` matches `x/` at any depth, the root included |
| `min_depth = 1` | marker | drops matches fewer than this many dirs below `under` (or the root) |
| `nested = false` | marker | drops a match inside another match of the same kind or source |
| `skip = ["dir", ...]` | builtin dir | top-level dirs that aren't rows; default `["target", "tmp"]` |

A row's preview is the first `preview` candidate that exists and isn't empty, else the dir. Candidates are relative to the row's dir and may be globs (`*.tf`, `charts/*/Chart.yaml`), which expand alphabetically to regular files only. A candidate whose basename matches a `preview_skip` glob is passed over. `preview` works on dirs, marker, exec and builtin dir kinds; a files row previews its own file.

### Redeclaring and extending

A `[[kind]]` with a name that's already loaded replaces it and keeps its place in the `:` menu. Add `extend = true` to change only the keys you set:

```toml
recipes = ["dir", "project", "terragrunt"]

[[kind]]
name = "tg"
extend = true
under = "live"
layout = ["env,region,name...", "name..."]
```

### Sources

A kind can be built from several shapes. Each `[[kind.source]]` table holds one `dirs`, `files` or `marker` and its own options, and rows come out source by source. `name`, `desc` and `default` stay on the kind, and a kind with sources has no shape of its own.

```toml
[[kind]]
name = "deploy"
desc = "charts and app manifests"

  [[kind.source]]
  marker = "Chart.yaml"
  under = "deploy/charts"
  layout = ["name..."]
  scope = "charts"

  [[kind.source]]
  files = ["deploy/apps/**/*.yaml"]
  under = "deploy/apps"
  strip_ext = true
  layout = ["name..."]
  scope = "apps"
```

### Env colours

The env column is red for `prod`, yellow for `staging`, blue for `dev` and magenta for anything else. Add your own words per class:

```toml
[settings]
env_colors = { prod = ["prod", "production"], dev = ["dev", "sandbox"] }
```

A class you set replaces that class's words, so list the default word too, and a class you leave out keeps its default.

### Coming from zsh hop

`hop import` turns a zsh hop `config.zsh` into TOML that gives the same rows: every `hop_preset` is written out with 0.3.1's own definition, so later recipe changes don't move them.

```sh
hop import -o ~/.config/hop/config.toml
```

The source is `$HOP_CONFIG` when it ends in `.zsh`, else `~/.config/hop/config.zsh`. Without `-o` it prints to stdout, and an existing `-o` file needs `--force`. It needs zsh to read the file. An `--fn` kind other than `_hop_provider_dir` or `_hop_provider_helm` can't be imported; rewrite it as an `exec` kind. A repo's `.hoprc` isn't read any more, and `HOP_HOPRC` prints a warning.

Until you import, hop runs on the zero-config set and says `hop: found config.zsh; run 'hop import -o ~/.config/hop/config.toml' to use it`.

<!-- end: kinds -->

## Upgrading, releases and the environment

<!-- end: ops -->
