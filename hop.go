package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/etknorr/hop/internal/act"
	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/debuglog"
	"github.com/etknorr/hop/internal/kinds"
	"github.com/etknorr/hop/internal/match"
	"github.com/etknorr/hop/internal/mru"
	"github.com/etknorr/hop/internal/pick"
	"github.com/etknorr/hop/internal/resolve"
	"github.com/etknorr/hop/internal/rows"
	"github.com/etknorr/hop/internal/tty"
	"github.com/etknorr/hop/internal/workspace"
	"golang.org/x/term"
)

// hopOpts is hop()'s parsed command line.
type hopOpts struct {
	words                       []string
	kinds                       []string
	all, repos, wss, here, pick bool
	actCD, actOpen, actReveal   bool
	actFlag, mode               string
	vim                         *bool
	info                        string
}

// parseHop is hop()'s option loop (hop.zsh:458), with its exit-2 rules.
func parseHop(args []string, stderr io.Writer) (*hopOpts, int) {
	o := &hopOpts{}
	opts := false
	for len(args) > 0 {
		a := args[0]
		switch {
		case a == "-h" || a == "--help":
			o.info = "help"
			return o, 0
		case a == "-V" || a == "-v" || a == "--version":
			o.info = "version"
			return o, 0
		case a == "--doctor" || strings.HasPrefix(a, "--doctor="):
			o.info = a[2:]
			if a == "--doctor" && len(args) > 1 && args[1] == "short" {
				o.info = "doctor=short"
			}
			return o, 0
		case a == "-a" || a == "--all":
			o.all, opts = true, true
		case a == "-R" || a == "--repos":
			o.repos, opts = true, true
		case a == "-w" || a == "--workspaces":
			o.wss, opts = true, true
		case a == "-c" || a == "--cwd" || a == "--here":
			o.here, opts = true, true
		case a == "-p" || a == "--pick":
			o.pick, opts = true, true
		case a == "--cd":
			o.actCD, opts = true, true
		case a == "-o" || a == "--open":
			o.actOpen, opts = true, true
		case a == "-e" || a == "--reveal":
			o.actReveal, opts = true, true
		case a == "--vim" || a == "--no-vim":
			on := a == "--vim"
			o.vim, opts = &on, true
		case a == "--action" || a == "--action=":
			fmt.Fprintln(stderr, "hop: --action needs a mode, as --action=MODE:", strings.Join(config.Actions, ", "))
			return nil, 2
		case strings.HasPrefix(a, "--action="):
			o.actFlag, opts = a[len("--action="):], true
		case a == "-k" || a == "--kinds":
			if len(args) < 2 {
				fmt.Fprintln(stderr, "hop: -k needs a comma-separated kind list")
				return nil, 2
			}
			o.kinds, opts = splitKinds(args[1]), true
			args = args[1:]
		case strings.HasPrefix(a, "-k"):
			o.kinds, opts = splitKinds(a[2:]), true
		case a == "/" || a == "-":
			if len(args) > 1 || len(o.words) > 0 || opts {
				fmt.Fprintf(stderr, "hop: %s takes no other arguments\n", a)
				return nil, 2
			}
			o.mode = a
		case a == "--":
			o.words = append(o.words, args[1:]...)
			args = nil
			continue
		case strings.HasPrefix(a, "-"):
			fmt.Fprintln(stderr, "hop: unknown option:", a)
			return nil, 2
		default:
			o.words = append(o.words, a)
		}
		args = args[1:]
	}
	if o.actOpen && o.actReveal {
		fmt.Fprintln(stderr, "hop: -o and -e are exclusive")
		return nil, 2
	}
	if o.actFlag != "" {
		if o.actCD || o.actOpen || o.actReveal {
			fmt.Fprintln(stderr, "hop: --action=MODE cannot be combined with --cd, -o or -e")
			return nil, 2
		}
		if !slices.Contains(config.Actions, o.actFlag) {
			fmt.Fprintf(stderr, "hop: --action=%s is not one of %s\n", o.actFlag, strings.Join(config.Actions, ", "))
			return nil, 2
		}
	}
	return o, 0
}

func (o *hopOpts) decidesMode() bool { return o.actCD || o.actOpen || o.actReveal || o.actFlag != "" }

// loadHop is load for hop() itself, minus the warnings about an environment value hop() words at its own point.
func loadHop(stderr io.Writer) (*config.Config, error) {
	cfg, err := config.Load(config.Path())
	if err != nil {
		return nil, err
	}
	bad := func(env string, valid []string) bool {
		v := os.Getenv(env)
		return v != "" && !slices.Contains(valid, v)
	}
	for _, w := range cfg.Warnings {
		if strings.HasPrefix(w, "action ") && bad("HOP_ACTION", config.Actions) || strings.HasPrefix(w, "jump ") && bad("HOP_JUMP", config.Jumps) {
			continue
		}
		fmt.Fprintln(stderr, "hop: warning:", w)
	}
	return cfg, nil
}

// termCols is zsh's $COLUMNS for the mode headers: the terminal's width, else COLUMNS, else 80.
func termCols() int {
	if t := tty.Open(); t != nil {
		defer t.Close()
		if w, _, err := term.GetSize(int(t.Fd())); err == nil && w > 0 {
			return w
		}
	}
	if n, err := strconv.Atoi(os.Getenv("COLUMNS")); err == nil && n > 0 {
		return n
	}
	return 80
}

// enterMode is hop()'s _hop_mode: the flags replace HOP_ACTION for this call.
func (o *hopOpts) enterMode(setting string) string {
	m := ""
	switch {
	case o.actFlag != "":
		m = o.actFlag
	case o.actOpen:
		m = "open"
	case o.actReveal:
		m = "reveal"
	}
	if o.actCD {
		if m == "" {
			return "cd"
		}
		return "cd+" + m
	}
	if m == "" {
		return setting
	}
	return m
}

// logicalPWD is zsh's $PWD: the inherited PWD when it still names this dir, else the physical one.
func logicalPWD() string {
	wd, _ := os.Getwd()
	if p := os.Getenv("PWD"); filepath.IsAbs(p) {
		a, errA := os.Stat(p)
		b, errB := os.Stat(".")
		if errA == nil && errB == nil && os.SameFile(a, b) {
			return p
		}
	}
	return wd
}

func gitToplevel() string {
	out, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return ""
	}
	return strings.TrimRight(string(out), "\n")
}

// listRows is _hop_rows: generate, keep what -c keeps, lay that out, then rank by history.
// - The status is hop's: 1 when the kinds list nothing, 2 when nothing is under the -c dir.
func listRows(cfg *config.Config, root, under string, names []string, stderr io.Writer) ([]string, int) {
	debuglog.Printf("generate root=%s kinds=%s", root, strings.Join(names, ","))
	gen := kinds.Generate(cfg, root, names, stderr)
	if len(gen) == 0 {
		return nil, 1
	}
	if under != "" {
		if gen = underRows(gen, under); len(gen) == 0 {
			return nil, 2
		}
	}
	return mru.Rank(renderAll(gen, root), mru.Load(cfg.Settings.HistFile)), 0
}

func haveFzf() bool {
	_, err := exec.LookPath("fzf")
	return err == nil
}

// looksLikePath is the outside-a-repo test for a kind word: the word after it is a path.
func looksLikePath(w string) bool {
	return strings.Contains(w, "/") || strings.HasPrefix(w, "~") || w == "." || w == ".."
}

// renderAll lays rs out as one list; see rows.List.
func renderAll(rs []rows.Row, root string) []string { return rows.List(rs, root, nil) }

// underRows is _hop_filter_under on rows not yet laid out, since hop 0.3 lays out only the rows -c keeps.
func underRows(rs []rows.Row, under string) []rows.Row {
	var out []rows.Row
	for _, r := range rs {
		if r.Dir == under || strings.HasPrefix(r.Dir, under+"/") {
			out = append(out, r)
		}
	}
	return out
}

// session is the state one hop call threads through the levels, as hop()'s dynamic-scope locals.
type session struct {
	cfg            *config.Config
	stdout, stderr io.Writer
	fzf            *match.FZF
	mode, jump     string
	// kword is the kind the first word was read as, hop 0.3.0's `hop file x` for `hop -k file x`.
	kword string
	vim   bool
	cols  int
}

// level is one picker's targets and what its keys can reach: _hop_run's and _hop_res_pick's arguments.
// - root is set only on a targets level, which is what enables the `:` menu and r; folder marks workspace and repo rows.
// - drill and up are the level moves l/ctrl-l and h/ctrl-h make, nil where there is nothing to move to.
// - upFrom finds up only once a picker opens, so a jump never pays for listing every workspace's repos.
type level struct {
	label, root, under string
	targets            []string
	kinds, reload      []string
	folder             bool
	drill              func(dir string) int
	up                 func() int
	upFrom             func() func() int
}

func (s *session) resolver(root, under string) *resolve.Resolver {
	return &resolve.Resolver{Match: s.fzf, Root: root, Action: s.mode, Jump: s.jump, Under: under, Kinds: s.cfg.AllKinds(), Vim: s.vim}
}

// resolveIn is Resolve plus _hop_resolve_log's line, the one every resolve writes.
func (s *session) resolveIn(r *resolve.Resolver, query string, targets []string) resolve.Result {
	t0 := time.Now()
	res := r.Resolve(query, targets)
	debuglog.Printf("resolve tier=%s rule=%s verdict=%s n=%d inj=%d q=%s target=%s ms=%s",
		orDash(res.Tier), orDash(res.Rule), res.Verdict, res.N, res.Inj, query, orDash(res.Target.Rel), since(t0))
	return res
}

func orDash(v string) string {
	if v == "" {
		return "-"
	}
	return v
}

func since(t0 time.Time) string {
	return strconv.FormatFloat(float64(time.Since(t0).Microseconds())/1000, 'f', 1, 64)
}

func (s *session) actor(folder bool) *act.Actor {
	set := s.cfg.Settings
	return &act.Actor{
		Mode: s.mode, Folder: folder, Code: set.Code, Clipboard: set.Clipboard, Hist: set.HistFile, HistMax: set.HistMax,
		Stdout: s.stdout, Stderr: s.stderr, Exec: act.ExecEditor, Terminal: act.DefaultTerminal,
	}
}

// pick is _hop_res_pick then _hop_dispatch: a jump jumps, no terminal reports, and anything else opens fzf.
// - A resolver pick opens ordered, best rows first, and never with --select-1, so one approximate candidate can't accept itself.
// - 130 is esc or ctrl-c, a cancel, which is silent and succeeds, as in hop.
// - ctrl-l and ctrl-h move a level; the levels run in this process, each opening on an empty query.
func (s *session) pick(res resolve.Result, query string, lv level) int {
	a := s.actor(lv.folder)
	if res.Verdict == "jump" {
		if res.Note != "" {
			fmt.Fprintln(s.stderr, res.Note)
		}
		t := res.Target
		return a.Dispatch("", t.Dir, t.Preview, t.Rel)
	}
	if !tty.Available() {
		debuglog.Printf("headless label=%s rows=%d query=%s", lv.label, res.N, query)
		accept, rc := resolve.Report(s.stderr, res, query, s.jump, s.kword)
		if accept {
			t := res.Target
			return a.Dispatch("", t.Dir, t.Preview, t.Rel)
		}
		return rc
	}
	if lv.upFrom != nil {
		lv.up = lv.upFrom()
	}
	o := pick.Opts{
		Self: self(), Label: lv.label, Note: res.Note, Query: res.Query, Height: *s.cfg.Settings.FzfHeight, Reload: lv.reload,
		Legend: pick.Legend(s.mode, lv.folder, len(lv.reload) > 0), Menu: lv.root != "", Drill: lv.drill != nil, Up: lv.up != nil,
		Vim: s.vim, Enter: pick.EnterName(s.mode, lv.folder), Cols: s.cols,
	}
	o.FreezeLeft, o.ShellQuotes = pick.Features(s.fzf.Version())
	input := lv.targets
	switch res.Verdict {
	case "pick":
		o.Ordered = true
		input = res.Input(lv.targets)
	case "empty":
		o.Select1 = s.jump != "never" && s.kword == ""
	}
	sess := &pick.Session{Root: lv.root, Under: lv.under, Kinds: lv.kinds, All: s.cfg.AllKinds(), Keys: o.Keys()}
	out, st, err := pick.Run(s.fzf.Bin, o, sess, input, s.stderr)
	debuglog.Printf("pick label=%s rows=%d query=%s st=%d", lv.label, len(input), query, st)
	switch {
	case err != nil:
		fmt.Fprintln(s.stderr, "hop: fzf:", err)
		return 2
	case st == 130:
		return 0
	case st == 1:
		if query != "" {
			fmt.Fprintln(s.stderr, "hop: no match for:", query)
		} else {
			fmt.Fprintln(s.stderr, "hop: no match")
		}
		return 1
	case st != 0:
		fmt.Fprintf(s.stderr, "hop: fzf exited with status %d\n", st)
		return st
	}
	r, ok := pick.Parse(out)
	if !ok {
		return 0
	}
	switch {
	case r.Key == "ctrl-l" && lv.drill != nil:
		return lv.drill(r.Dir)
	case r.Key == "ctrl-h" && lv.up != nil:
		return lv.up()
	}
	return a.Dispatch(r.Key, r.Dir, r.Preview, r.Rel)
}

// elsewhere runs resolve.Elsewhere over every repo and workspace hop knows; done means the call is over with rc.
func (s *session) elsewhere(query, root, pwd string) (rc int, done bool) {
	set := s.cfg.Settings
	wss := workspace.Parse(set.Workspaces, set.WorkspacesFile)
	var places []resolve.Place
	for _, r := range workspace.RepoList(set.Repos, wss) {
		places = append(places, resolve.Place{Name: filepath.Base(r), Path: r})
	}
	for _, w := range wss {
		places = append(places, resolve.Place{Name: w.Name, Path: w.Path, Workspace: true})
	}
	t0 := time.Now()
	a, hint, ok := resolve.Elsewhere(query, root, pwd, places, s.jump, mru.Load(set.HistFile))
	if ok {
		n := len(a.Rows)
		if a.Res.Verdict == "jump" {
			n = a.Res.N
		}
		debuglog.Printf("resolve tier=T0 rule=elsewhere verdict=%s n=%d inj=0 q=%s target=%s ms=%s", a.Res.Verdict, n, query, orDash(a.Res.Target.Rel), since(t0))
	}
	if !ok {
		if hint != "" {
			fmt.Fprintln(s.stderr, hint)
		}
		return 0, false
	}
	return s.pick(a.Res, query, level{label: fmt.Sprintf("paths  %d found", len(a.Rows)), targets: a.Rows}), true
}

func (s *session) workspaces() []workspace.Workspace {
	set := s.cfg.Settings
	return workspace.Parse(set.Workspaces, set.WorkspacesFile)
}

// repoRows is _hop_repo_targets: rc 1 when no repo is configured or found, 2 when none of them is readable.
func (s *session) repoRows(list []string) ([]string, int) {
	if len(list) == 0 {
		return nil, 1
	}
	rs := renderAll(kinds.RepoRows(list), "")
	if len(rs) == 0 {
		return nil, 2
	}
	return rs, 0
}

func (s *session) allRepos() []string {
	return workspace.RepoList(s.cfg.Settings.Repos, s.workspaces())
}

// wsLevel is _hop_ws_picker: outside a repo, a query no workspace answers exactly is tried on the repos too.
// - l drills into the workspace's own repos, where h comes back here.
func (s *session) wsLevel(query string, fallback bool) int {
	targets := renderAll(kinds.WorkspaceRows(s.workspaces()), "")
	if len(targets) == 0 {
		fmt.Fprintf(s.stderr, "hop: no workspaces configured (edit %s)\n", s.cfg.Settings.WorkspacesFile)
		return 1
	}
	res := s.resolveIn(s.resolver("", ""), query, targets)
	if fallback && res.Verdict != "jump" && res.Verdict != "empty" && res.Tier != "T1" {
		if repos, rc := s.repoRows(s.allRepos()); rc == 0 {
			rr := s.resolveIn(s.resolver("", ""), query, repos)
			if rr.Rank() > res.Rank() {
				return s.pick(rr, query, s.repoLv(repos, s.allRepos, s.upToWorkspaces()))
			}
		}
	}
	back := func() int { return s.wsLevel("", false) }
	return s.pick(res, query, level{
		label: fmt.Sprintf("workspaces  %d", len(targets)), targets: targets, folder: true,
		drill: func(dir string) int {
			return s.reposOf(func() []string { return workspace.Repos(dir) }, back)
		},
	})
}

// upToWorkspaces is h on a repo level reached from the top: the workspace picker, when there is one to go to.
func (s *session) upToWorkspaces() func() int {
	if len(s.workspaces()) == 0 {
		return nil
	}
	return func() int { return s.wsLevel("", false) }
}

// repoLv is a repo level over repos, listed again by list when h comes back to it from a repo's targets.
func (s *session) repoLv(repos []string, list func() []string, up func() int) level {
	back := func() int { return s.reposOf(list, up) }
	return level{
		label: fmt.Sprintf("repos  %d found", len(repos)), targets: repos, folder: true, up: up,
		drill: func(dir string) int { return s.targetsIn(dir, back) },
	}
}

// reposOf opens a repo level, with an empty query, on the repos list names.
func (s *session) reposOf(list func() []string, up func() int) int {
	repos, rc := s.repoRows(list())
	switch rc {
	case 1:
		fmt.Fprintln(s.stderr, "hop: not in a git repository, and no repos found (set $HOP_REPOS)")
		return 1
	case 2:
		fmt.Fprintln(s.stderr, "hop: no readable repos in $HOP_REPOS")
		return 1
	}
	return s.pick(s.resolveIn(s.resolver("", ""), "", repos), "", s.repoLv(repos, list, up))
}

func (s *session) repoLevel(query string) int {
	repos, rc := s.repoRows(s.allRepos())
	switch rc {
	case 1:
		fmt.Fprintln(s.stderr, "hop: not in a git repository, and no repos found (set $HOP_REPOS)")
		return 1
	case 2:
		fmt.Fprintln(s.stderr, "hop: no readable repos in $HOP_REPOS")
		return 1
	}
	return s.pick(s.resolveIn(s.resolver("", ""), query, repos), query, s.repoLv(repos, s.allRepos, s.upToWorkspaces()))
}

// targetsIn is l on a repo row, new in 1.0: that repo's default kinds, with no cd until the final Enter decides.
func (s *session) targetsIn(root string, up func() int) int {
	names := uniqStrings(s.cfg.DefaultKinds())
	if len(names) == 0 {
		fmt.Fprintln(s.stderr, "hop: no kinds selected")
		return 2
	}
	all, st := listRows(s.cfg, root, "", names, s.stderr)
	if st != 0 {
		fmt.Fprintf(s.stderr, "hop: no targets in %s for kinds: %s\n", root, strings.Join(names, ","))
		return 1
	}
	r := s.resolver(root, "")
	r.Like = all[0]
	return s.pick(s.resolveIn(r, "", all), "", s.targetsLv(root, "", all, names, up))
}

func (s *session) targetsLv(root, under string, all, names []string, up func() int) level {
	return level{
		label: fmt.Sprintf("%s  %d targets  %s", filepath.Base(root), len(all), strings.Join(names, ",")),
		root:  root, under: under, targets: all, kinds: names, reload: s.cfg.AllKinds(), up: up,
	}
}

// cmdHop is hop() (hop.zsh:439) up to the picker: T0, then enumerate, rank, resolve, and jump or report.
func cmdHop(args []string, stdout, stderr io.Writer) int {
	o, rc := parseHop(args, stderr)
	if o == nil {
		return rc
	}
	if o.info != "" {
		return info(o.info, stdout, stderr)
	}
	if o.mode == "-" {
		fmt.Fprintln(stderr, "hop: `hop -` is the shell function's own cd -; run `eval \"$(hop init zsh)\"` or your shell's equivalent")
		return 2
	}
	cfg, err := loadHop(stderr)
	if err != nil {
		fmt.Fprintln(stderr, "hop:", err)
		return 1
	}
	set := cfg.Settings
	debuglog.Configure(set.Debug, set.DebugLog)
	// The guard runs in fzf's callbacks, which read the window from the environment, so a [settings] value travels there.
	os.Setenv("HOP_GUARD_WINDOW", set.GuardWindow)
	s := &session{cfg: cfg, stdout: stdout, stderr: stderr, mode: o.enterMode(set.Action), jump: set.Jump, vim: *set.Vim, cols: termCols()}
	if o.vim != nil {
		s.vim = *o.vim
	}
	if o.pick {
		s.jump = "never"
	}
	root := gitToplevel()
	if o.mode == "/" {
		if root == "" {
			fmt.Fprintln(stderr, "hop: not in a git repository")
			return 1
		}
		return act.CD(root, stdout, stderr, set.HistFile, set.HistMax)
	}
	// hop() warns about these where it reads them: after / and -, HOP_ACTION only when no flag chose the mode, HOP_JUMP never under -p.
	if v := os.Getenv("HOP_ACTION"); v != "" && !slices.Contains(config.Actions, v) && !o.decidesMode() {
		fmt.Fprintf(stderr, "hop: HOP_ACTION=%s is not one of %s; using cd\n", v, strings.Join(config.Actions, ", "))
	}
	if v := os.Getenv("HOP_JUMP"); v != "" && !slices.Contains(config.Jumps, v) && !o.pick {
		fmt.Fprintf(stderr, "hop: HOP_JUMP=%s is not one of auto, unique, never; using auto\n", v)
	}
	pwd := logicalPWD()
	names := cfg.DefaultKinds()
	if o.all {
		names = cfg.AllKinds()
	} else if o.kinds != nil {
		names = o.kinds
	}
	names = uniqStrings(names)
	under := ""
	if o.here && root != "" {
		if h, r := realpath(pwd), realpath(root); h != r {
			under = h
		}
	}

	// hop 0.3.0: a first word naming a kind outside the active set, which no row here holds as a whole word, is that kind.
	// - In a repo the kind must have rows here; outside one, the word is read only before a path, which it frees for T0.
	// - The rows listed to decide it are kept, so the resolve below enumerates nothing twice.
	var pre []string
	preSt := -1
	if o.kinds == nil && !o.all && !o.wss && !o.repos && len(o.words) > 0 && haveFzf() {
		w1 := strings.ToLower(o.words[0])
		if slices.Contains(cfg.AllKinds(), w1) && !slices.Contains(names, w1) {
			if root == "" {
				if len(o.words) == 2 && looksLikePath(o.words[1]) {
					s.kword = w1
				}
			} else {
				pre, preSt = listRows(cfg, root, under, names, stderr)
				if resolve.WordUnread(o.words[0], pre) {
					if k, st := listRows(cfg, root, under, []string{w1}, stderr); st == 0 {
						s.kword, pre, preSt = w1, k, 0
					}
				}
			}
		}
		if s.kword != "" {
			fmt.Fprintf(stderr, "hop: reading \"%s\" as -k %s\n", o.words[0], s.kword)
			names, o.words = []string{s.kword}, o.words[1:]
		}
	}

	// T0: a typed path is a filesystem fact, so it jumps before fzf or any enumeration is paid for.
	if !o.wss && !o.repos && len(o.words) == 1 && s.jump != "never" {
		t0 := time.Now()
		if t, ok := resolve.Literal(o.words[0], root, pwd); ok {
			debuglog.Printf("resolve tier=T0 rule=path verdict=jump n=1 inj=0 q=%s target=%s ms=%s", o.words[0], t.Rel, since(t0))
			return s.actor(false).Dispatch("", t.Dir, t.Preview, t.Rel)
		}
	}
	// A one-word path T0 missed may be another repo's (hop 0.3.0), tried only where this repo has nothing for it; never under -c.
	xrepo := !o.wss && !o.repos && len(o.words) == 1 && !o.here

	if s.fzf, err = match.New(stderr); err != nil {
		fmt.Fprintln(stderr, "hop: fzf is not installed")
		return 1
	}
	if err := s.fzf.CheckVersion(set.FzfMin); err != nil {
		fmt.Fprint(stderr, err)
		return 1
	}
	query := strings.Join(o.words, " ")

	if o.wss {
		return s.wsLevel(query, false)
	}
	if o.repos || root == "" {
		if root == "" && xrepo {
			if rc, done := s.elsewhere(query, "", pwd); done {
				return rc
			}
		}
		if root == "" && !o.repos && len(workspace.Parse(set.Workspaces, set.WorkspacesFile)) > 0 {
			return s.wsLevel(query, true)
		}
		return s.repoLevel(query)
	}

	if len(names) == 0 {
		fmt.Fprintln(stderr, "hop: no kinds selected")
		return 2
	}
	all, st := pre, preSt
	if st < 0 {
		all, st = listRows(cfg, root, under, names, stderr)
	}
	if st == 1 && xrepo {
		if rc, done := s.elsewhere(query, root, pwd); done {
			return rc
		}
	}
	switch st {
	case 1:
		fmt.Fprintf(stderr, "hop: no targets in %s for kinds: %s\n", root, strings.Join(names, ","))
		return 1
	case 2:
		fmt.Fprintf(stderr, "hop: no targets under %s for kinds: %s\n", pwd, strings.Join(names, ","))
		return 1
	}
	r := s.resolver(root, under)
	r.Like = all[0]
	res := s.resolveIn(r, query, all)
	if err := r.Err(); err != nil {
		fmt.Fprintln(stderr, "hop:", err)
	}
	if res.Verdict == "none" && xrepo {
		if rc, done := s.elsewhere(query, root, pwd); done {
			return rc
		}
	}
	lv := s.targetsLv(root, under, all, names, nil)
	lv.upFrom = func() func() int {
		if len(s.allRepos()) == 0 {
			return nil
		}
		return func() int { return s.repoLevel("") }
	}
	return s.pick(res, query, lv)
}

func uniqStrings(ss []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range ss {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}

func realpath(p string) string {
	if r, err := filepath.EvalSymlinks(p); err == nil {
		return r
	}
	return p
}

// cmdResolveDump is `hop __resolve-dump`: one query per stdin line against one enumeration, never cd, never history.
// - The default line is query, verdict, tier, rule, rel(target) and n; --full prints testdata/resolve_runner.zsh's line.
// - --stats adds one stderr line with the fzf fork count and the time per query, enumeration excluded.
// - --ms ends each default line with that query's resolve time in ms, T0 included, for per-tier timing.
func cmdResolveDump(args []string, stdout, stderr io.Writer) error {
	full, stats, ms, root, jump := false, false, false, "", ""
	var names []string
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--full":
			full = true
		case a == "--stats":
			stats = true
		case a == "--ms":
			ms = true
		case a == "--root" && i+1 < len(args):
			i++
			root = args[i]
		case a == "--jump" && i+1 < len(args):
			i++
			jump = args[i]
		case a == "-k" && i+1 < len(args):
			i++
			names = splitKinds(args[i])
		default:
			return errUsage
		}
	}
	cfg, err := loadHop(stderr)
	if err != nil {
		return err
	}
	if root == "" {
		if root, err = gitRoot(); err != nil {
			return err
		}
	}
	if jump == "" {
		jump = cfg.Settings.Jump
	}
	if names == nil {
		names = cfg.DefaultKinds()
	}
	fzf, err := match.New(stderr)
	if err != nil {
		return err
	}
	all := mru.Rank(renderAll(kinds.Generate(cfg, root, names, stderr), root), mru.Load(cfg.Settings.HistFile))
	r := &resolve.Resolver{Match: fzf, Root: root, Action: "cd", Jump: jump, Kinds: cfg.AllKinds(), Vim: *cfg.Settings.Vim}
	bw := bufio.NewWriter(stdout)
	defer bw.Flush()
	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 1<<16), 1<<20)
	n, start := 0, time.Now()
	if stats {
		defer func() {
			el := time.Since(start)
			fmt.Fprintf(stderr, "hop: %d queries, %d fzf calls, %.1f ms per query, %.2f fzf calls per query\n",
				n, fzf.Calls, float64(el.Microseconds())/1000/float64(max(n, 1)), float64(fzf.Calls)/float64(max(n, 1)))
		}()
	}
	for sc.Scan() {
		q := sc.Text()
		n++
		began := time.Now()
		res, t0 := resolve.Result{}, false
		if jump != "never" && len(strings.Fields(q)) == 1 {
			if t, ok := resolve.Literal(q, root, root); ok {
				res, t0 = resolve.Result{Verdict: "jump", Tier: "T0", Rule: "path", Target: t, N: 1, M: 1}, true
			}
		}
		if !t0 {
			res = r.Resolve(q, all)
		}
		if !full {
			fmt.Fprintf(bw, "%s\t%s\t%s\t%s\t%s\t%d", q, res.Verdict, res.Tier, res.Rule, res.Target.Rel, res.N)
			if ms {
				fmt.Fprintf(bw, "\t%.3f", float64(time.Since(began).Microseconds())/1000)
			}
			bw.WriteByte('\n')
			continue
		}
		f := []string{q, ".", "cd", jump, "-", res.Verdict, res.Tier, res.Rule, res.Target.Dir, res.Target.Preview, res.Target.Rel,
			strconv.Itoa(res.N), strconv.Itoa(res.M), strconv.Itoa(res.Inj)}
		if t0 {
			f = append(f, "", "", "", "")
		} else {
			rep := ""
			if res.Verdict != "jump" {
				var b strings.Builder
				resolve.Report(&b, res, q, jump, "")
				rep = strings.ReplaceAll(strings.TrimRight(b.String(), "\n"), "\n", `\n`)
			}
			var rels []string
			for _, row := range res.Rows {
				rels = append(rels, resolve.RelOf(row))
			}
			f = append(f, strings.Join(rels, ","), res.Query, res.Note, rep)
		}
		fmt.Fprintln(bw, strings.Join(f, "\t"))
	}
	return sc.Err()
}
