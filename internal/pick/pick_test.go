package pick

import (
	"bytes"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/etknorr/hop/internal/keymap"
	"github.com/etknorr/hop/internal/match"
	"github.com/etknorr/hop/internal/testfix"
)

var update = flag.Bool("update", false, "rewrite testdata/golden/argv.golden")

const self = "/opt/hop dir/bin/hop"

func argvCases() []struct {
	name string
	o    Opts
} {
	legend := Legend("cd", false, true)
	all := []string{"tg", "mod", "helm", "dir", "file"}
	targets := Opts{Self: self, Label: "repo  12 targets  tg,mod", Legend: legend, Height: "80%", Reload: all, Menu: true, Up: true,
		FreezeLeft: true, ShellQuotes: true, Select1: true, Vim: true, Enter: "cd", Cols: 80}
	with := func(o Opts, f func(*Opts)) Opts { f(&o); return o }
	return []struct {
		name string
		o    Opts
	}{
		{"NORMAL start", targets},
		{"-c", with(targets, func(o *Opts) { o.Label = "repo  3 targets  tg,mod" })},
		{"SEARCH start", with(targets, func(o *Opts) {
			o.Label, o.Query, o.Ordered, o.Select1, o.FreezeLeft = "repo  4 targets  helm", "web", true, false, false
		})},
		{"--action=open with a note", with(targets, func(o *Opts) {
			o.Legend, o.Enter, o.Note, o.Query, o.Ordered, o.Select1 = Legend("open", false, true), "open", "ignored: zzqx", "vpc", true, false
		})},
		{"wide", with(targets, func(o *Opts) { o.Cols = 200 })},
		{"HOP_FZF_HEIGHT=", with(targets, func(o *Opts) { o.Height = "" })},
		{"HOP_VIM=0", with(targets, func(o *Opts) { o.Vim = false })},
		{"HOP_VIM=0 SEARCH", with(targets, func(o *Opts) { o.Vim, o.Query, o.Note = false, "web", "nothing close to: web (ctrl-u clears)" })},
		{"workspace level", Opts{Self: self, Label: "workspaces  4", Legend: Legend("reveal", true, false), Height: "80%", Drill: true, ShellQuotes: true,
			Select1: true, Vim: true, Enter: EnterName("reveal", true), Cols: 80}},
		{"repo level", Opts{Self: self, Label: "repos  9 found", Legend: Legend("cd", true, false), Height: "80%", Drill: true, Up: true, ShellQuotes: true,
			Select1: true, Vim: true, Enter: "cd", Cols: 80}},
		{"repo level HOP_VIM=0", Opts{Self: self, Label: "repos  9 found", Legend: Legend("cd", true, false), Height: "80%", Drill: true, Up: true, ShellQuotes: true,
			Select1: true, Enter: "cd", Cols: 80}},
	}
}

func renderArgv() string {
	var b strings.Builder
	for _, c := range argvCases() {
		fmt.Fprintf(&b, "== %s\n", c.name)
		for _, a := range Args(c.o) {
			b.WriteString(strconv.Quote(a) + "\n")
		}
	}
	return b.String()
}

func TestArgvGolden(t *testing.T) {
	path := filepath.Join(testfix.ModuleRoot(), "testdata", "golden", "argv.golden")
	got := renderArgv()
	if *update {
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if got != string(want) {
		t.Errorf("argv differs from %s; rerun with -update after checking the change\n%s", path, got)
	}
}

// TestArgvParses runs every argv through the real fzf: --filter parses the whole command line, binds included, and exits 0 on a match.
func TestArgvParses(t *testing.T) {
	fzf, err := exec.LookPath("fzf")
	if err != nil {
		t.Skip("no fzf")
	}
	run := func(args []string) (int, string) {
		c := exec.Command(fzf, append(args, "--filter=x")...)
		c.Env = append(os.Environ(), "FZF_DEFAULT_OPTS=", "FZF_DEFAULT_OPTS_FILE=")
		c.Stdin = strings.NewReader("x\t/d\t/d\tx/\n")
		var errb bytes.Buffer
		c.Stderr = &errb
		err := c.Run()
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode(), errb.String()
		}
		return 0, errb.String()
	}
	// hop passes --freeze-left only from fzf 0.67.0, as the fzf under test would see it.
	old := (&match.FZF{Bin: fzf}).Version()
	frozen := old != "" && !match.Less(old, "0.67.0")
	quotes := old != "" && !match.Less(old, "0.71.0")
	for _, c := range argvCases() {
		c.o.FreezeLeft = c.o.FreezeLeft && frozen
		c.o.ShellQuotes = c.o.ShellQuotes && quotes
		if rc, msg := run(Args(c.o)); rc != 0 || msg != "" {
			t.Errorf("%s: fzf %s rc %d: %s", c.name, old, rc, msg)
		}
	}
	first := argvCases()[0].o
	first.FreezeLeft = frozen
	bad := append(Args(first), "--bind=alt-z:no-such-action")
	if rc, msg := run(bad); rc != 2 || !strings.Contains(msg, "unknown action") {
		t.Errorf("control: a bogus action must fail the parse, got rc %d %q", rc, msg)
	}
}

func TestArgvShape(t *testing.T) {
	cases := argvCases()
	a := strings.Join(Args(cases[0].o), "\n")
	for _, want := range []string{"--expect=ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y,ctrl-h", "--bind=alt-B:print(ctrl-g)+accept", "--bind=ctrl-/:toggle-preview",
		"--bind=alt-p:toggle-preview", "--bind=alt-a:reload(hop __rows tg mod helm dir file)", "--bind=alt-enter:transform:hop __key alt-enter",
		"--with-shell='/opt/hop dir/bin/hop' __sh", "--preview=hop __preview {2} {3}", "--height=80%", "--disabled", "--prompt=> ",
		"--bind=esc:transform:hop __key esc", "--bind=enter:transform:hop __key enter {2}", "--bind=o:transform:hop __guard check o",
		"--bind=alt-]:execute-silent(hop __guard mark)", "--bind=j:down+" + keymap.Restore, "--bind=r:reload(hop __rows)",
		"--bind=l:ignore", "--bind=h:transform:hop __guard check h", "--bind=(:ignore", "--bind=):ignore"} {
		if !strings.Contains(a, want+"\n") {
			t.Errorf("argv lacks %q", want)
		}
	}
	for _, unwanted := range []string{"--bind=alt-k:change", "--bind=alt-a:execute-silent", "--bind=alt-o:execute-silent", "--bind=alt-B:execute-silent"} {
		if strings.Contains(a, unwanted) {
			t.Errorf("argv holds %q", unwanted)
		}
	}
	for _, c := range cases {
		for _, x := range Args(c.o) {
			if strings.Contains(x, "/opt/hop") && !strings.HasPrefix(x, "--with-shell=") {
				t.Errorf("%s: only --with-shell may hold a path: %q", c.name, x)
			}
		}
	}
	plain := strings.Join(Args(cases[6].o), "\n")
	for _, x := range []string{"--disabled", "__key", "__guard", "--bind=j:"} {
		if strings.Contains(plain, x) {
			t.Errorf("HOP_VIM=0 is plain fzf, but its argv holds %q", x)
		}
	}
	if !strings.Contains(plain, "--prompt="+Prompt) || !strings.Contains(plain, "--bind=alt-enter:print(alt-enter)+accept") {
		t.Error("HOP_VIM=0 keeps the hop prompt and a plain alt-enter")
	}
	if s := strings.Join(Args(cases[2].o), "\n"); !strings.Contains(s, "--prompt=/ ") || strings.Contains(s, "--disabled") ||
		!strings.Contains(s, "--bind=start:"+keymap.UnbindAll+"+enable-search") {
		t.Error("a CLI query starts in SEARCH, filtering")
	}
	if s := Args(cases[3].o); !strings.HasPrefix(s[len(s)-1], "--header=ignored: zzqx\nSEARCH") {
		t.Errorf("a resolver note stays above the SEARCH header: %q", s[len(s)-1])
	}
	ws := strings.Join(Args(cases[8].o), "\n")
	for _, want := range []string{"--expect=ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y,ctrl-l\n", "--bind=l:transform:hop __guard check l\n", "--bind=h:ignore\n",
		"--bind=r:ignore\n", "--bind=::ignore\n", "--bind=alt-enter:print(alt-enter)+accept\n", "enter open  c cd  q quit"} {
		if !strings.Contains(ws, want) {
			t.Errorf("workspace level lacks %q", want)
		}
	}
	if strings.Contains(ws, "--bind=enter:") || strings.Contains(ws, ": view") {
		t.Error("the workspace level has no menu, so enter is fzf's and the header names no view")
	}
	if s := strings.Join(Args(cases[10].o), "\n"); !strings.Contains(s, "--expect=ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y,ctrl-l,ctrl-h\n") {
		t.Error("ctrl-l and ctrl-h are --expect keys with the modal layer off too")
	}
	fs := strings.Join(Args(cases[5].o), "\n")
	if strings.Contains(fs, "--height") {
		t.Error("HOP_FZF_HEIGHT set but empty is fullscreen, so no --height")
	}
	for _, c := range []struct {
		self   string
		quotes bool
		want   string
	}{
		{"/usr/local/bin/hop", false, "/usr/local/bin/hop __sh"},
		{"/home/a.b/go/bin/hop", true, "/home/a.b/go/bin/hop __sh"},
		{"/a/it's/hop", true, `'/a/it'\''s/hop' __sh`},
		{"/opt/hop dir/bin/hop", true, `'/opt/hop dir/bin/hop' __sh`},
		{"/opt/hop dir/bin/hop", false, "hop __sh"},
	} {
		if got := WithShell(c.self, c.quotes); got != c.want {
			t.Errorf("WithShell(%q, %v) = %q, want %q", c.self, c.quotes, got, c.want)
		}
	}
}

func TestLegend(t *testing.T) {
	for _, c := range []struct {
		mode           string
		folder, reload bool
		want           string
	}{
		{"cd", false, false, "enter cd · ^O file · ^T folder\n^Y copy · M-y copy file · M-o edit\nM-B github · M-p preview"},
		{"cd", false, true, "enter cd · ^O file · ^T folder\n^Y copy · M-y copy file · M-o edit\nM-B github · M-a all · M-p preview"},
		{"cd+open", false, true, "enter cd+open · M-enter cd\n^O file · ^T folder · ^Y copy\nM-y copy file · M-o edit\nM-B github · M-a all · M-p preview"},
		{"reveal", true, false, "enter open · M-enter cd\n^O file · ^T folder · ^Y copy\nM-y copy file · M-o edit\nM-B github · M-p preview"},
	} {
		if got := Legend(c.mode, c.folder, c.reload); got != c.want {
			t.Errorf("Legend(%s): %q", c.mode, got)
		}
		for _, l := range strings.Split(Legend(c.mode, c.folder, c.reload), "\n") {
			if n := len([]rune(l)); n > 35 {
				t.Errorf("legend line %q is %d columns, over 35", l, n)
			}
		}
	}
}

func TestParse(t *testing.T) {
	for _, c := range []struct {
		out  string
		want Result
		ok   bool
	}{
		{"\n/r/a\t/r/a/main.tf\t\x1b[2ma/\x1b[0m\n", Result{"", "/r/a", "/r/a/main.tf", "a/"}, true},
		{"ctrl-o\n/r/a\t/r/a/x\ta/\n", Result{"ctrl-o", "/r/a", "/r/a/x", "a/"}, true},
		{"\nctrl-g\n/r/a\t/r/a/x\ta/\n", Result{"ctrl-g", "/r/a", "/r/a/x", "a/"}, true},
		{"\n/r/a\t\ta/\n", Result{"", "/r/a", "/r/a", "a/"}, true},
		{"\n/r/a\n", Result{"", "/r/a", "/r/a", ""}, true},
		{"\n\n", Result{}, false},
		{"", Result{}, false},
	} {
		got, ok := Parse(c.out)
		if ok != c.ok || got != c.want {
			t.Errorf("Parse(%q) = %+v %v, want %+v %v", c.out, got, ok, c.want, c.ok)
		}
	}
}

func TestSplitWords(t *testing.T) {
	for in, want := range map[string][]string{
		`hop __preview '/a b/c' '/it'\''s'`: {"hop", "__preview", "/a b/c", "/it's"},
		`hop __key enter 'helm'`:            {"hop", "__key", "enter", "helm"},
		`echo "a \"b\" \$c" x\ y`:           {"echo", `a "b" $c`, "x y"},
		`hop __preview '' ''`:               {"hop", "__preview", "", ""},
	} {
		got, err := SplitWords(in)
		if err != nil || strings.Join(got, "|") != strings.Join(want, "|") {
			t.Errorf("SplitWords(%q) = %q %v", in, got, err)
		}
	}
	if _, err := SplitWords(`a 'b`); err == nil {
		t.Error("an unterminated quote is an error")
	}
}

func TestShim(t *testing.T) {
	var got []string
	disp := func(a []string) int { got = a; return 7 }
	var out, errb bytes.Buffer
	if rc := Shim(`hop __preview '/a b' '/c'`, disp, &out, &errb); rc != 7 || strings.Join(got, "|") != "__preview|/a b|/c" {
		t.Errorf("a hop callback dispatches in process: rc %d %q", rc, got)
	}
	got = nil
	t.Setenv("SHELL", "/bin/sh")
	if rc := Shim(`printf '%s' "$((6*7))"; exit 3`, disp, &out, &errb); rc != 3 || got != nil || out.String() != "42" {
		t.Errorf("anything else runs in $SHELL: rc %d out %q", rc, out.String())
	}
	out.Reset()
	if rc := Shim(`hopy __preview x`, disp, &out, &errb); got != nil || rc == 7 {
		t.Error("only the word hop dispatches in process")
	}
}

func TestSession(t *testing.T) {
	s := &Session{Root: "/r)x", Under: "/r)x/a", Kinds: []string{"tg"}, All: []string{"tg", "mod"}, Keys: keymap.Map{Enter: "open", Menu: true, Cols: 99}}
	dir, p, err := s.Write()
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(dir)
	if st, _ := os.Stat(p); st.Mode().Perm() != 0o600 {
		t.Errorf("session mode %v", st.Mode().Perm())
	}
	t.Setenv("HOP_SESSION", p)
	got, err := Load()
	if err != nil || got.Root != s.Root || got.Under != s.Under || got.Keys != s.Keys || len(got.All) != 2 {
		t.Errorf("round trip: %+v %v", got, err)
	}
	if got.Current()[0] != "tg" {
		t.Error("with no view switched, the current view is the opening kinds")
	}
	got.View = []string{"mod"}
	if err := got.Save(); err != nil {
		t.Fatal(err)
	}
	if again, _ := Load(); again.Current()[0] != "mod" || again.Root != s.Root {
		t.Errorf("a saved view survives the next callback's load: %+v", again)
	}
	stale := filepath.Join(filepath.Dir(dir), "hop-pick-stale")
	os.Mkdir(stale, 0o700)
	old := time.Now().Add(-25 * time.Hour)
	os.Chtimes(stale, old, old)
	fresh, _, _ := s.Write()
	defer os.RemoveAll(fresh)
	if _, err := os.Stat(stale); err == nil {
		os.RemoveAll(stale)
		t.Error("a day-old picker directory, as SIGKILL leaves, is reaped by the next picker")
	}
	t.Setenv("HOP_SESSION", "")
	if _, err := Load(); err == nil {
		t.Error("no session outside a picker")
	}
}

func TestPreview(t *testing.T) {
	t.Setenv("PATH", "/usr/bin:/bin")
	root := t.TempDir()
	os.Mkdir(filepath.Join(root, ".git"), 0o755)
	unit := filepath.Join(root, "svc", "web")
	os.MkdirAll(filepath.Join(unit, "sub"), 0o755)
	os.WriteFile(filepath.Join(unit, "README.md"), []byte("# web\nline 2"), 0o644)
	os.WriteFile(filepath.Join(unit, ".hidden"), nil, 0o644)
	empty := filepath.Join(root, "empty")
	os.Mkdir(empty, 0o755)
	var long strings.Builder
	for i := range 450 {
		fmt.Fprintf(&long, "%d\n", i)
	}
	os.WriteFile(filepath.Join(root, "long.txt"), []byte(long.String()), 0o644)

	pv := func(dir, target string) string {
		var b bytes.Buffer
		Preview(&b, dir, target)
		return b.String()
	}
	if got, want := pv(unit, filepath.Join(unit, "README.md")), hdr+"svc/web"+off+"\n"+sub+"svc/web/README.md"+off+"\n"+rule+"\n# web\nline 2"; got != want {
		t.Errorf("file preview:\n%q\nwant\n%q", got, want)
	}
	if got, want := pv(unit, unit), hdr+"svc/web"+off+"\n"+sub+"directory listing"+off+"\n"+rule+"\n.hidden\nREADME.md\n"+hdr+"sub/"+off+"\n"; got != want {
		t.Errorf("dir preview:\n%q\nwant\n%q", got, want)
	}
	if got := pv(empty, ""); !strings.HasSuffix(got, sub+"(empty)"+off+"\n") {
		t.Errorf("empty dir: %q", got)
	}
	if got := pv(root, filepath.Join(root, "long.txt")); strings.Count(got, "\n") != 3+400 || !strings.HasSuffix(got, "399\n") {
		t.Errorf("a long file stops at 400 lines: %d lines", strings.Count(got, "\n"))
	}
	if got := pv(unit, filepath.Join(unit, "gone")); !strings.Contains(got, "no preview: svc/web/gone does not exist") {
		t.Errorf("missing target: %q", got)
	}
	if got := pv("", ""); !strings.Contains(got, "nothing to preview") {
		t.Errorf("no arguments: %q", got)
	}
}
