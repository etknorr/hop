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

	"github.com/etknorr/hop/internal/testfix"
)

var update = flag.Bool("update", false, "rewrite testdata/golden/argv.golden")

const self = "/opt/hop dir/bin/hop"

func argvCases() []struct {
	name string
	o    Opts
} {
	legend := Legend("cd", false, true, true)
	all := []string{"tg", "mod", "helm", "dir", "file"}
	return []struct {
		name string
		o    Opts
	}{
		{"default", Opts{Self: self, Label: "repo  12 targets  tg,mod", Legend: legend, Height: "80%", Reload: all, Menu: true, FreezeLeft: true, Select1: true}},
		{"-c", Opts{Self: self, Label: "repo  3 targets  tg,mod", Legend: legend, Height: "80%", Reload: all, Menu: true, FreezeLeft: true, Select1: true}},
		{"-k helm", Opts{Self: self, Label: "repo  4 targets  helm", Legend: legend, Height: "80%", Reload: all, Menu: true, FreezeLeft: true, Query: "web", Ordered: true}},
		{"--action=open", Opts{Self: self, Label: "repo  12 targets  tg,mod", Legend: Legend("open", false, true, true), Height: "80%", Reload: all, Menu: true, Note: "ignored: zzqx", Query: "vpc", Ordered: true}},
		{"HOP_FZF_HEIGHT=", Opts{Self: self, Label: "repo  12 targets  tg,mod", Legend: legend, Reload: all, Menu: true, Select1: true}},
		{"-w", Opts{Self: self, Label: "workspaces  4", Legend: Legend("reveal", true, false, false), Height: "80%"}},
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
	for _, c := range argvCases() {
		if rc, msg := run(Args(c.o)); rc != 0 || msg != "" {
			t.Errorf("%s: fzf rc %d: %s", c.name, rc, msg)
		}
	}
	bad := append(Args(argvCases()[0].o), "--bind=alt-z:no-such-action")
	if rc, msg := run(bad); rc != 2 || !strings.Contains(msg, "unknown action") {
		t.Errorf("control: a bogus action must fail the parse, got rc %d %q", rc, msg)
	}
}

func TestArgvShape(t *testing.T) {
	a := strings.Join(Args(argvCases()[0].o), "\n")
	for _, want := range []string{"--expect=ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y", "--bind=alt-B:print(ctrl-g)+accept", "--bind=ctrl-/:toggle-preview",
		"--bind=alt-p:toggle-preview", "--bind=alt-a:reload(hop __rows tg mod helm dir file)", "--bind=alt-k:" + MenuOpen,
		"--with-shell='/opt/hop dir/bin/hop' __sh", "--preview=hop __preview {2} {3}", "--height=80%"} {
		if !strings.Contains(a, want) {
			t.Errorf("argv lacks %q", want)
		}
	}
	for _, c := range argvCases() {
		for _, x := range Args(c.o) {
			if strings.Contains(x, "/opt/hop") && !strings.HasPrefix(x, "--with-shell=") {
				t.Errorf("%s: only --with-shell may hold a path: %q", c.name, x)
			}
		}
	}
	fs := strings.Join(Args(argvCases()[4].o), "\n")
	if strings.Contains(fs, "--height") {
		t.Error("HOP_FZF_HEIGHT set but empty is fullscreen, so no --height")
	}
	if WithShell("/a/it's/hop") != `'/a/it'\''s/hop' __sh` {
		t.Error("a quote in the binary path must survive --with-shell")
	}
}

func TestLegend(t *testing.T) {
	for _, c := range []struct {
		mode                 string
		folder, reload, menu bool
		want                 string
	}{
		{"cd", false, false, false, "enter cd · ^O file · ^T folder\n^Y copy · M-y copy file · M-o edit\nM-B github · M-p preview"},
		{"cd+open", false, true, true, "enter cd+open · M-enter cd\n^O file · ^T folder · ^Y copy\nM-y copy file · M-o edit\nM-B github · M-p preview\nM-a all kinds · M-k kind menu"},
		{"reveal", true, false, false, "enter open · M-enter cd\n^O file · ^T folder · ^Y copy\nM-y copy file · M-o edit\nM-B github · M-p preview"},
	} {
		if got := Legend(c.mode, c.folder, c.reload, c.menu); got != c.want {
			t.Errorf("Legend(%s): %q", c.mode, got)
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

func TestKey(t *testing.T) {
	s := &Session{Kinds: []string{"tg", "mod"}, All: []string{"tg", "mod", "helm"}}
	t.Setenv("FZF_PROMPT", Prompt)
	if Key(s, "enter", "/r/a") != "accept" || Key(s, "esc", "") != "abort" || Key(s, "alt-enter", "") != "print(alt-enter)+accept" {
		t.Error("on the target list, enter accepts, esc aborts and alt-enter cds")
	}
	t.Setenv("FZF_PROMPT", MenuPrompt)
	if got := Key(s, "enter", "helm"); got != "clear-query+reload(hop __rows helm)+change-prompt("+Prompt+")+transform-header(hop __header)+first" {
		t.Errorf("menu enter: %q", got)
	}
	if got := Key(s, "esc", ""); !strings.HasPrefix(got, "clear-query+reload(hop __rows tg mod)+") {
		t.Errorf("menu esc restores the opening kinds: %q", got)
	}
	if Key(s, "enter", "nope") != "ignore" || Key(s, "alt-enter", "") != "ignore" || Key(s, "bogus", "") != "ignore" {
		t.Error("an unknown kind, alt-enter in the menu and an unknown key are ignored")
	}
}

func TestSession(t *testing.T) {
	s := &Session{Root: "/r)x", Under: "/r)x/a", Kinds: []string{"tg"}, All: []string{"tg", "mod"}, Header: "note\nlegend"}
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
	if err != nil || got.Root != s.Root || got.Under != s.Under || got.Header != s.Header || len(got.All) != 2 {
		t.Errorf("round trip: %+v %v", got, err)
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
