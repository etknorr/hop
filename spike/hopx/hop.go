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

	"github.com/etknorr/hop/spike/hopx/internal/act"
	"github.com/etknorr/hop/spike/hopx/internal/config"
	"github.com/etknorr/hop/spike/hopx/internal/kinds"
	"github.com/etknorr/hop/spike/hopx/internal/match"
	"github.com/etknorr/hop/spike/hopx/internal/mru"
	"github.com/etknorr/hop/spike/hopx/internal/pick"
	"github.com/etknorr/hop/spike/hopx/internal/resolve"
	"github.com/etknorr/hop/spike/hopx/internal/rows"
	"github.com/etknorr/hop/spike/hopx/internal/tty"
	"github.com/etknorr/hop/spike/hopx/internal/workspace"
)

// hopOpts is hop()'s parsed command line.
type hopOpts struct {
	words                       []string
	kinds                       []string
	all, repos, wss, here, pick bool
	actCD, actOpen, actReveal   bool
	actFlag, mode               string
}

// parseHop is hop()'s option loop (hop.zsh:458), with its exit-2 rules.
func parseHop(args []string, stderr io.Writer) (*hopOpts, int) {
	o := &hopOpts{}
	opts := false
	for len(args) > 0 {
		a := args[0]
		switch {
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

func renderAll(rs []rows.Row, root string) []string {
	out := make([]string, len(rs))
	for i, r := range rs {
		out[i] = rows.Render(r, root)
	}
	return out
}

// session is the state one hopx call threads through the levels, as hop()'s dynamic-scope locals.
type session struct {
	cfg            *config.Config
	stdout, stderr io.Writer
	fzf            *match.FZF
	mode, jump     string
}

// level is one picker's targets and what its keys can reach: _hop_run's and _hop_res_pick's arguments.
// - root is set only on the kinds level, which is what enables the alt-k menu; folder marks workspace and repo rows.
type level struct {
	label, root, under string
	targets            []string
	kinds, reload      []string
	folder             bool
}

func (s *session) resolver(root, under string) *resolve.Resolver {
	return &resolve.Resolver{Match: s.fzf, Root: root, Action: s.mode, Jump: s.jump, Under: under, Kinds: s.cfg.AllKinds()}
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
// - 130 is a cancel and stays silent; hop returns 0 there, the spec's cd protocol says 130.
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
		accept, rc := resolve.Report(s.stderr, res, query, s.jump)
		if accept {
			t := res.Target
			return a.Dispatch("", t.Dir, t.Preview, t.Rel)
		}
		return rc
	}
	o := pick.Opts{
		Self: self(), Label: lv.label, Note: res.Note, Query: res.Query, Height: *s.cfg.Settings.FzfHeight, Reload: lv.reload,
		Legend: pick.Legend(s.mode, lv.folder, len(lv.reload) > 0, lv.root != ""), Menu: lv.root != "",
	}
	if v := s.fzf.Version(); v != "" && !match.Less(v, "0.67.0") {
		o.FreezeLeft = true
	}
	input := lv.targets
	switch res.Verdict {
	case "pick":
		o.Ordered = true
		input = res.Input(lv.targets)
	case "empty":
		o.Select1 = s.jump != "never"
	}
	sess := &pick.Session{Root: lv.root, Under: lv.under, Kinds: lv.kinds, All: s.cfg.AllKinds(), Header: o.Header()}
	out, st, err := pick.Run(s.fzf.Bin, o, sess, input, s.stderr)
	switch {
	case err != nil:
		fmt.Fprintln(s.stderr, "hopx: fzf:", err)
		return 2
	case st == 130:
		return 130
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
	return a.Dispatch(r.Key, r.Dir, r.Preview, r.Rel)
}

func (s *session) repoRows() []string {
	set := s.cfg.Settings
	return renderAll(kinds.RepoRows(workspace.RepoList(set.Repos, workspace.Parse(set.Workspaces, set.WorkspacesFile))), "")
}

// wsLevel is _hop_ws_picker: outside a repo, a query no workspace answers exactly is tried on the repos too.
func (s *session) wsLevel(query string, fallback bool) int {
	set := s.cfg.Settings
	targets := renderAll(kinds.WorkspaceRows(workspace.Parse(set.Workspaces, set.WorkspacesFile)), "")
	if len(targets) == 0 {
		fmt.Fprintf(s.stderr, "hop: no workspaces configured (edit %s)\n", set.WorkspacesFile)
		return 1
	}
	res := s.resolver("", "").Resolve(query, targets)
	if fallback && res.Verdict != "jump" && res.Verdict != "empty" && res.Tier != "T1" {
		if repos := s.repoRows(); len(repos) > 0 {
			rr := s.resolver("", "").Resolve(query, repos)
			if rr.Rank() > res.Rank() {
				return s.pick(rr, query, repoLevel(repos))
			}
		}
	}
	return s.pick(res, query, level{label: fmt.Sprintf("workspaces  %d", len(targets)), targets: targets, folder: true})
}

func repoLevel(repos []string) level {
	return level{label: fmt.Sprintf("repos  %d found", len(repos)), targets: repos, folder: true}
}

func (s *session) repoLevel(query string) int {
	repos := s.repoRows()
	if len(repos) == 0 {
		fmt.Fprintln(s.stderr, "hop: not in a git repository, and no repos found (set $HOP_REPOS)")
		return 1
	}
	return s.pick(s.resolver("", "").Resolve(query, repos), query, repoLevel(repos))
}

// cmdHop is hop() (hop.zsh:439) up to the picker: T0, then enumerate, rank, resolve, and jump or report.
func cmdHop(args []string, stdout, stderr io.Writer) int {
	o, rc := parseHop(args, stderr)
	if o == nil {
		return rc
	}
	if o.mode == "-" {
		fmt.Fprintln(stderr, "hopx: `hopx -` is the shell function's own cd -; run `eval \"$(hopx init zsh)\"` or your shell's equivalent")
		return 2
	}
	cfg, err := load(stderr)
	if err != nil {
		fmt.Fprintln(stderr, "hopx:", err)
		return 1
	}
	set := cfg.Settings
	s := &session{cfg: cfg, stdout: stdout, stderr: stderr, mode: o.enterMode(set.Action), jump: set.Jump}
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
	pwd := logicalPWD()

	// T0: a typed path is a filesystem fact, so it jumps before fzf or any enumeration is paid for.
	if !o.wss && !o.repos && len(o.words) == 1 && s.jump != "never" {
		if t, ok := resolve.Literal(o.words[0], root, pwd); ok {
			return s.actor(false).Dispatch("", t.Dir, t.Preview, t.Rel)
		}
	}

	if s.fzf, err = match.New(stderr); err != nil {
		fmt.Fprintln(stderr, "hop: fzf is not installed")
		return 1
	}
	if err := s.fzf.CheckVersion(); err != nil {
		fmt.Fprintln(stderr, "hopx:", err)
		return 1
	}
	query := strings.Join(o.words, " ")

	if o.wss {
		return s.wsLevel(query, false)
	}
	if o.repos || root == "" {
		if root == "" && !o.repos && len(workspace.Parse(set.Workspaces, set.WorkspacesFile)) > 0 {
			return s.wsLevel(query, true)
		}
		return s.repoLevel(query)
	}

	names := cfg.DefaultKinds()
	if o.all {
		names = cfg.AllKinds()
	} else if o.kinds != nil {
		names = o.kinds
	}
	names = uniqStrings(names)
	if len(names) == 0 {
		fmt.Fprintln(stderr, "hop: no kinds selected")
		return 2
	}
	under := ""
	if o.here {
		if h, r := realpath(pwd), realpath(root); h != r {
			under = h
		}
	}
	all := renderAll(kinds.Generate(cfg, root, names, stderr), root)
	if len(all) == 0 {
		fmt.Fprintf(stderr, "hop: no targets in %s for kinds: %s\n", root, strings.Join(names, ","))
		return 1
	}
	if under != "" {
		if all = resolve.FilterUnder(all, under); len(all) == 0 {
			fmt.Fprintf(stderr, "hop: no targets under %s for kinds: %s\n", pwd, strings.Join(names, ","))
			return 1
		}
	}
	all = mru.Rank(all, mru.Load(set.HistFile))
	r := s.resolver(root, under)
	res := r.Resolve(query, all)
	if err := r.Err(); err != nil {
		fmt.Fprintln(stderr, "hopx:", err)
	}
	return s.pick(res, query, level{
		label: fmt.Sprintf("%s  %d targets  %s", filepath.Base(root), len(all), strings.Join(names, ",")),
		root:  root, under: under, targets: all, kinds: names, reload: cfg.AllKinds(),
	})
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

// cmdResolveDump is `hopx __resolve-dump`: one query per stdin line against one enumeration, never cd, never history.
// - The default line is query, verdict, tier, rule, rel(target) and n; --full prints testdata/resolve_runner.zsh's line.
// - --stats adds one stderr line with the fzf fork count and the time per query, enumeration excluded.
func cmdResolveDump(args []string, stdout, stderr io.Writer) error {
	full, stats, root, jump := false, false, "", ""
	var names []string
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--full":
			full = true
		case a == "--stats":
			stats = true
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
	cfg, err := load(stderr)
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
	r := &resolve.Resolver{Match: fzf, Root: root, Action: "cd", Jump: jump, Kinds: cfg.AllKinds()}
	bw := bufio.NewWriter(stdout)
	defer bw.Flush()
	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 1<<16), 1<<20)
	n, start := 0, time.Now()
	if stats {
		defer func() {
			el := time.Since(start)
			fmt.Fprintf(stderr, "hopx: %d queries, %d fzf calls, %.1f ms per query, %.2f fzf calls per query\n",
				n, fzf.Calls, float64(el.Microseconds())/1000/float64(max(n, 1)), float64(fzf.Calls)/float64(max(n, 1)))
		}()
	}
	for sc.Scan() {
		q := sc.Text()
		n++
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
			fmt.Fprintf(bw, "%s\t%s\t%s\t%s\t%s\t%d\n", q, res.Verdict, res.Tier, res.Rule, res.Target.Rel, res.N)
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
				resolve.Report(&b, res, q, jump)
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
