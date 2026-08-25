# hop

A modal, fzf-driven navigator for large configuration monorepos.

`hop` answers one question fast: **which unit did I mean, and take me there.** In a repo with
hundreds of Terraform units, dozens of Helm charts and thousands of config files, `cd` plus
tab-completion is the wrong shape: the interesting unit is not "a directory" but "a deployable
thing", and those things sit at inconsistent depths. `hop` enumerates the things, not the tree.

```
vpc                     tg    payments             prod      us-east-1
vpc                     tg    payments             staging   us-east-1
web                     helm  kubernetes/values    -         -
alerting                mod   terraform/modules    -         -
```

It is a zsh function, not a binary, because the primary verb is `cd` and only the parent shell can
do that. Enumerating ~1,000 units takes about 0.4s, with no index, no daemon and no cache to
invalidate.

Scope note: this is a navigator only. It does not run terragrunt, helm or anything else. The most
it does besides `cd` is open an editor, copy a path, or open your git host.

Nothing in `hop` knows anything about your repo. Kinds are **declared** in your own config file, so
one install works across every repo you own. See [Configuring kinds](#configuring-kinds).

---

## Install

Requires `zsh` and [`fzf`](https://github.com/junegunn/fzf); `git` does the enumeration.
Optional: [`bat`](https://github.com/sharkdp/bat) for highlighted previews, `gh` for the browse
verb, and VS Code's `code` for the open verbs.

```zsh
git clone git@github.com:etknorr/hop.git ~/.local/share/hop
```

Add one line to `.zshrc`:

```zsh
source ~/.local/share/hop/hop.zsh
```

That is the whole install. `HOP_HOME` resolves to `hop.zsh`'s own directory, so the install can live
anywhere and be moved without editing anything.

**Completions** need `hop.zsh` sourced *before* `compinit`. `hop.zsh` adds `$HOP_HOME/completions`
to `fpath`, which only takes effect if `compinit` has not already run. If your `.zshrc` calls
`compinit` first, symlink into a directory already on `fpath` instead:

```zsh
ln -s ~/.local/share/hop/completions/_hop ~/.zfunc/_hop
```

With no config at all, `hop` loads every shipped preset and works immediately in any repo following
a common convention. To teach it your own layout:

```zsh
mkdir -p ~/.config/hop
cp ~/.local/share/hop/config.example.zsh ~/.config/hop/config.zsh
cp ~/.local/share/hop/workspaces.example ~/.config/hop/workspaces
```

---

## Commands

| Command | Does |
|---|---|
| `hop` | pick from the default kinds, starting in NORMAL mode |
| `hop vpc prod` | prefill the query; a single match jumps immediately with no UI |
| `hop /` or `hopr` | `cd` to the repo root |
| `hop -` | `cd -` |
| `hopw` | `cd` to the workspace containing `$PWD`, deepest match winning |
| `^G` or `alt-g` | open `hop` from a half-typed command line, which survives |

`^G` replaces zsh's `send-break`. Use `^C` to abandon a line, or rebind `hop-widget`.

### Flags

| Flag | Does |
|---|---|
| `-a`, `--all` | include every registered kind, not just the defaults |
| `-k`, `--kinds KIND[,KIND...]` | restrict to specific kinds |
| `-c`, `--cwd`, `--here` | only targets under `$PWD`, for any kind |
| `-R`, `--repos` | pick a repo instead of using the current one |
| `-w`, `--workspaces` | pick a workspace root; `l` drills into its repos |
| `--no-vim` | search-first fzf, no modal layer, same as `HOP_VIM=0` |
| `--vim` | force the modal layer on when `HOP_VIM=0` is set |
| `-h`, `--help` | usage, listing the kinds actually registered |

`-c` is the one to remember. `hop -c -k file pr` finds a file by name inside the subtree you are
standing in, instead of across the whole repo.

---

## Modal mode

`hop` starts in NORMAL mode, like `k9s` or vim: keys are verbs, not text. `/` enters SEARCH.

### Why a modal layer needs `ignore`

fzf's `--disabled` and `disable-search` stop *filtering*, but the query buffer still accepts
keystrokes — so a bare `--disabled` gives you a mode where typing looks broken rather than doing
nothing. A real NORMAL mode has to bind every printable character to `ignore` and `rebind` them on
entering SEARCH. That is what `_hop_vim_binds` generates, and why the keymap is ~99 binds.

fzf has no key-sequence support, so there is no `gg`. `g` alone is first, `G` is last.

### NORMAL

| Key | Does |
|---|---|
| `j` / `k` | move down / up |
| `g` / `G` | first / last row |
| `^d` / `^u` | half page down / up |
| `enter` | `cd` to the target |
| `l` / `h` | drill in a level / back out a level |
| `/` | enter SEARCH |
| `:` | open the kind menu in place |
| `o` / `O` | open the preview file / the directory in your editor |
| `e` | open the preview file in `$EDITOR` |
| `y` / `Y` | copy the directory / the file path |
| `b` | open the directory on your git host |
| `p` | toggle the preview pane |
| `r` | refresh the list |
| `?` | keymap overlay in the preview pane |
| `q` or `esc` | quit |

### SEARCH

Every printable key types. `esc` returns to NORMAL and clears the query.

| Key | Does |
|---|---|
| `enter` | `cd` to the target |
| `ctrl-o` / `ctrl-t` | open the file / the directory in your editor |
| `alt-o` | open the file in `$EDITOR` |
| `ctrl-y` / `alt-y` | copy the directory / the file path |
| `ctrl-g` | open on your git host |
| `alt-a` | reload with every registered kind |
| `ctrl-r` | refresh the preview |
| `alt-p` or `ctrl-/` | toggle the preview pane |

### The `:` kind menu

`:` switches which kinds are listed, **in place** — no nested fzf process. It reuses the single fzf
instance by reloading it with a menu and using `$FZF_PROMPT` as the mode flag. `enter` switches to
that kind; `esc` returns to exactly the list you came from, row count unchanged.

Menu counts are cached per repo *and* per `HEAD`, so a branch switch invalidates them for free. A
cache miss renders instantly without counts and warms in a detached subshell, so `:` never blocks on
a full sweep of every kind.

A kind with zero matches in the current repo is hidden from the menu entirely, which is what keeps
one shared config from cluttering unrelated repos.

### Escape hatch

`HOP_VIM=0` gives plain search-first fzf. Nothing about the modal layer is load-bearing for the
verbs, so this is a genuine fallback, not a degraded mode.

---

## Configuring kinds

A **kind** is one family of navigable things: Terragrunt units, Helm charts, services, tracked
files. Kinds are declared with `hop_kind` in `$HOP_CONFIG`, default `~/.config/hop/config.zsh`.
That file is sourced by your shell, so treat it like `.zshrc`.

```zsh
hop_preset terragrunt terraform-modules helm serverless puppet backstage dir file

hop_kind svc --default \
	--dirs 'services,platform/services' \
	--preview 'service.yaml,docs/runbook.md,README.md' \
	--desc 'application services'
```

Declaring anything replaces the load-every-preset default, so name the presets you want.
`config.example.zsh` is a working file covering everything below.

### The three shapes

Nearly every family in a config repo is one of three shapes.

**`--dirs BASE[,BASE...]`** — every child directory of each base is a target. The marker is
**directory existence**, never a particular file. `--depth 2` walks a `<namespace>/<name>` layout,
where one level would return only the containers.

**`--files PATHSPEC[,PATHSPEC...]`** — every tracked file matching the pathspec. The row's `cd`
target is the containing directory; the preview is the file itself.

**`--marker FILE`** — every directory holding that file. With `--under` and `--layout`, this is what
turns `terraform/<account>/<env>/<region>/<unit>/terragrunt.hcl` into columns.

**`--fn FUNCTION`** — the escape hatch. A family too irregular to declare gets a function and is
still a first-class kind, appearing in `--help`, the `:` menu and completions. The shipped `helm`
kind uses it, because that one kind spans four genuinely different directory shapes.

### Options

| Option | Meaning |
|---|---|
| `--desc TEXT` | one-line description in `--help` and the `:` menu |
| `--default` | include in the default kind set |
| `--dirs BASE,...` | shape 1: child directories of each base |
| `--depth N` | for `--dirs`: how many levels down a target sits (default 1) |
| `--files SPEC,...` | shape 2: tracked files matching these git pathspecs |
| `--marker FILE` | shape 3: a directory containing this file |
| `--under BASE` | restrict to this base, and strip it before reading segments |
| `--layout SPEC` | map path segments to columns; repeatable |
| `--name-template TPL` | compose the name from `{scope}`, `{env}`, `{region}` |
| `--name-fn FUNCTION` | derive the name from the file, e.g. a YAML `metadata.name` |
| `--strip-ext` | drop the file extension before applying the layout |
| `--exclude GLOB,...` | skip paths matching any of these |
| `--preview REL,...` | ordered preview fallback chain, relative to the target |
| `--preview-skip GLOB,...` | never preview a file matching these, e.g. generated code |
| `--scope-literal TEXT` | fill the scope column with a fixed string |
| `--trim COL:PREFIX,...` | strip a naming prefix off a column, for display only |
| `--fn FUNCTION` | shape 4: a hand-written provider |

Redeclaring a kind **replaces** it and keeps its position in the menu, which is how you adjust a
shipped preset without copying it wholesale.

### `--layout`, and why not a regex

`--layout` names path segments positionally, after `--under` is stripped. Columns are `scope`,
`env`, `region`, `name`, and `-` to discard a segment. A trailing `...` swallows every remaining
segment. `--layout` is repeatable and tried **longest first**:

```zsh
hop_kind tg --default \
	--marker 'terragrunt.hcl' --under 'terraform' \
	--layout 'scope,env,region,name...' \
	--layout 'scope,name...'
```

| path under `terraform/` | scope | env | region | name |
|---|---|---|---|---|
| `payments/prod/us-east-1/vpc` | `payments` | `prod` | `us-east-1` | `vpc` |
| `payments/policies` | `payments` | `-` | `-` | `policies` |
| `payments/prod/us-east-1/rbac/reader` | `payments` | `prod` | `us-east-1` | `rbac/reader` |
| `terragrunt_base` | *skipped* | | | |

The last two rows are the entire reason for this design. A single capture-group regex was tried
first and **got both wrong**: a greedy leading group mis-parses the nested unit, sliding `region`
into `rbac`, and it fails to match the shallow two-segment form at all. Segment indices handle every
depth correctly.

The skipped row matters as much. A shared include at depth 1 matches **no** layout, so it is
excluded with no content check and no hardcoded name. That is necessary, because such an include is
often byte-identical to a real unit.

### Preview chains

`--preview` is an ordered list of candidates relative to the target, first hit wins, falling back to
a directory listing. A candidate containing `*` or `?` is a glob expanded alphabetically, which is
how "the first real `.tf`" gets expressed:

```zsh
--preview 'main.tf,*.tf,terragrunt.hcl,README.md' \
--preview-skip 'provider_*.tf,variables_defaults.tf,versions_override.tf'
```

**Zero-byte files are never chosen.** Not hypothetical: real repos contain a 0-byte `main.tf` and a
0-byte `values.yaml`, and each rendered as a blank preview pane until this rule was made uniform
across every chain.

---

## Workspaces

A workspace is the level *above* a repo: a directory holding checkouts. Configure them in
`~/.config/hop/workspaces`, a plain list:

```
work      = ~/work/code
work-all  = ~/work
personal  = ~/src
```

`hop -w` lists them. `enter` cds to the workspace; `l` drills in and lists its repos. `hopw` jumps
to the workspace containing `$PWD`, **deepest match winning**, so nesting `~/work/code` inside
`~/work` behaves the way you meant.

The file is parsed, never `eval`'d — a backtick or `$(...)` in it is inert. A leading `~` and any
`$VAR` expand; a path that does not exist yet is skipped silently, so listing it early is fine.

With no workspace file, `hop` guesses the conventional locations (`~/src`, `~/code`, `~/projects`,
`~/dev`, `~/work`) and ignores the ones that do not exist.

---

## Data model

Every provider emits three TAB-separated fields:

```
<display>  \t  <dir>  \t  <preview_path>
```

`display` is pre-padded and ANSI-coloured in `_hop_row`, because fzf does not align `--with-nth`
fields. Padding is applied to the plain text *before* colouring, since `printf` counts an escape
sequence's bytes as width. `dir` is the `cd` target; `preview_path` is what the preview pane and the
file verbs act on.

The name column comes **first**. It is the only field distinguishing one row from another, and a
fixed 55-column prefix pushed it off-screen below about 160 columns. Putting it first also makes
`--tiebreak=begin` reward a name-prefix match instead of a kind-prefix match.

Verbs reach the shell through fzf's `--expect` and `print()+accept`: fzf prints the pressed key,
`_hop_parse_result` splits it from the `--accept-nth` fields, and `_hop_dispatch` runs the action
**in the parent shell**, which is what lets `enter` actually `cd`.

---

## Design notes

Five things shaped this design and are worth knowing before changing it.

### Git's bare `*` crosses `/`

In a git pathspec, `*` matches across directory separators, so `terraform/*/terragrunt.hcl` silently
sweeps in units four levels deep. Every pathspec needs the `:(glob)` magic prefix. `_hop_ls` adds it
to any spec lacking one, and it is the only function that talks to `git ls-files`, so nothing can
bypass the fix.

### A marker must be directory existence, not a file

Three separate times, keying a target off "the directory contains `X`" dropped real targets: a
service with no manifest is still a service. Presence of the *directory* is the marker, and a
preview *chain* absorbs the fact that different targets carry different files. A directory whose
only tracked file is `.gitkeep` counts as empty.

### Enumeration must not fork

Preview chains return through `REPLY`, never stdout. One `$(...)` per row cost more than everything
else in enumeration combined at ~1,000 rows. `_hop_entity_name` reads YAML with a bounded line scan
for the same reason: correct enough, and zero forks instead of one per file.

### `git ls-files -z`, always

One real repo tracks a path ending in a space and a backslash. `git ls-files` C-escape-quotes any
path containing a backslash or a non-ASCII byte, which breaks newline-splitting parsers. `-z` plus
zsh's `${(0)...}` never quotes and never splits inside a name.

### Exact matching, and frecency

fzf's default fuzzy matching bleeds across the columns: a 3-word query matched 13 rows where exact
matching matched exactly 1. `--exact` with `--tiebreak=begin,length` is what makes `hop vpc prod`
jump straight to a single target.

Previously-visited directories float to the top. fzf's final implicit tiebreak is input order, so
pre-sorting the input is the entire mechanism, with no scoring in the matcher. This matters because
a large repo can hold dozens of units all named `vpc`, and alphabetical order buries the one you use
every day.

---

## Files

```
hop.zsh                 entry point: hop, hopr, hopw, the ^G widget, config loading
lib/dsl.zsh             the hop_kind registry and the generic enumeration engine
lib/providers.zsh       row primitives, plus families too irregular to declare
lib/ui.zsh              the single fzf call and the whole modal keymap
lib/actions.zsh         the verbs: cd, open, edit, copy, browse, and frecency
lib/workspaces.zsh      workspace config parsing and lookup
presets/                shipped kind declarations, loaded with hop_preset
bin/hop-kinds           renders the `:` menu and reloads rows; never runs fzf
bin/hop-preview         the preview pane, and the `?` keymap overlay
completions/_hop        zsh completion, driven by the live registry
tests/run               the headless test suite
config.example.zsh      a working config to copy
workspaces.example      a workspace list to copy
```

`bin/hop-kinds` and `bin/hop-preview` are standalone executables because fzf runs `--preview` and
`reload()` in a fresh `$SHELL -c` that inherits no zsh functions.

---

## Environment

| Variable | Default | Does |
|---|---|---|
| `HOP_CONFIG` | `~/.config/hop/config.zsh` | your kind declarations |
| `HOP_DEFAULT_KINDS` | kinds declared `--default` | the default kind set |
| `HOP_WORKSPACES_FILE` | `~/.config/hop/workspaces` | workspace list |
| `HOP_WORKSPACES` | unset | colon-separated workspaces, overrides the file |
| `HOP_REPOS` | every repo in every workspace | colon-separated repo list for `-R` |
| `HOP_HISTFILE` | `~/.local/state/hop/history` | frecency history |
| `HOP_VIM` | `1` | `0` disables the modal layer |
| `HOP_HOPRC` | unset | `1` allows a repo-root `.hoprc` to run |
| `HOP_HOME` | derived from `hop.zsh` | install directory |

### `.hoprc` is opt-in

A repo-root `.hoprc` can declare extra kinds, but sourcing it runs arbitrary code from whatever repo
you happen to be standing in. Default-on meant `cd` into any clone plus one `hop` was a code
execution path, so it now requires `HOP_HOPRC=1`. Only enable it for repos you would already
`source` by hand.

### Degradations

Every dependency beyond `zsh`, `fzf` and `git` is optional and degrades to something that works: no
`bat` means plain `cat`; no `gh` means the browse verb explains why; no `code` means `$EDITOR`. A
kind whose families are absent from the current repo emits zero rows and **zero** stderr, which is
what lets one config work across every repo without noise.

---

## Tests

```zsh
tests/run
```

The suite is headless and hermetic: it builds synthetic fixture repos rather than reading your real
checkouts, and it stubs every external command so a test can never open an editor window or a
browser tab. Interactive fzf cannot be driven in a synthetic pty, so whatever genuinely needs a
terminal lives in `SMOKE.md` as a manual checklist.
