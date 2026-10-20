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

### Install

`hop` is one binary for macOS and Linux. It needs [`fzf`](https://github.com/junegunn/fzf)
0.60.3 or newer, and `git`. Optional: [`bat`](https://github.com/sharkdp/bat) for highlighted
previews, `gh` for the browse verb, and VS Code's `code` (or the CLI `HOP_CODE` names) for the open
and reveal verbs.

That fzf floor is newer than what some distros package. The picker passes `--accept-nth` together
with `--select-1`: `--accept-nth` arrived in fzf 0.60.0 and only worked alongside `--select-1` from
0.60.3. Debian and Ubuntu package 0.44.x, which rejects the flag, so `apt install fzf` isn't enough:
install an [upstream release](https://github.com/junegunn/fzf/releases), or let Homebrew bring it.

#### Homebrew

```sh
brew tap etknorr/hop https://github.com/etknorr/hop
brew install etknorr/hop/hop
```

The formula lives in this repo, builds `hop` from source with Go, and installs fzf with it. It works
the same on macOS and Linux.

#### go install

```sh
go install github.com/etknorr/hop@latest
```

This needs Go 1.26 or newer, the version `go.mod` names. The binary lands in `$(go env GOBIN)`, or
`$(go env GOPATH)/bin` when `GOBIN` is unset, and that directory has to be on your `PATH`. Install
fzf separately.

#### Release archives

Every [release](https://github.com/etknorr/hop/releases) has a `.tar.gz` for darwin and linux on
amd64 and arm64, with a `checksums.txt`. Put the `hop` inside on your `PATH`. `hop upgrade` can't
update a copied binary, so it prints the other install commands instead.

#### From a checkout

```sh
git clone https://github.com/etknorr/hop ~/src/hop
cd ~/src/hop && go build -o bin/hop .
```

Then put `~/src/hop/bin` on your `PATH`. `hop upgrade` moves this checkout between releases and
rebuilds the binary.

### Shell setup

`hop` exists to `cd`, and a child process can't change its parent shell's directory. So the binary
prints a small shell function that runs it and does the `cd` itself. Add one line to your shell's rc
file:

| Shell | File | Line |
|---|---|---|
| zsh | `~/.zshrc`, after `compinit` | `eval "$(hop init zsh)"` |
| bash 3.2 and newer | `~/.bashrc` | `eval "$(hop init bash)"` |
| fish | `~/.config/fish/config.fish` | `hop init fish \| source` |

That line defines:

- `hop`, the function. It runs the binary and `cd`s to what it picked, with plain `cd`, so zoxide and
  `chpwd` hooks see the jump. `hop -` is `cd -`.
- `hopr`, which `cd`s to the repo root, and `hopw`, which `cd`s to the configured workspace holding
  `$PWD`.
- Completion for every flag, the kinds in your config, and the `upgrade`, `init` and `import` verbs.
- `^G` and `alt-g`, which open `hop` from a half-typed command line. The line comes back at the next
  prompt. In zsh, `^G` replaces `send-break`, so use `^C` to abandon a line.

`--cmd NAME` gives the function another name and leaves out `hopr` and `hopw`, for example
`eval "$(hop init zsh --cmd j)"`. In zsh, completion is only registered when `compinit` has already
run, which is why the line goes after it.

When a new `hop` changes these scripts, `hop -V` adds
`hop: your shell integration predates this hop: run 'exec zsh' to reload it`.

#### Moving from zsh hop 0.3

`hop` 1.0 replaces the zsh plugin. Install the binary first, then:

1. Convert your config. This reads `~/.config/hop/config.zsh` and leaves it alone:
   ```sh
   command hop import -o ~/.config/hop/config.toml
   ```
   Your history and workspaces files keep their format, so ranking carries over.
2. Replace the line that sources `hop.zsh` (or your plugin manager's entry) with the init line
   above, then `exec zsh`.

Don't run 0.3's `hop upgrade` once 1.0 is out. It fast-forwards the zsh checkout to the Go tree,
which has no `hop.zsh`, so the `source` line in `~/.zshrc` fails. To undo it, run
`git -C ~/.local/share/hop checkout --detach v0.3.1`. zinit, antidote, sheldon and oh-my-zsh
installs have no 1.0 equivalent: use one of the installs above.

#### Configuring it

With no config at all, `hop` lists every repo's top-level dirs and its projects, and works in any
repo straight away. To teach it your own layout, start from the examples in this repo,
[config.example.toml](config.example.toml) and [workspaces.example](workspaces.example), copied to
`~/.config/hop/config.toml` and `~/.config/hop/workspaces`. [Configuring kinds](#configuring-kinds)
describes every key.

<!-- end: install -->

## Using the picker

### Commands

| Command | Does |
|---|---|
| `hop` | pick from the default kinds, starting in NORMAL mode |
| `hop vpc prod` | a clear match jumps with no UI; otherwise the picker opens on the best matches first. See [How a query resolves](#how-a-query-resolves) |
| `hop services/api` | a path that exists jumps straight there, before any matching, even from outside its repo when only one repo has it, or only one of that repo's checkouts is on its default branch |
| `hop /` or `hopr` | `cd` to the repo root |
| `hop -` | `cd -` |
| `hopw` | `cd` to the workspace containing `$PWD`, deepest match winning |
| `hop upgrade` | update `hop` the way it was installed; see [Upgrading](#upgrading) |
| `^G` or `alt-g` | open `hop` from a half-typed command line, which survives |

`^G` replaces zsh's `send-break`. Use `^C` to abandon a line, or rebind `hop-widget`.

#### Flags

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
| `-V`, `-v`, `--version` | print the version, and say when the shell integration predates the binary |
| `-h`, `--help` | usage, listing the kinds actually registered |

`-c` is the one to remember. `hop -c -k file pr` finds a file by name inside the subtree you are
standing in, instead of across the whole repo.

#### What Enter does

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
all, as a directory of nothing but subdirectories doesn't, hop says so and suggests `-o`.

`hop /`, `hop -`, `hopr` and `hopw` always `cd`, whatever `HOP_ACTION` says, because they navigate
by name rather than pick a target. Inside the picker, `c` (NORMAL) and `alt-enter` (SEARCH) always
`cd` too, so the plain `cd` stays one key away when Enter does something else. In the `:` view
menu they do nothing, because a menu row names a view, not a directory.

### Modal mode

`hop` starts in NORMAL mode, like `k9s` or vim: keys are verbs, not text. `/` enters SEARCH.

#### Why a modal layer needs `ignore`

fzf's `--disabled` and `disable-search` stop *filtering*, but the query buffer still accepts
keystrokes, so a bare `--disabled` gives you a mode where typing looks broken rather than doing
nothing. A real NORMAL mode has to bind every printable character to `ignore` and `rebind` them on
entering SEARCH, which is why hop's NORMAL keymap is about 99 binds.

fzf has no key-sequence support, so there is no `gg`. `g` alone is first, `G` is last.

#### NORMAL

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
and `alt-a` needs a reload command. The levels run workspace, repo, then a repo's targets: `l` on a
workspace lists its repos, `l` on a repo lists that repo's targets without `cd`-ing into it, and `h`
goes back up, from a repo's targets to the repos and from the repos to the workspaces. The workspace
picker (`hop -w`) has no `h`, and the targets of the repo you're in get `h` only when hop knows other
repos (from workspaces or `$HOP_REPOS`). Where a key is not bound, the legend and the `?` overlay both leave it out rather than name a
key that does nothing.

Every printable ASCII key is bound in NORMAL, so none of them types. After an `esc` out of SEARCH
the query is still live, though, and a key fzf can't bind still lands in it and filters the list:
a non-ASCII character, such as the `π` that Option+p sends when your terminal doesn't treat Option
as Meta, or a paste.

#### SEARCH

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

#### The escape guard

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
level navigation; moving the remaining `--expect` keys onto guarded binds isn't done yet.

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
guarded, and that is a safety property rather than an oversight: if the `hop __guard` callback ever
failed to run, a `transform:` yields no output, fzf treats that as no action, and all ten guarded
keys go dead at once. `esc` is then the only way out of the picker.

#### The `:` kind menu

`:` switches which kinds are listed, **in place**, with no nested fzf process. It reuses the single
fzf instance by reloading it with a menu and using `$FZF_PROMPT` as the mode flag. `enter` switches
to that kind, and that kind stays the view `r` and a later `esc` out of the menu come back to;
`esc` returns to the view you came from. `/` filters the menu, with a `:/ ` prompt. `:` drops a query
kept from SEARCH, because it would filter the kind list too, so `esc` out of the menu brings back the
full list, not the filtered one.

Menu counts are live: every kind is counted from one `git ls-files` of the repo each time the menu
opens, which is fast enough that nothing is cached.

A kind with zero matches in the current repo is hidden from the menu entirely, which is what keeps
one shared config from cluttering unrelated repos.

Every reload builds its rows the way the first list was built: `alt-a`, `r`, `esc` out of the menu
and switching to a kind all keep `-c`'s subtree and the visited-first order. Two things don't
survive a reload: the directory rows a query added (see
[How a query resolves](#how-a-query-resolves)), and the best-first order the picker opened with.

#### Escape hatch

`HOP_VIM=0` gives plain search-first fzf. Nothing about the modal layer is load-bearing for the
verbs, so this is a genuine fallback, not a degraded mode.

### Workspaces

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

### How a query resolves

`hop <words>` decides what you meant before any picker opens. It tries these steps in order and
stops at the first one that finds something:

1. **Literal path**: one word that holds a `/`, starts with `~`, `./` or `../`, or is a bare `.` or
   `..`, and names a real directory or file jumps there before anything is enumerated, in about a
   millisecond. `hop -o .` opens the directory you're in. The match ignores case and lands on the
   on-disk spelling, so `hop Services/API` cds to `services/api`. `./x` and `../x` are
   relative to `$PWD`, `/x` is relative to the repo root first (as `hop /` is), and anything else
   tries `$PWD` and then the root. `-k` doesn't narrow it, since no kind is consulted, and `-w`,
   `-R` and `-p` skip it.

   A path that isn't under `$PWD` or the repo root is looked up in every repo hop knows
   (`$HOP_REPOS`, or every repo in your workspaces), with or without the repo's name in front, and
   under every workspace root. It ignores case the same way. So from `~`, both
   `hop services/api` and `hop platform/services/api` land in `platform`, as long
   as no other repo has the same path. One match jumps and prints where it was found:
   `hop: services/api -> ~/work/platform/services/api/ (found in platform)`.

   Two or more jump only when every one is a checkout of the same origin repo and exactly one of
   them is checked out on its default branch. Origins are compared by `remote.origin.url` with the
   scheme, the user and a trailing `.git` dropped, ignoring case, so `git@github.com:org/repo` and
   `https://github.com/org/repo.git` count as one. The default branch is what `origin/HEAD` names,
   else `main` if the repo has it, else `master` if it has that, and a detached HEAD isn't on any
   branch. So when a clone, a retired copy and two worktrees of `platform` hold the path and
   only one of them is on `main`, hop lands there, and the note says why:
   `(found in platform, the main checkout of 4)`. hop reads this from each checkout's own git
   files rather than running `git`, so it costs a few milliseconds. `HOP_JUMP=unique` turns this
   rule off, since there the path names more than one target. When they don't jump, the picker
   opens on just those, each row named by its repo, the repo you visited most recently first, then
   by path.

   Inside a repo, other repos are tried only when the repo has nothing close to the query, so
   a match or a typo pick in the repo you're in still wins. The lookup needs a `/` with a name
   after it, so `hop platform/` is still matched like any other query. It skips paths
   starting with `./`, `../`, `/` or `~` and paths with a `.` or `..` segment, and it's off under
   `-c`, which keeps the search under `$PWD`. Under `-p` or `HOP_JUMP=never` it still runs, and
   even one match opens the picker. A misspelt path isn't corrected here. When no repo has the path
   but some repo has its first directory, hop names the repos that have it, the first three and a
   count of the rest. A typo is only corrected from inside its repo, so `cd` into one and run the
   query again. It only checks whether the path exists in each repo, so it lists no repo's targets
   and costs a few milliseconds.
2. **Exact**: fzf matches the words against the row's name line (name, kind, scope, env and
   region) and its `rel` path, with `--exact`, `-i` and `--tiebreak=begin,chunk`. The picker gets
   the same flags from the same array, so the two always agree on which rows match. Your
   `FZF_DEFAULT_OPTS` never reaches this step, so a default such as `--no-sort`
   or `--nth=1` can't change what jumps, and the picker resets `--nth`, `--tac` and `--scheme`, the
   defaults that would change which rows match or their order.
3. **Rewrite**: a word that no path contains is fixed against the words the paths do contain: one
   typo from 4 letters, two from 8, or an abbreviation from 6. `checkuot` reads as
   `checkout`. A word the paths already hold is abbreviated only when nothing matched without
   that, so `infra/account-billing` reads as `infra account | acct billing`, while
   `homepage-prod` stays `homepage prod` instead of gaining `page`. A word run together
   from two or three path words is split back into them, so `externaldns` reads as `external dns`,
   and a short env word no path holds reads as its long form: `prd` as `prod`, `stg` as `staging`.
   If one word can't be explained, this step finds nothing, so a nonsense word is never turned
   into a match.
4. **Loose**: initials, or the letters in order within one path segment, starting with its first
   letter: `kps` and `kubeprom` both find `kube-prometheus-stack`.
5. **Relaxed**: with two or more words, each word is read on its own by whichever step above finds
   it, the ones nothing reads are dropped, and the picker's header says so: `ignored: zzqx`. When
   every word matches alone but no row holds them all, the picker shows the rows that hold all but
   one, smallest set first, and the header says `ignored: one of: homepage, dev`.
6. **Nothing close**: the picker opens on your query with no rows, ready to edit.

Before any of these, a first word that names a registered kind outside your default set is read
as `-k` when that kind has targets in this repo and no default target holds the word as a whole
word of its name line or its path. So with `file` not a default kind, `hop file renovate.json` is
`hop -k file renovate.json`, and hop prints `hop: reading "file" as -k file`. `hop file` alone opens
the picker on that kind, even when it holds one target. `hop -k file` is the form that jumps to a
lone target. A default kind such as `tg`, a kind name after the first word, a kind with no targets
here, and a word some default target holds all stay plain words, so `hop puppet` in a repo with a
top-level `puppet/` still goes to that dir. A kind name that's only part of a word, as `conf` is of
`aws-config`, doesn't count as held. Nothing is read as `-k` when you pass `-k` or `-a`, or under
`-w` or `-R`, which list no kinds. Outside a repo it's read only when one path follows it, so
`hop file services/x` from `~` looks the path up in your repos as `hop -k file services/x` does,
while `hop puppet` from `~` stays a workspace query. With no terminal, a rest that matches nothing
is reported as `nothing matched the query: zzqx with -k file`.

#### Jump rules

Whether a query jumps is decided by the rules below, never by a score, because fzf doesn't expose
one. Only a literal path, an exact match, or a rewrite that changed nothing but separators or case
(`payments_api_prod`) may jump. A typo fix or a loose match always opens the picker, best match
first, because a typo costs you one Enter and a false jump costs a wrong `cd` or a wrong VS Code
window. An exact match jumps when one of these holds, checked in this order:

| Rule | When | Example |
|---|---|---|
| J1 | exactly one target matches | `payments api` |
| J1b | every match is in one directory, and Enter is plain `cd` | `monitoring/grafana`, whose files all sit in `deploy/monitoring/` |
| J3 | exactly one row matches on its name line alone, and no other match's name line is clipped with `…`, except a name its path spells out whole, which is matched whole | `disaster-recovery prod` |
| J0 | at the workspace and repo levels only: one word, and exactly one target's name is that word | `platform` from `~`, past `platform.old` |
| J2 | every match is under one directory, the words name that directory on whole-word boundaries, and none of them is a kind name | `payments-prod` jumps to `infra/payments-prod/` |

The name line is all hop searched before paths were added, so a query that jumped before still
jumps, unless another match has a clipped kind, scope, env or region, or a clipped name its path
doesn't spell out whole.

J2 prints one line saying why it jumped, such as
`hop: payments-prod -> infra/payments-prod/ (all 3 matches are under it)`,
and J0 names what it skipped: `hop: platform -> ~/work/code/platform/ (exact name; 3
others contain it)`. A jump on a rewrite of separators says how it read the words, as
`hop: homepage-prod -> ... (read as: homepage prod)`.
`inf` doesn't jump to `infra/`, because a prefix isn't a whole word, and `tg vpc` doesn't jump
by J2, because `tg` names a whole family. Under any mode but plain `cd`, `cd+reveal` included, J1b
doesn't collapse the files in one directory, because each file is a target of its own.

An account or env directory is not a row of any kind, but it still shows up when your query names
it: hop adds it as a row only when it matches the same query, and J2 is the only rule that jumps to
one. A query using fzf's own syntax (`'`, `^`, `$`, `!` or `|`) gets the exact step alone, with no
rewrite and no added rows.

Outside a repo, a path is looked up in your repos and workspace roots first, as step 1 describes.
Any other query is resolved against your workspaces, and when none matches exactly hop tries your
repos too and keeps the closer result, a tie going to the workspaces. So `hop tf vpc` from `~`
lands on `tf-aws-vpc` instead of a workspace that only matched `tf`.

`HOP_JUMP` sets how eager this is. `auto` allows every rule above. `unique` allows literal paths,
J1, J1b and J3, so a query jumps only when it names one target. `never` always opens the picker,
and `-p` is `never` for one call.

#### The picker

When a query opens the picker, the closest matches come first: `payments prod` lists the
`infra/payments-prod/` directory and then its units. The first key you type hands the order back to fzf. The header's
first line says when the query was rewritten, for example
`no exact match for: paymnets-prod (showing: payments prod)`, or
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

### Upgrading

`hop upgrade` works out how `hop` was installed and upgrades it the same way:

| Installed with | `hop upgrade` runs | `hop upgrade 1.2.0` |
|---|---|---|
| Homebrew | `brew upgrade etknorr/hop/hop` | refused, since brew only has the newest release |
| `go install` | `go install github.com/etknorr/hop@latest` | `go install github.com/etknorr/hop@v1.2.0` |
| a checkout | fast-forwards `main` to the newest release tag, then `go build -o <this binary> .` | checks out `v1.2.0` detached, then rebuilds |
| anything else | nothing; it prints the three install commands | the same |

`hop upgrade --check` (or `--dry-run`, or `-n`) prints the installed version against the newest
`vX.Y.Z` tag and changes nothing. It reads the tags with `git ls-remote`, so it needs no GitHub
token. A checkout asks its own `origin`.

Under `go install`, `hop upgrade` warns when Go would write the new binary somewhere other than the
directory the running `hop` is in, since the old one would then stay first on your `PATH`.

A checkout has two ways to move. Bare `hop upgrade` fast-forwards your local `main`, so `git pull`
and the next `hop upgrade` both keep working. Naming a version is a pin: it detaches `HEAD` at that
tag, and a bare `hop upgrade` later brings you back to `main`, saying so. Between releases `main` is
normally ahead of the newest tag, and `hop upgrade` reports that as up to date.

A checkout upgrade refuses, changing nothing, when the checkout has uncommitted changes, sits on a
branch other than `main`, is detached somewhere that isn't a release tag, has no `origin`, is inside
another repo, or has a `main` that has diverged from the release. It never cleans, resets, merges
or forces anything, and it never touches untracked files. An untracked file where the release ships
one is a refusal too. `--check` changes no files, but it does fetch tags into `.git`.

Releases are cut from a `v*` tag by the release workflow, as [docs/RELEASING.md](docs/RELEASING.md)
describes.

### Environment

Each variable beats the same key in `config.toml`'s `[settings]`, which is the reverse of zsh hop 0.3,
where a `typeset` in `config.zsh` beat the environment. In the file, `workspaces`, `repos` and
`default_kinds` are lists, `vim` and `debug` are booleans, and `hist_max` and `guard_window` are
numbers.

| Variable | `[settings]` key | Default | Does |
|---|---|---|---|
| `HOP_CONFIG` | - | `~/.config/hop/config.toml` | your config; a value ending in `.zsh` is zsh hop's and is never read as TOML |
| `HOP_DEFAULT_KINDS` | `default_kinds` | kinds declared `default = true` | the default kind set |
| `HOP_WORKSPACES_FILE` | `workspaces_file` | `~/.config/hop/workspaces` | workspace list |
| `HOP_WORKSPACES` | `workspaces` | unset | colon-separated workspaces, overrides the file |
| `HOP_REPOS` | `repos` | every repo in every workspace | colon-separated repo list for `-R` |
| `HOP_ACTION` | `action` | `cd` | what Enter does: `cd`, `open`, `reveal`, `cd+open` or `cd+reveal` |
| `HOP_JUMP` | `jump` | `auto` | when a query may skip the picker: `auto`, `unique` or `never` |
| `HOP_CODE` | `code` | `code` | a VS Code-compatible CLI that accepts `-r` and `-n`: `code`, `cursor`, `codium`, `code-insiders` |
| `HOP_HISTFILE` | `hist_file` | `~/.local/state/hop/history` | frecency history; a dir that no longer exists is dropped from it |
| `HOP_HIST_MAX` | `hist_max` | `300` | how many frecency history lines to keep |
| `HOP_CLIPBOARD` | `clipboard` | unset | overrides the copy verb's clipboard command, skipping the probe |
| `HOP_VIM` | `vim` | `1` | `0` disables the modal layer |
| `HOP_FZF_HEIGHT` | `fzf_height` | `80%` | picker height; **empty means fullscreen** |
| `HOP_FZF_MIN` | `fzf_min` | `0.60.3` | the fzf floor; lower it if the check is wrong about your build |
| `HOP_GUARD_WINDOW` | `guard_window` | `0.15` | seconds the escape guard refuses a verb for; `0` disables it |
| `HOP_DEBUG` | `debug` | unset | any value logs every pick and key dispatch, readable with `--doctor` |
| `HOP_DEBUG_LOG` | `debug_log` | `~/.local/state/hop/debug.log` | where that log goes |

The `~/.config` and `~/.local/state` defaults follow `XDG_CONFIG_HOME` and `XDG_STATE_HOME` when
they're set. The shell function sets `HOP_CMDFILE`, `HOP_SHELL` and `HOP_INIT_HASH` for each call;
they aren't settings.

#### `HOP_FZF_HEIGHT`

By default the picker takes 80% of the terminal and leaves your scrollback visible above it. Any
value fzf's `--height` accepts works here, so `HOP_FZF_HEIGHT=100%` or `HOP_FZF_HEIGHT=30` both do
what you would expect. Setting it to the **empty string** is the special case: it drops `--height`
altogether and fzf takes over the whole screen on its own alternate buffer.

Fullscreen is also what the pty tests use. In `--height` mode fzf asks the terminal where the cursor
is and waits for the answer, which a synthetic terminal may never send.

#### `.hoprc` is gone

zsh hop 0.3 could source a repo-root `.hoprc` when `HOP_HOPRC=1` was set. That ran code from
whatever repo you stood in, and 1.0 doesn't read it at all. `hop --doctor` reports a set
`HOP_HOPRC` as unsupported.

#### Degradations

Every dependency beyond `fzf` and `git` is optional and degrades to something that works: no
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

### Troubleshooting

```zsh
hop --doctor
```

Prints the install path and version, every `HOP_*` setting and whether its file is readable, the
version of each optional tool, where you are and which workspace that falls in, and every
registered kind with its live row count in the current repo. That last table is usually the answer:
a kind showing `0` is a kind whose `dirs`, `files` or `marker` does not match this repo. Under the
table it lists the recipes hop ships and the ones your config loads.

It also shows `HOP_ACTION`, `HOP_JUMP` and `HOP_CODE`, and whether VS Code is reachable from this
shell, with the reason when it isn't. That's the line to read when Enter or `o` opens `$EDITOR`
where you expected VS Code.

For a key that did something unexpected, log what actually dispatched:

```zsh
HOP_DEBUG=1 hop      # reproduce the problem
hop --doctor         # the last 15 log lines are at the bottom
```

`--doctor` output contains local paths, workspace names and kind names. Read it before pasting
anywhere public. For a bug report, run `hop --doctor=short` instead: it withholds every path and
name and reports counts in their place, so it is safe to paste into a public issue.

#### Keys that get mixed up

`^G` launches hop from the shell, and it no longer means anything *inside* hop: browse is `b` in
NORMAL and `alt-B` in SEARCH. Navigation is `l`/`h` in NORMAL and `ctrl-l`/`ctrl-h` in SEARCH.

#### Nothing appears at all

`hop` needs either a git repo or a configured workspace. Outside a repo it opens the workspace
picker, and with no `~/.config/hop/workspaces` it guesses `~/src`, `~/code`, `~/projects`, `~/dev`
and `~/work`. If none of those exist, it stops with
`hop: not in a git repository, and no workspaces found`. List your code dirs in that file (see
[`workspaces.example`](workspaces.example)), or set `$HOP_WORKSPACES`.

### Tests

```sh
go vet ./... && go test ./...
```

The suite is hermetic: every package runs in a temp `HOME` with every inherited `HOP_*` and `FZF_*`
variable unset, builds synthetic fixture repos rather than reading your checkouts, and stubs every
external command, so a test can never open an editor window or a browser tab or touch your history.
It needs `fzf` and `git`; the tests that compare against zsh hop also need `zsh`, and skip without
it.

Some tests compare against zsh hop 0.3.1 itself, run from the `v0.3.1` tag, so a clone needs its
tags (`git fetch --tags`). `pty_test.go` runs the real picker on a pseudo-terminal and sends real
keystrokes, which is the only way to prove that a key reaches its action. To check the fzf floor, put
an fzf 0.60.3 first on `PATH` and run `go test -run 'TestPicker|TestArgv' .` again.

`test/shell/run-all.sh` sources `hop init` in zsh, bash 5, macOS `/bin/bash` 3.2 and fish (in docker,
or the host's with `NO_DOCKER=1`) and drives the function, the widget and completion in each.

`test/parity/` compares this hop with an installed zsh hop 0.3.1 on a real repo: `rows.sh` the rows of
every kind, `resolve.sh` every jump decision under `HOP_JUMP` auto, unique and never, `e2e.sh` where
each query lands, and `perf.sh` how long both take. Each needs the oracle and the repo:

```sh
HOP_PARITY_HOME=<zsh hop 0.3.1 checkout> HOP_PARITY_REPO=<repo> HOP_PARITY_CONFIG=<config.toml> test/parity/rows.sh
```

[docs/SMOKE.md](docs/SMOKE.md) is what's left for a person: whether the layout reads well at 80
columns, and where VS Code puts what a `code` call opens.

<!-- end: ops -->

## License

MIT. See [LICENSE](LICENSE).
