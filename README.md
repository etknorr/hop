# hop

[![CI](https://img.shields.io/github/actions/workflow/status/etknorr/hop/ci.yml?branch=main&label=CI)](https://github.com/etknorr/hop/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/etknorr/hop?sort=semver&label=release)](https://github.com/etknorr/hop/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![shell: zsh](https://img.shields.io/badge/shell-zsh-89e051.svg)](https://www.zsh.org/)

A modal, fzf-driven navigator for large configuration monorepos.

`hop` answers one question fast: **which unit did I mean, and take me there.** In a repo with
hundreds of Terraform units, dozens of Helm charts and thousands of config files, `cd` plus
tab-completion is the wrong shape: the interesting unit is not "a directory" but "a deployable
thing", and those things sit at inconsistent depths. `hop` enumerates the things, not the tree.

```
vpc                     tg    payments             prod      us-east-1  terraform/payments/prod/us-east-1/vpc/
vpc                     tg    payments             staging   us-east-1  terraform/payments/staging/us-east-1/vpc/
web                     helm  kubernetes/values    -         -          kubernetes/values/web/
alerting                mod   terraform/modules    -         -          terraform/modules/alerting/
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

Requires `zsh` and [`fzf`](https://github.com/junegunn/fzf) **0.60.3 or newer**; `git` does the
enumeration. Optional: [`bat`](https://github.com/sharkdp/bat) for highlighted previews, `gh` for
the browse verb, and VS Code's `code` (or the CLI `HOP_CODE` names) for the open and reveal verbs.

That fzf floor is newer than what some distros package, and it is not arbitrary. The picker passes
`--accept-nth` together with `--select-1`: `--accept-nth` arrived in fzf 0.60.0 and only worked
alongside `--select-1` from 0.60.3. Debian and Ubuntu currently package 0.44.x, which rejects the
flag outright, so `apt install fzf` is not enough: install an
[upstream release](https://github.com/junegunn/fzf/releases). `hop` checks once per shell and says
so, rather than letting fzf fail with a bare `unknown option`.

A zsh plugin is always **a local checkout plus one line that sources it.** There is nothing to
compile and no binary to put on `$PATH`. What a plugin manager adds is bookkeeping: it does the
clone, it can pin you to a released version, and it updates everything with one command. If you
already use one, use it here. If you do not, the [manual clone](#manual-clone) is exactly what the
others do underneath, and [`hop upgrade`](#updating) covers pinning and updating yourself.

`hop` has to run **inside your interactive shell**, because its whole purpose is to `cd`. Anything
that runs it in a subprocess or a container cannot work, which is also why there is no Homebrew
formula and no container image.

Each recipe below is given twice. Unpinned follows the default branch and changes when it changes;
pinned sits on a release tag until you move it. Pinning is the better default for something you
launch from muscle memory.

### zinit

```zsh
# follows main
zinit light etknorr/hop

# pinned to a release
zinit ice ver'v0.1.0'
zinit light etknorr/hop
```

### antidote

In your plugin file, usually `~/.zsh_plugins.txt`:

```
# follows main
etknorr/hop

# pinned to a release
etknorr/hop branch:v0.1.0
```

The annotation is called `branch:`, but it is handed straight to `git clone`, so a tag pins fine.

### sheldon

In `~/.config/sheldon/plugins.toml`:

```toml
# follows main
[plugins.hop]
github = "etknorr/hop"

# pinned to a release
[plugins.hop]
github = "etknorr/hop"
tag = "v0.1.0"
```

Then `sheldon lock --update`.

### oh-my-zsh

Oh-my-zsh has no fetcher, so the clone into its custom plugins directory is yours to make:

```zsh
# follows main
git clone https://github.com/etknorr/hop.git \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/hop"

# pinned to a release
git clone --branch v0.1.0 https://github.com/etknorr/hop.git \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/hop"
```

Then add it to the list in `.zshrc`, **before** `source $ZSH/oh-my-zsh.sh`:

```zsh
plugins=(git hop)
```

### Manual clone

No manager, one line of `.zshrc`, and nothing between you and the checkout:

```zsh
# follows main
git clone https://github.com/etknorr/hop.git ~/.local/share/hop

# pinned to a release
git clone --branch v0.1.0 https://github.com/etknorr/hop.git ~/.local/share/hop
```

```zsh
source ~/.local/share/hop/hop.zsh
```

`HOP_HOME` resolves to `hop.zsh`'s own directory, so the checkout can live anywhere and be moved
without editing anything. `hop.plugin.zsh` sits alongside it purely because that is the filename
plugin managers look for; both do the same thing.

### Updating

A manager owns the checkouts it made, so update there: `zinit update etknorr/hop`,
`antidote update`, `sheldon lock --update`, or re-clone the oh-my-zsh directory. Bump the pinned
version in your config first if you set one.

A manual clone updates itself:

```zsh
hop upgrade --check     # what is installed vs what is released; changes nothing
hop upgrade             # fast-forward main to the newest release, staying on main
hop upgrade 0.1.0       # pin to exactly that release, detached
exec zsh                # reload; a sourced function cannot replace itself mid-call
```

The two forms land in different places on purpose. Bare `hop upgrade` fast-forwards your local
`main`, so `git pull` and the next `hop upgrade` both keep working. Naming a version is a **pin**,
which detaches `HEAD` at that tag; a bare `hop upgrade` brings you back to `main`, saying so as it
goes.

Between releases, `main` is normally *ahead* of the newest tag. `hop upgrade` reports that as up to
date rather than moving you backwards onto the tag.

`hop upgrade` refuses rather than acts when the checkout is dirty, sits on a branch other than
`main`, is detached somewhere that is not a release tag, has no `origin` remote, or has a `main`
that has diverged from the release. It never runs `git clean`, never hard-resets, never merges and
never forces anything: `main` only ever moves by fast-forward. Untracked files are never touched.
If one sits where the new release ships a file, that is a refusal too.

`--check` never touches your worktree or `HEAD`. It does fetch tags, so it writes refs under `.git`.

### Completions

Completions need `hop.zsh` sourced *before* `compinit`. `hop.zsh` adds `$HOP_HOME/completions` to
`fpath`, which only takes effect if `compinit` has not already run. Most managers handle this. If
your `.zshrc` calls `compinit` first, symlink into a directory already on `fpath` instead:

```zsh
ln -s ~/.local/share/hop/completions/_hop ~/.zfunc/_hop
```

### Configuring it

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
| `hop vpc prod` | a clear match jumps with no UI; otherwise the picker opens on the best matches first. See [How a query resolves](#how-a-query-resolves) |
| `hop terraform/acct-x` | a path that exists jumps straight there, before any matching, even from outside its repo when only one repo has it, or only one of that repo's checkouts is on its default branch |
| `hop /` or `hopr` | `cd` to the repo root |
| `hop -` | `cd -` |
| `hopw` | `cd` to the workspace containing `$PWD`, deepest match winning |
| `hop upgrade` | move a manual clone to the newest release; see [Updating](#updating) |
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
| `-p`, `--pick` | always open the picker, even for a clear match; `HOP_JUMP=never` for one call |
| `-o`, `--open` | Enter opens the target in VS Code instead of `cd`-ing |
| `-e`, `--reveal` | Enter shows the target in VS Code's explorer instead of `cd`-ing |
| `--cd` | Enter `cd`s first; with `-o` or `-e` it then opens or reveals |
| `--action=MODE` | Enter does MODE, one of the `HOP_ACTION` values below |
| `--no-vim` | search-first fzf, no modal layer, same as `HOP_VIM=0` |
| `--vim` | force the modal layer on when `HOP_VIM=0` is set |
| `--doctor` | dump config, tools and kind counts for a bug report |
| `--doctor=short` | the same, minus paths and names; safe to paste publicly |
| `-V`, `--version` | print the installed version |
| `-h`, `--help` | usage, listing the kinds actually registered |

`-c` is the one to remember. `hop -c -k file pr` finds a file by name inside the subtree you are
standing in, instead of across the whole repo.

### What Enter does

Enter, a direct jump and a headless jump all do the same thing, and `HOP_ACTION` decides what:

| Mode | A file target | A directory target |
|---|---|---|
| `cd` (default) | `cd` to its directory | `cd` to it |
| `open` | `code -r <file>` | `code -n <dir>`, a window on that folder |
| `reveal` | `code -r <file>` | `code -r` on the row's preview file; when the preview is the directory itself, on a top-level README, else the first file by name |
| `cd+open`, `cd+reveal` | `cd` first, then as above | `cd` first, then as above |

The flags replace `HOP_ACTION` for one call. `-o` and `-e` are exclusive, `--cd -o` is `cd+open`,
and `--action=MODE` can't be combined with `--cd`, `-o` or `-e`; each of those is an exit 2. A
workspace or repo row is a whole folder, so `open` and `reveal` both mean `code -n` on it.

`code -r` never gets a directory. `code -r <dir>` reloads the focused window onto that folder,
which replaces whatever you had open. VS Code also has no command that reveals a folder, which is
why `reveal` on a directory reveals a file inside it. When the top of a directory holds no file at
all, as `kubernetes/values/` doesn't, hop says so and suggests `-o`.

`hop /`, `hop -`, `hopr` and `hopw` always `cd`, whatever `HOP_ACTION` says, because they navigate
by name rather than pick a target. Inside the picker, `c` (NORMAL) and `alt-enter` (SEARCH) always
`cd` too, so the plain `cd` stays one key away when Enter does something else. In the `:` view
menu they do nothing, because a menu row names a view, not a directory.

---

## Modal mode

`hop` starts in NORMAL mode, like `k9s` or vim: keys are verbs, not text. `/` enters SEARCH.

### Why a modal layer needs `ignore`

fzf's `--disabled` and `disable-search` stop *filtering*, but the query buffer still accepts
keystrokes, so a bare `--disabled` gives you a mode where typing looks broken rather than doing
nothing. A real NORMAL mode has to bind every printable character to `ignore` and `rebind` them on
entering SEARCH. That is what `_hop_vim_binds` generates, and why the keymap is ~99 binds.

fzf has no key-sequence support, so there is no `gg`. `g` alone is first, `G` is last.

### NORMAL

| Key | Does |
|---|---|
| `j` / `k` | move down / up |
| `g` / `G` | first / last row |
| `^d` / `^u` | half page down / up |
| `enter` | the Enter action: `cd` by default, see [What Enter does](#what-enter-does) |
| `c` | `cd` to the target, whatever Enter does |
| `l` / `h` | drill in a level / back out a level |
| `/` | enter SEARCH |
| `:` | open the kind menu in place |
| `o` / `O` | open the preview in VS Code (`code -r`, or `code -n` for a directory) / the directory in a new VS Code window |
| `e` | open the preview file in `$EDITOR` |
| `y` / `Y` | copy the directory / the file path |
| `b` | open the directory on your git host |
| `p` | toggle the preview pane |
| `r` | refresh the list |
| `?` | keymap overlay in the preview pane |
| `esc` | clear the query, or quit when it is already empty |
| `q` | quit |

Five of those depend on which picker you are in. `r` needs a list it can regenerate, `:` needs a repo
root to enumerate kinds from, `l` needs somewhere to drill into, `h` needs a level to go back out to,
and `alt-a` needs a reload command. The repo picker (`hop -R`) has only `h` and the workspace picker
(`hop -w`) has only `l`. Where a key is not bound, the legend and the `?` overlay both leave it out
rather than name a key that does nothing.

### SEARCH

Every printable key types. `esc` returns to NORMAL and keeps the query, so the list stays filtered
and `j`/`k` and every NORMAL verb work on the rows it matched. A second `esc` clears the query and
brings the full list back, and a third quits. `/` goes back to SEARCH with the query still there to
edit.

| Key | Does |
|---|---|
| `enter` | the Enter action: `cd` by default |
| `alt-enter` | `cd` to the target, whatever Enter does |
| `ctrl-o` / `ctrl-t` | open the preview in VS Code / the directory in a new VS Code window |
| `alt-o` | open the file in `$EDITOR` |
| `ctrl-y` / `alt-y` | copy the directory / the file path |
| `alt-B` | open on your git host |
| `alt-a` | reload with every registered kind |
| `ctrl-r` | refresh the preview |
| `alt-p` or `ctrl-/` | toggle the preview pane |

The legends and the `?` overlay name what Enter does in this call, such as `enter cd+reveal`. They
list `c cd` and `M-enter cd` only when Enter isn't plain `cd`, so the default legend is unchanged.

### The escape guard

NORMAL mode makes letters into verbs, and that creates a problem no keymap can fix on its own: fzf
cannot decode every escape sequence that arrives on its input, and the ones it cannot parse are
delivered as ordinary keystrokes. A terminal answering a background-colour query with
`\e]11;rgb:1e1e/1e1e/1e1e\e\\` therefore types `11;rgb:1e1e/1e1e/1e1e` into the picker, and the `b`
in `rgb` used to run `gh browse`. Nobody touched a key. An `\e]52;...` clipboard reply reached the
copy verb through its `Y`, and a `\eP...` version reply reached `$EDITOR` through its `e`.

fzf does surface the part it could not parse: an unrecognised `ESC <char>` becomes a bindable
`alt-<char>`, so `\e]` arrives as `alt-]`. hop binds every such key to a stamp of the clock, and
every verb that would leave the picker checks that stamp before it runs. A forged letter follows its
introducer by about 20 milliseconds, which is the cost of the check itself. A real keypress follows
whatever the user did last by however long they took. `HOP_GUARD_WINDOW` is where that line sits.

The guard fails open by design. With no clock, no stamp or a malformed window it runs the verb,
because swallowing a real keypress is worse than the nuisance it prevents. `HOP_GUARD_WINDOW=0`
turns it off entirely.

Navigation keys are deliberately outside it. `j`, `k`, `g` and `G` must not fork a process on every
cursor move, and `/` and `:` are both undone by `esc`. So a hostile sequence can still scroll the
list or switch mode. It cannot open an editor, write your clipboard or open a browser tab.

Three gaps remain, all nuisance-level and all deliberate for now.

A **bracketed paste** wraps its payload in `\e[200~` and `\e[201~`, which are well-formed CSI
sequences that fzf parses and discards, so there is no introducer left to hook. It also takes a
deliberate paste to trigger.

`\b` and `\f`, if a program prints them raw, still read as `ctrl-h` and `ctrl-l`, which are `--expect`
keys rather than binds. `--expect` outranks every bind and so cannot be guarded. Both are in-picker
level navigation; moving the remaining `--expect` keys onto guarded binds is queued for 0.2.0.

**The guard does not cover the bare control bytes, and it structurally cannot.** It works by hooking
the `alt-<char>` that an unparsed escape *introducer* produces. `\a`, `\b` and `\f` carry no
introducer, so there is nothing to hook and no mark is ever written. Binding the key to `ignore` and
relocating the verb, which is what `ctrl-g` got, is the only remedy that class has. The remaining two
are deliberately not getting it in a patch release: relocating two documented keybindings is a worse
trade than a recoverable change of list position.

A **bare `ESC` byte** still closes the picker, because `esc` in NORMAL with an empty query means
quit and that is the documented binding; with a query it clears the query instead. Measured on an
empty query: a lone `\e` or `\e\e` aborts, while a `\e` arriving at the tail of a truncated sequence
does whatever `esc` means in the mode it lands in. `esc` is deliberately *not*
guarded, and that is a safety property rather than an oversight: if `bin/hop-guard` were ever missing
or lost its executable bit, a `transform:` yields no output, fzf treats that as no action, and all
ten guarded keys go dead at once. `esc` is then the only way out of the picker.

### The `:` kind menu

`:` switches which kinds are listed, **in place**, with no nested fzf process. It reuses the single
fzf instance by reloading it with a menu and using `$FZF_PROMPT` as the mode flag. `enter` switches
to that kind; `esc` returns to exactly the list you came from, row count unchanged. `:` drops a
query kept from SEARCH, because it would filter the kind list too, so that list comes back unfiltered.

Menu counts are cached per repo, per `HEAD`, *and* per the index's own state, so a commit, a branch
switch and a bare `git add` all invalidate them for free. The index has to be in the key because
enumeration reads it rather than `HEAD`'s tree, so staging a file changes the counts while `HEAD`
stands still. A cache miss renders instantly without counts and warms in a detached subshell, so `:`
never blocks on a full sweep of every kind.

A kind with zero matches in the current repo is hidden from the menu entirely, which is what keeps
one shared config from cluttering unrelated repos.

Every reload builds its rows the way the first list was built: `alt-a`, `r`, `esc` out of the menu
and switching to a kind all keep `-c`'s subtree and the visited-first order. Two things don't
survive a reload: the directory rows a query added (see
[How a query resolves](#how-a-query-resolves)), and the best-first order the picker opened with.

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

**`--dirs BASE[,BASE...]`**: every child directory of each base is a target. The marker is
**directory existence**, never a particular file. `--depth 2` walks a `<namespace>/<name>` layout,
where one level would return only the containers.

**`--files PATHSPEC[,PATHSPEC...]`**: every tracked file matching the pathspec. The row's `cd`
target is the containing directory; the preview is the file itself.

**`--marker FILE`**: every directory holding that file. With `--under` and `--layout`, this is what
turns `terraform/<account>/<env>/<region>/<unit>/terragrunt.hcl` into columns.

**`--fn FUNCTION`**: the escape hatch. A family too irregular to declare gets a function and is
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

The file is parsed, never `eval`'d, so a backtick or `$(...)` in it is inert. A leading `~` and any
`$VAR` expand; a path that does not exist yet is skipped silently, so listing it early is fine.

With no workspace file, `hop` guesses the conventional locations (`~/src`, `~/code`, `~/projects`,
`~/dev`, `~/work`) and ignores the ones that do not exist.

---

## Data model

Every provider emits four TAB-separated fields:

```
<display>  \t  <dir>  \t  <preview_path>  \t  <rel>
```

`display` is padded and ANSI-coloured by hop, because fzf does not align `--with-nth` fields. Each
list is laid out as a whole, so the kind, scope, env, region and path columns start at the same
column on every row. A column is as wide as the longest value in that list, up to a cap, and the
name column is between 20 and 56 characters wide. A scope, env or region column that's `-` on every
row is left out, so a repo row shows only its name and kind before the path. `dir` is the `cd`
target; `preview_path` is what the preview pane and the file verbs act on.

A name longer than 56 keeps its start and its end around a `…`. Most names come from the path, and
`rel` holds the whole path, so a query still matches the part that's cut. A name that isn't in the
path, such as a workspace name set with `name = path` or one that `--name-fn` reads from a file,
can't be matched on its cut part.

`rel` is the target's path relative to the repo root, dimmed, and it's the only path fzf searches.
The absolute `dir` is never searched, so your home directory or a temp-dir suffix can't match a
query. The trailing `/` is what marks a directory target:

| Target | `rel` |
|---|---|
| a directory | `terraform/acct-security-tooling-prod/env-prod/` |
| a file | `kubernetes/services/monitoring/grafana.yaml` |
| the repo root | `./` |
| a workspace or repo row | `~/work/code/` |

`_hop_row <kind> <scope> <env> <region> <name> <dir> <preview> [f]` builds every field, `rel`
included, from the root `_hop_generate` is running for. The optional 8th argument `f` makes the
row a file target: the preview is the destination, and `dir` is only its parent. Inside
`_hop_generate`, `_hop_row` leaves the display unpadded, and hop pads the whole list once it has
every row, so a `--fn` provider's rows line up with every other kind's. A row whose display the
provider prints itself, without `_hop_row`, is shown as printed and won't line up. A `--fn`
provider written before `rel` existed still works. Its 3-field rows get a `rel` derived from
`dir`, so they always count as directory targets, and `hop --doctor` names the kind so you can
move it to `_hop_row`.

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

### How a query resolves

`hop <words>` decides what you meant before any picker opens. It tries these steps in order and
stops at the first one that finds something:

1. **Literal path**: one word that holds a `/`, starts with `~`, `./` or `../`, or is a bare `.` or
   `..`, and names a real directory or file jumps there before anything is enumerated, in about a
   millisecond. `hop -o .` opens the directory you're in. The match ignores case and lands on the
   on-disk spelling, so `hop Terraform/ACCT-x` cds to `terraform/acct-x`. `./x` and `../x` are
   relative to `$PWD`, `/x` is relative to the repo root first (as `hop /` is), and anything else
   tries `$PWD` and then the root. `-k` doesn't narrow it, since no kind is consulted, and `-w`,
   `-R` and `-p` skip it.

   A path that isn't under `$PWD` or the repo root is looked up in every repo hop knows
   (`$HOP_REPOS`, or every repo in your workspaces), with or without the repo's name in front, and
   under every workspace root. It ignores case the same way. So from `~`, both
   `hop terraform/acct-x` and `hop configuration/terraform/acct-x` land in `configuration`, as long
   as no other repo has the same path. One match jumps and prints where it was found:
   `hop: terraform/acct-x -> ~/work/configuration/terraform/acct-x/ (found in configuration)`.

   Two or more jump only when every one is a checkout of the same origin repo and exactly one of
   them is checked out on its default branch. Origins are compared by `remote.origin.url` with the
   scheme, the user and a trailing `.git` dropped, ignoring case, so `git@github.com:org/repo` and
   `https://github.com/org/repo.git` count as one. The default branch is what `origin/HEAD` names,
   else `main` if the repo has it, else `master` if it has that, and a detached HEAD isn't on any
   branch. So when a clone, a retired copy and two worktrees of `configuration` hold the path and
   only one of them is on `main`, hop lands there, and the note says why:
   `(found in configuration, the main checkout of 4)`. hop reads this from each checkout's own git
   files rather than running `git`, so it costs a few milliseconds. `HOP_JUMP=unique` turns this
   rule off, since there the path names more than one target. Otherwise the picker opens on
   just those, the repo you visited most recently first, then by path.

   Inside a repo, other repos are tried only when the repo has nothing close to the query, so
   a match or a typo pick in the repo you're in still wins. The lookup needs a `/` with a name
   after it, so `hop configuration/` is still matched like any other query. It skips paths
   starting with `./`, `../`, `/` or `~` and paths with a `.` or `..` segment, and it's off under
   `-c`, which keeps the search under `$PWD`. It only checks whether the path exists in each repo,
   so it lists no repo's targets and costs a few milliseconds.
2. **Exact**: fzf matches the words against the row's name line (name, kind, scope, env and
   region) and its `rel` path, with `--exact`, `-i` and `--tiebreak=begin,chunk`. The picker gets
   the same flags from the same array, so the two always agree on which rows match. Your
   `FZF_DEFAULT_OPTS` and any `fzf` alias never reach this step, so a default such as `--no-sort`
   or `--nth=1` can't change what jumps, and the picker resets `--nth`, `--tac` and `--scheme`, the
   defaults that would change which rows match or their order.
3. **Rewrite**: a word that no path contains is fixed against the words the paths do contain: one
   typo from 4 letters, two from 8, or an abbreviation from 6. `routemaxter` reads as
   `routemaster`. A word the paths already hold is abbreviated only when nothing matched without
   that, so `terraform/account-security` reads as `terraform account | acct security`, while
   `routemaster-prod` stays `routemaster prod` instead of gaining `raster`. A word run together
   from two or three path words is split back into them, so `externaldns` reads as `external dns`,
   and a short env word no path holds reads as its long form: `prd` as `prod`, `stg` as `staging`.
   If one word can't be explained, this step finds nothing, so a nonsense word is never turned
   into a match.
4. **Loose**: initials, or the letters in order within one path segment, starting with its first
   letter: `kps` and `kubeprom` both find `kube-prometheus-stack`.
5. **Relaxed**: with two or more words, each word is read on its own by whichever step above finds
   it, the ones nothing reads are dropped, and the picker's header says so: `ignored: zzqx`. When
   every word matches alone but no row holds them all, the picker shows the rows that hold all but
   one, smallest set first, and the header says `ignored: one of: routemaster, dev`.
6. **Nothing close**: the picker opens on your query with no rows, ready to edit.

Before any of these, a first word that names a registered kind outside your default set is read
as `-k` when no default target matches it, not even as a typo fix or a loose match. So with `file`
not a default kind, `hop file aeraki.yaml` is `hop -k file aeraki.yaml`, and hop prints
`hop: reading "file" as -k file`. `hop file` alone opens the picker on that kind, even when it
holds one target. A default kind such as `tg`, a kind name after the first word, and a word some
default target matches all stay plain words, so `hop puppet` in a repo with a top-level `puppet/`
still goes to that dir. Nothing is read as `-k` when you pass `-k` or `-a`. With `-w`, `-R` or
outside a repo it's read the same way, and since those levels ignore `-k`, the word is only
dropped from the query. When it fires in a repo, the default kinds are listed once to check the
word, and with no terminal a rest that matches nothing is reported as
`nothing matched the query: zzqx with -k file`.

#### Jump rules

Whether a query jumps is decided by the rules below, never by a score, because fzf doesn't expose
one. Only a literal path, an exact match, or a rewrite that changed nothing but separators or case
(`security_tooling_prod`) may jump. A typo fix or a loose match always opens the picker, best match
first, because a typo costs you one Enter and a false jump costs a wrong `cd` or a wrong VS Code
window. An exact match jumps when one of these holds, checked in this order:

| Rule | When | Example |
|---|---|---|
| J1 | exactly one target matches | `eks security` |
| J1b | every match is in one directory, and Enter is plain `cd` | `monitoring/grafana`, whose files all sit in `kubernetes/services/monitoring/` |
| J3 | exactly one row matches on its name line alone, and no other match's name line is clipped with `…` | `disaster-recovery prod` |
| J0 | at the workspace and repo levels only: one word, and exactly one target's name is that word | `configuration` from `~`, past `configuration.retired-2026-09-14` |
| J2 | every match is under one directory, the words name that directory on whole-word boundaries, and none of them is a kind name | `security-tooling-prod` jumps to `terraform/acct-security-tooling-prod/` |

The name line is all hop searched before paths were added, so a query that jumped before still
jumps, unless another match's name line is clipped.

J2 prints one line saying why it jumped, such as
`hop: security-tooling-prod -> terraform/acct-security-tooling-prod/ (all 3 matches are under it)`,
and J0 names what it skipped: `hop: configuration -> ~/work/code/configuration/ (exact name; 3
others contain it)`. A jump on a rewrite of separators says how it read the words, as
`hop: routemaster-prod -> ... (read as: routemaster prod)`.
`kub` doesn't jump to `kubernetes/`, because a prefix isn't a whole word, and `tg vpc` doesn't jump
by J2, because `tg` names a whole family. Under any mode but plain `cd`, `cd+reveal` included, J1b
doesn't collapse the files in one directory, because each file is a target of its own.

An account or env directory is not a row of any kind, but it still shows up when your query names
it: hop adds it as a row only when it matches the same query, and J2 is the only rule that jumps to
one. A query using fzf's own syntax (`'`, `^`, `$`, `!` or `|`) gets the exact step alone, with no
rewrite and no added rows.

Outside a repo, a path is looked up in your repos and workspace roots first, as step 1 describes.
Any other query is resolved against your workspaces, and when none matches exactly hop tries your
repos too and keeps the closer result, a tie going to the workspaces. So `hop tf eks` from `~`
lands on `tf-aws-eks` instead of a workspace that only matched `tf`.

`HOP_JUMP` sets how eager this is. `auto` allows every rule above. `unique` allows literal paths,
J1, J1b and J3, so a query jumps only when it names one target. `never` always opens the picker,
and `-p` is `never` for one call.

#### The picker

When a query opens the picker, the closest matches come first: `acct sec prod` lists the account
directory and then its units. The first key you type hands the order back to fzf. The header's
first line says when the query was rewritten, for example
`no exact match for: securty-tooling-prod (showing: security tooling prod)`, or
`(read as: prod vpc)` for `prod_vpc`, whose words were only split apart. Typing in the picker is
plain fzf: it searches the paths, but it doesn't correct typos. With no terminal, a pick can't be
shown, so hop prints how many targets matched, the best three paths, and what would let it jump:
a narrower query, a spelling fix, the words it ignored, or the repo name in front of a path
several repos have. Then it exits 1.

#### Frecency and fuzzy matching

Visited directories float to the top of the list, since fzf's last tiebreak is input order and
pre-sorting the input is the whole mechanism. They never decide a jump, though: a jump that depends
on history lands somewhere different over time, with nothing on screen to say why. `begin,chunk`
replaced `begin,length` so the visited order can decide between rows with the same name, because
once paths are searched every line is a different length. Matching stays `--exact` because fuzzy
matching over the name and the path matches nearly every row that holds the query's letters in
order, anywhere along the line. fzf's `'` prefix still makes one word fuzzy.

Not built yet: typo correction while you type in the picker, and caching the enumeration.

---

## Files

```
hop.zsh                 entry point: hop, hopr, hopw, the ^G widget, config loading
hop.plugin.zsh          the name plugin managers look for; sources hop.zsh and nothing else
lib/dsl.zsh             the hop_kind registry and the generic enumeration engine
lib/providers.zsh       row primitives, plus families too irregular to declare
lib/ui.zsh              the picker's fzf call and the whole modal keymap
lib/match.zsh           the resolver: literal paths, the matching steps, and the jump rules
lib/actions.zsh         the verbs: cd, open, reveal, edit, copy, browse, and frecency
lib/doctor.zsh          hop --doctor and the HOP_DEBUG log
lib/workspaces.zsh      workspace config parsing and lookup
lib/upgrade.zsh         hop upgrade: the release-tag self-update, and every refusal it makes
presets/                shipped kind declarations, loaded with hop_preset
bin/hop-kinds           renders the `:` menu and reloads rows; never runs fzf
bin/hop-preview         the preview pane, and the `?` keymap overlay
completions/_hop        zsh completion, driven by the live registry
tests/run               the headless test suite
tests/eval_real.zsh     the jump sweeps over a real checkout; tests/run doesn't run it
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
| `HOP_ACTION` | `cd` | what Enter does: `cd`, `open`, `reveal`, `cd+open` or `cd+reveal` |
| `HOP_JUMP` | `auto` | when a query may skip the picker: `auto`, `unique` or `never` |
| `HOP_CODE` | `code` | a VS Code-compatible CLI that accepts `-r` and `-n`: `code`, `cursor`, `codium`, `code-insiders` |
| `HOP_HISTFILE` | `~/.local/state/hop/history` | frecency history; a dir that no longer exists is dropped from it |
| `HOP_HIST_MAX` | `300` | how many frecency history lines to keep |
| `HOP_CLIPBOARD` | unset | overrides the copy verb's clipboard command, skipping the probe |
| `HOP_VIM` | `1` | `0` disables the modal layer |
| `HOP_FZF_HEIGHT` | `80%` | picker height; **empty means fullscreen** |
| `HOP_HOPRC` | unset | `1` allows a repo-root `.hoprc` to run |
| `HOP_FZF_MIN` | `0.60.3` | the fzf floor; lower it if the check is wrong about your build |
| `HOP_GUARD_WINDOW` | `0.15` | seconds the escape guard refuses a verb for; `0` disables it |
| `HOP_DEBUG` | unset | `1` logs every key dispatch, readable via `--doctor` |
| `HOP_DEBUG_LOG` | `~/.local/state/hop/debug.log` | where that log goes |
| `HOP_HOME` | derived from `hop.zsh` | install directory |

### `HOP_FZF_HEIGHT`

By default the picker takes 80% of the terminal and leaves your scrollback visible above it. Any
value fzf's `--height` accepts works here, so `HOP_FZF_HEIGHT=100%` or `HOP_FZF_HEIGHT=30` both do
what you would expect. Setting it to the **empty string** is the special case: it drops `--height`
altogether and fzf takes over the whole screen on its own alternate buffer.

Fullscreen is also the only mode that survives a synthetic terminal, which is what the pty tests
use. In `--height` mode fzf asks the terminal where the cursor is and waits for the answer, and
nothing in `zsh/zpty` ever answers, so the picker hangs before it draws anything.

### `.hoprc` is opt-in

A repo-root `.hoprc` can declare extra kinds, but sourcing it runs arbitrary code from whatever repo
you happen to be standing in. Default-on meant `cd` into any clone plus one `hop` was a code
execution path, so it now requires `HOP_HOPRC=1`. Only enable it for repos you would already
`source` by hand.

### Degradations

Every dependency beyond `zsh`, `fzf` and `git` is optional and degrades to something that works: no
`bat` means plain `cat`; no `gh` means the browse verb explains why; no `code` means `$EDITOR`; no
clipboard tool means the copy verb names what to install instead of copying nothing silently. The
copy verb itself tries `pbcopy`, `wl-copy`, `xclip`, `xsel`, then `clip.exe`, so it works unmodified
on macOS, Wayland, X11 and WSL. A kind whose families are absent from the current repo emits zero
rows and **zero** stderr, which is what lets one config work across every repo without noise.

VS Code counts as unusable, not just missing, in three more cases: `VSCODE_IPC_HOOK_CLI` names a
socket that's gone, which is a terminal that outlived its window; an SSH session with no VS Code
window attached; and Linux with neither `DISPLAY` nor `WAYLAND_DISPLAY`, except under WSL, where
`code` opens VS Code on Windows. A live IPC socket wins over the other two, so a VS Code Remote-SSH
terminal still works. When `code` can't be used, each verb says why in one line and then does the
nearest thing:

- open or reveal a file, and open a directory, use `$EDITOR` instead;
- reveal a directory has no editor equivalent, so it explains and exits 1;
- `cd+open` and `cd+reveal` still `cd`, then say what they skipped;
- with no terminal, hop won't start an editor, and prints the target's path instead.

What `reveal` can show is up to VS Code. The explorer follows a `code -r <file>` only with
`explorer.autoReveal` on, the Explorer view visible, and the file inside a folder that window has
open; otherwise the file just opens as a tab. For a file target, `open` and `reveal` are the same
call.

---

## Tests

```zsh
tests/run
```

The suite is headless and hermetic: it builds synthetic fixture repos rather than reading your real
checkouts, and it stubs every external command so a test can never open an editor window or a
browser tab.

`tests/suite_pty.zsh` is the exception to headless. It runs the real picker inside a `zsh/zpty`
pseudo-terminal and sends real keystrokes, which is the only way to prove that a key reaches its
action. It needs `HOP_FZF_HEIGHT=` for fullscreen, and it reads fzf's own exported state rather than
the screen, because `zsh/zpty` cannot set a window size and the rendered UI is unusable. Missing
`zsh/zpty` skips those tests locally but **fails** under `$CI`, so a runner that loses pty
capability turns red instead of quietly dropping coverage.

`tests/eval_real.zsh` checks the jump rules against a real checkout, which a fixture can't stand in
for. `tests/run` doesn't run it, so run it yourself after changing `lib/match.zsh`:

```zsh
HOP_TEST_REPO=~/src/some-repo zsh tests/eval_real.zsh
```

It builds the repo's rows with the default kinds from your `HOP_CONFIG` and asks every name,
3-letter prefix, scope+env pair and name+env pair it finds there, plus every word of a 500-word
dictionary that the rows don't contain. It fails if a query that jumped with hop 0.1.2's matcher
now opens the picker or lands somewhere else, or if any of those dictionary words jumps. New jumps
are listed but don't fail it, and so is a jump lost only because another match's name line is
clipped with `…`, since the old matcher's one hit there was a guess. It never calls `hop` itself,
so nothing cds, opens a window or writes history.

What is left in `SMOKE.md` is the part with no machine-readable outcome: whether the layout is
actually readable at 80 columns, and where VS Code puts what a `code` call opens.

---

## Troubleshooting

```zsh
hop --doctor
```

Prints the install path and version, every `HOP_*` setting and whether its file is readable, the
version of each optional tool, where you are and which workspace that falls in, and every
registered kind with its live row count in the current repo. That last table is usually the answer:
a kind showing `0` is a kind whose `--dirs` or `--marker` does not match this repo. Under the table
it names any `--fn` kind still printing 3-field rows.

It also shows `HOP_ACTION`, `HOP_JUMP` and `HOP_CODE`, and whether VS Code is reachable from this
shell, with the reason when it isn't. That's the line to read when Enter or `o` opens `$EDITOR`
where you expected VS Code.

For a key that did something unexpected, log what actually dispatched:

```zsh
HOP_DEBUG=1 hop      # reproduce the problem
hop --doctor         # the last 15 dispatches are at the bottom
```

`--doctor` output contains local paths, workspace names and kind names. Read it before pasting
anywhere public. For a bug report, run `hop --doctor=short` instead: it withholds every path and
name and reports counts in their place, so it is safe to paste into a public issue.

### Keys that get mixed up

`^G` launches hop from the shell, and it no longer means anything *inside* hop: browse is `b` in
NORMAL and `alt-B` in SEARCH. Navigation is `l`/`h` in NORMAL and `ctrl-l`/`ctrl-h` in SEARCH.

### Nothing appears at all

`hop` needs either a git repo or a configured workspace. Outside a repo it opens the workspace
picker, and with no `~/.config/hop/workspaces` it guesses `~/src`, `~/code`, `~/projects`, `~/dev`
and `~/work`. If none of those exist you get an empty picker; write the file.

---

## License

MIT. See [LICENSE](LICENSE).
