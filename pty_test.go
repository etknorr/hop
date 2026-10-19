//go:build darwin || linux

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/etknorr/hop/internal/match"
	"github.com/etknorr/hop/internal/ptytest"
	"github.com/etknorr/hop/internal/rows"
	"github.com/etknorr/hop/internal/testfix"
)

// picker is a built hop on the match fixture, run under a real pty the way a shell function would run it.
//   - The stubs log what each verb would have launched: code, gh, the editor and the clipboard.
//   - list is the fixture's default rows, in the order an empty query shows them with no history.
//   - The config is written here rather than read from testdata, because run-all.sh runs this in a container
//     where the module may not be mounted, and a missing config silently loads every preset instead.
type picker struct {
	bin, root, tmp, stub, cfg string
	list                      []string
}

const pickerConfig = `[[kind]]
name = 'tg'
desc = 'terragrunt units'
default = true
marker = 'terragrunt.hcl'
under = 'terraform'
layout = ['scope,env,region,name...', 'scope,name...']
trim = { scope = 'acct-', env = 'env-' }
preview = ['main.tf', '*.tf', 'terragrunt.hcl', 'README.md']

[[kind]]
name = 'mesos'
desc = 'mesos services'
default = true
dirs = ['mesos/services']
scope = '-'
preview = ['service.conf']

[[kind]]
name = 'sbx'
desc = 'sandbox dirs'
dirs = ['sandbox']

[[kind]]
name = 'dir'
desc = 'repo root and top-level dirs'
default = true
builtin = 'dir'
`

func newPicker(t *testing.T) *picker {
	t.Helper()
	if _, err := exec.LookPath("fzf"); err != nil {
		t.Skip("fzf not installed")
	}
	tmp := testfix.Resolved(t.TempDir())
	p := &picker{bin: os.Getenv("HOP_TEST_BIN"), root: filepath.Join(tmp, "repo"), tmp: tmp, stub: filepath.Join(tmp, "stub")}
	if p.bin == "" {
		p.bin = filepath.Join(tmp, "hop")
		if out, err := exec.Command("go", "build", "-o", p.bin, ".").CombinedOutput(); err != nil {
			t.Fatalf("go build: %v\n%s", err, out)
		}
	}
	if err := testfix.BuildMatch(p.root); err != nil {
		t.Fatal(err)
	}
	p.cfg = filepath.Join(tmp, "picker.toml")
	if err := os.WriteFile(p.cfg, []byte(pickerConfig), 0o644); err != nil {
		t.Fatal(err)
	}
	os.Mkdir(p.stub, 0o755)
	for name, body := range map[string]string{
		"pbcopy": `cat >"$T/clip"`,
		"code":   `echo "code $*" >>"$T/code"`,
		"gh":     `echo "gh $PWD $*" >>"$T/gh"`,
		"ed":     `echo "ed $*" >>"$T/ed"`,
	} {
		os.WriteFile(filepath.Join(p.stub, name), []byte("#!/bin/sh\nT="+tmp+"\n"+body+"\n"), 0o755)
	}
	c := exec.Command(p.bin, "__dump-rows")
	c.Dir, c.Env = p.root, []string{"PATH=" + os.Getenv("PATH"), "HOME=" + tmp, "HOP_CONFIG=" + p.cfg}
	out, err := c.Output()
	if err != nil {
		t.Fatalf("hop __dump-rows: %v", err)
	}
	p.list = match.Lines(string(out))
	return p
}

type outcome struct {
	rc                  int
	cd, clip, out       string
	code, gh, ed, files string
}

// spec is one picker run: hop's arguments, where it starts and what it adds to the pinned environment.
type spec struct {
	shell, dir string
	env, args  []string
}

// rel is what a row's preview pane leads with, the settle signal for a move: tcell repaints only changed cells,
// so a list line or an info count like 1/27 may never be drawn whole.
func (p *picker) rel(row string) string {
	d := p.dir(row)
	if d == p.root {
		return regexp.QuoteMeta(filepath.Base(p.root))
	}
	return regexp.QuoteMeta(strings.TrimPrefix(d, p.root+"/"))
}

func (p *picker) dir(row string) string { return rows.Split(row)[1] }

// run starts hop on a 40x140 pty, waits until it has drawn ready, lets drive type at it, and reports what it did.
func (p *picker) run(t *testing.T, s spec, ready string, drive func(*ptytest.Term) bool) outcome {
	t.Helper()
	for _, f := range []string{"cmd", "clip", "code", "gh", "ed", "hist"} {
		os.Remove(filepath.Join(p.tmp, f))
	}
	c := exec.Command(p.bin, s.args...)
	c.Dir = p.root
	if s.dir != "" {
		c.Dir = s.dir
	}
	if s.shell == "" {
		s.shell = "/bin/sh"
	}
	c.Env = append([]string{
		"PATH=" + p.stub + ":" + os.Getenv("PATH"), "HOME=" + p.tmp, "TMPDIR=" + p.tmp, "PWD=" + c.Dir, "LANG=en_US.UTF-8", "TERM=xterm-256color",
		"SHELL=" + s.shell, "HOP_CONFIG=" + p.cfg, "HOP_HISTFILE=" + filepath.Join(p.tmp, "hist"), "HOP_CMDFILE=" + filepath.Join(p.tmp, "cmd"),
		"HOP_FZF_HEIGHT=", "FZF_DEFAULT_OPTS=", "HOP_CODE=" + filepath.Join(p.tmp, "no-code"), "EDITOR=" + filepath.Join(p.stub, "ed"), "DISPLAY=:0",
	}, s.env...)
	term, err := ptytest.Start(c, 40, 140)
	if err != nil {
		t.Fatal(err)
	}
	if !term.WaitFor(ready, 10*time.Second) {
		term.Send("\x03")
		term.Wait(5 * time.Second)
		t.Fatalf("the picker never drew %q:\n%s", ready, lastScreen(term.Plain()))
	}
	if !drive(term) {
		since := term.Since()
		term.Send("\x03")
		term.Wait(5 * time.Second)
		t.Errorf("screen did not reach the expected state; drawn since the last key:\n%q", lastScreen(since))
		return outcome{rc: -2}
	}
	o := outcome{rc: term.Wait(10 * time.Second), out: term.Plain()}
	read := func(f string) string {
		b, _ := os.ReadFile(filepath.Join(p.tmp, f))
		return strings.TrimRight(string(b), "\n")
	}
	o.cd, o.clip, o.code, o.gh, o.ed = read("cmd"), read("clip"), read("code"), read("gh"), read("ed")
	return o
}

func lastScreen(s string) string {
	if len(s) > 3000 {
		return s[len(s)-3000:]
	}
	return s
}

func pickerShells(t *testing.T) []string {
	if v := os.Getenv("HOP_TEST_SHELLS"); v != "" {
		return strings.Fields(v)
	}
	shells := []string{"/bin/sh"}
	if z, err := exec.LookPath("zsh"); err == nil {
		shells = append(shells, z)
	}
	return shells
}

func waitFor(re string) func(*ptytest.Term) bool {
	return func(tm *ptytest.Term) bool { return tm.WaitFor(re, 10*time.Second) }
}

// steps runs each step in order: a string is keys to send, a duration a pause, and a func a wait on what was drawn.
func steps(s ...any) func(*ptytest.Term) bool {
	return func(tm *ptytest.Term) bool {
		for _, x := range s {
			switch v := x.(type) {
			case string:
				tm.Send(v)
			case time.Duration:
				time.Sleep(v)
			case func(*ptytest.Term) bool:
				if !v(tm) {
					return false
				}
			}
		}
		return true
	}
}

func mustLook(t *testing.T, name string) string {
	p, err := exec.LookPath(name)
	if err != nil {
		t.Skip(name, " not installed")
	}
	return p
}

const normal = `NORMAL  j/k move`

// TestPickerModal is the modal layer under a real fzf: NORMAL movement, SEARCH, esc's meanings, the menu and the overlay.
func TestPickerModal(t *testing.T) {
	p := newPicker(t)
	raster := p.root + "/terraform/acct-map-platform-prod/env-prod/us-east-1/raster-catalogue"
	rasterPv := `raster-catalogue/terragrunt\.hcl`
	first, second := p.list[0], p.list[1]
	for _, sh := range pickerShells(t) {
		t.Run(filepath.Base(sh), func(t *testing.T) {
			s := spec{shell: sh}
			if o := p.run(t, s, normal, steps(waitFor(p.rel(first)), "jjk", waitFor(p.rel(second)), "\r")); o.rc != 0 || o.cd != p.dir(second) {
				t.Errorf("j j k then enter: rc %d cd %q, want %q", o.rc, o.cd, p.dir(second))
			}
			if o := p.run(t, s, normal, steps("/", waitFor(`SEARCH  type to filter`), "raster", waitFor(rasterPv), "\r")); o.rc != 0 || o.cd != raster {
				t.Errorf("/ then raster then enter: rc %d cd %q", o.rc, o.cd)
			}
			if o := p.run(t, s, normal, steps(waitFor(p.rel(first)), "\x1b")); o.rc != 0 || o.cd != "" {
				t.Errorf("esc on an empty query exits 0 with no cd: rc %d cd %q", o.rc, o.cd)
			}
			if o := p.run(t, s, normal, steps(waitFor(p.rel(first)), "\x03")); o.rc != 0 || o.cd != "" {
				t.Errorf("ctrl-c exits 0 with no cd: rc %d cd %q", o.rc, o.cd)
			}
		})
	}
	s := spec{}

	two, err := (&match.FZF{Bin: mustLook(t, "fzf")}).Filter("secrets", p.list)
	if err != nil || len(two) < 2 {
		t.Fatalf("the fixture has two secrets rows: %v %v", two, err)
	}
	if o := p.run(t, s, normal, steps("/secrets", waitFor(p.rel(two[0])), "\x1b", waitFor(normal), "j", waitFor(p.rel(two[1])), "\r")); o.rc != 0 || o.cd != p.dir(two[1]) {
		t.Errorf("esc keeps the query, so j walks the filtered rows: rc %d cd %q, want %q", o.rc, o.cd, p.dir(two[1]))
	}
	if o := p.run(t, s, normal, steps("/secrets", waitFor(p.rel(two[0])), "\x1b", waitFor(normal), "\x1b", waitFor(p.rel(first)), "\r")); o.rc != 0 || o.cd != p.dir(first) {
		t.Errorf("esc esc restores every row: rc %d cd %q, want %q", o.rc, o.cd, p.dir(first))
	}
	if o := p.run(t, s, normal, steps(waitFor(p.rel(first)), "/zzqx", 400*time.Millisecond, "\x1b", waitFor(normal), "\x1b", waitFor(p.rel(first)), "\r")); o.rc != 0 || o.cd != p.dir(first) {
		t.Errorf("esc esc from a zero-match query restores every row: rc %d cd %q", o.rc, o.cd)
	}

	view := `VIEW  enter switch  esc back`
	sbx := p.root + "/sandbox/abg"
	if o := p.run(t, s, normal, steps("/raster", waitFor(rasterPv), "\x1b", waitFor(normal), ":", waitFor(view), "/sbx", waitFor(`sbx\s+2\s+sandbox dirs`), "\r",
		waitFor(normal), waitFor(`sandbox/abg`), "\r")); o.rc != 0 || o.cd != sbx {
		t.Errorf(": clears the query, / filters the menu, enter switches the view: rc %d cd %q", o.rc, o.cd)
	}
	tf := p.root + "/terraform"
	if o := p.run(t, spec{dir: tf, args: []string{"-c"}}, normal, steps(":", waitFor(view), "/dir", waitFor(`dir\s+1\s+`), "\r", waitFor(normal), 300*time.Millisecond, "g\r")); o.rc != 0 || o.cd != tf {
		t.Errorf("a kind switched to from the menu keeps -c: rc %d cd %q, want %q", o.rc, o.cd, tf)
	}
	if o := p.run(t, s, normal, steps(waitFor(p.rel(first)), ":", waitFor(view), "\x1b", waitFor(normal), waitFor(p.rel(first)), "\r")); o.rc != 0 || o.cd != p.dir(first) {
		t.Errorf("esc out of the menu goes back to the view: rc %d cd %q", o.rc, o.cd)
	}
	if o := p.run(t, s, normal, steps(waitFor(p.rel(first)), "?", waitFor(`hop keys[\s\S]*switch view, enter picks`), "j", waitFor(p.rel(second)), "\x1b")); o.rc != 0 {
		t.Errorf("? opens the overlay and j closes it: rc %d", o.rc)
	}
	if o := p.run(t, spec{args: []string{"raster", "zzqx"}}, `ignored: zzqx[\s\S]*SEARCH`, steps(waitFor(rasterPv), "\r")); o.rc != 0 || o.cd != raster {
		t.Errorf("a relaxed pick opens ordered in SEARCH with its note: rc %d cd %q", o.rc, o.cd)
	}
}

// TestPickerVerbs is each NORMAL letter verb against stub code, gh, editor and clipboard, from a row picked by a query.
func TestPickerVerbs(t *testing.T) {
	p := newPicker(t)
	raster := p.root + "/terraform/acct-map-platform-prod/env-prod/us-east-1/raster-catalogue"
	hcl := raster + "/terragrunt.hcl"
	code := []string{"HOP_CODE=" + filepath.Join(p.stub, "code")}
	at := func(key string) func(*ptytest.Term) bool {
		return steps("/raster", waitFor(`raster-catalogue/terragrunt\.hcl`), "\x1b", waitFor(normal), key)
	}
	for _, c := range []struct {
		key  string
		env  []string
		want func(outcome) bool
	}{
		{"o", code, func(o outcome) bool { return o.code == "code -r "+hcl && o.cd == "" }},
		{"O", code, func(o outcome) bool { return o.code == "code -n "+raster && o.cd == "" }},
		{"e", nil, func(o outcome) bool { return o.ed == "ed "+hcl && o.cd == "" }},
		{"y", nil, func(o outcome) bool { return o.clip == raster && strings.Contains(o.out, "hop: copied "+raster) }},
		{"Y", nil, func(o outcome) bool { return o.clip == hcl }},
		{"b", nil, func(o outcome) bool {
			return o.gh == "gh "+p.root+" browse -- terraform/acct-map-platform-prod/env-prod/us-east-1/raster-catalogue"
		}},
		{"c", append([]string{"HOP_ACTION=open"}, code...), func(o outcome) bool { return o.cd == raster && o.code == "" }},
		{"\r", append([]string{"HOP_ACTION=open"}, code...), func(o outcome) bool { return o.cd == "" && o.code == "code -n "+raster }},
	} {
		if o := p.run(t, spec{env: c.env}, normal, at(c.key)); o.rc != 0 || !c.want(o) {
			t.Errorf("%q: rc %d cd %q code %q gh %q ed %q clip %q", c.key, o.rc, o.cd, o.code, o.gh, o.ed, o.clip)
		}
	}
	if o := p.run(t, spec{env: []string{"HOP_VIM=0"}}, `hop ▸[\s\S]*M-a all`, steps("raster", waitFor(`raster-catalogue/terragrunt\.hcl`), "\x19")); o.rc != 0 || o.clip != raster {
		t.Errorf("HOP_VIM=0: letters type and ctrl-y copies: rc %d clip %q", o.rc, o.clip)
	}
	abg := p.root + "/sandbox/alpha-beta-gamma"
	if o := p.run(t, spec{env: []string{"HOP_VIM=0"}}, `hop ▸`, steps("\x1ba", waitFor(`\d+/\d+`), "alpha-beta", waitFor(`sandbox/alpha-beta-gamma`), "\r")); o.rc != 0 || o.cd != abg {
		t.Errorf("HOP_VIM=0: alt-a reloads every kind: rc %d cd %q", o.rc, o.cd)
	}
	if o := p.run(t, spec{args: []string{"--no-vim"}}, `hop ▸`, steps("\x1b")); o.rc != 0 {
		t.Errorf("--no-vim: plain fzf, esc quits: rc %d", o.rc)
	}
	if o := p.run(t, spec{args: []string{"--vim"}, env: []string{"HOP_VIM=0"}}, normal, steps("\x1b")); o.rc != 0 {
		t.Errorf("--vim beats HOP_VIM=0: rc %d", o.rc)
	}
}

// TestPickerGuard is suite_pty_escape's reported case: a terminal reply that fzf can't parse must reach no verb.
// - The negative pins a 300 s window, as zsh hop's suite does, so a loaded machine can't make the guard look leaky.
// - The guard-off run shows the payload really does reach browse, on an fzf that still leaks it.
func TestPickerGuard(t *testing.T) {
	p := newPicker(t)
	first := p.list[0]
	osc := "\x1b]11;rgb:1e1e/1e1e/1e1e\x1b\\"
	for name, burst := range map[string]string{
		"a bare BEL":                 "\a",
		"an OSC 11 reply, then b":    osc + "b",
		"an OSC 11 reply, BEL-ended": "\x1b]11;rgb:1e1e/1e1e/1e1e\a",
		"a truncated OSC 11 reply":   "\x1b]11;rgb:1e1e",
		"an OSC 10 reply":            "\x1b]10;rgb:c5c5/c8c8/c6c6\x1b\\",
		"an OSC 52 clipboard reply":  "\x1b]52;c;eW95b3lv\x1b\\",
		"a DCS version reply":        "\x1bP>|fzf-test(1.2.3)\x1b\\",
		"a 64-letter APC payload":    "\x1b_G" + strings.Repeat("obey", 16) + "\x1b\\",
	} {
		o := p.run(t, spec{env: []string{"HOP_GUARD_WINDOW=300"}}, normal, steps(waitFor(p.rel(first)), burst, time.Second, "\x03"))
		if o.rc != 0 || o.gh != "" || o.cd != "" || o.clip != "" || o.ed != "" || o.code != "" {
			t.Errorf("%s reached a verb: rc %d gh %q cd %q clip %q ed %q code %q", name, o.rc, o.gh, o.cd, o.clip, o.ed, o.code)
		}
	}
	if o := p.run(t, spec{}, normal, steps(waitFor(p.rel(first)), "y")); o.rc != 0 || o.clip != p.dir(first) {
		t.Errorf("a real y still copies, so the negatives aren't vacuous: rc %d clip %q", o.rc, o.clip)
	}
	f := &match.FZF{Bin: mustLook(t, "fzf")}
	if v := f.Version(); v != "" && match.Less(v, "0.74.5") {
		if o := p.run(t, spec{env: []string{"HOP_GUARD_WINDOW=0"}}, normal, steps(waitFor(p.rel(first)), osc, 2*time.Second, "\x03")); o.gh == "" {
			t.Errorf("with the guard off, fzf %s leaks the reply into browse, or the negative proves nothing: rc %d", v, o.rc)
		}
	}
	third := strings.TrimSuffix(strings.TrimPrefix(p.dir(p.list[2]), p.root+"/"), "/")
	if o := p.run(t, spec{}, normal, steps(waitFor(p.rel(first)), "j", 60*time.Millisecond, "j", 60*time.Millisecond, "b")); o.rc != 0 ||
		o.gh != "gh "+p.root+" browse -- "+third {
		t.Errorf("j j b at 60 ms still browses: rc %d gh %q", o.rc, o.gh)
	}
}

// levels is two workspaces of git repos: ws1 holds alpha and beta, ws2 holds gamma alone.
func levels(t *testing.T, p *picker) (ws1, ws2 string, cfg string) {
	t.Helper()
	ws1, ws2 = filepath.Join(p.tmp, "ws1"), filepath.Join(p.tmp, "ws2")
	for repo, dirs := range map[string][]string{"ws1/alpha": {"a", "b"}, "ws1/beta": {"c"}, "ws2/gamma": {"d"}} {
		r := filepath.Join(p.tmp, repo)
		for _, d := range dirs {
			os.MkdirAll(filepath.Join(r, d), 0o755)
			os.WriteFile(filepath.Join(r, d, "f.txt"), []byte("x\n"), 0o644)
		}
		os.WriteFile(filepath.Join(r, "README.md"), []byte("# "+filepath.Base(r)+"\n"), 0o644)
		for _, c := range [][]string{{"init", "-q"}, {"add", "-A"}} {
			if out, err := exec.Command("git", append([]string{"-C", r}, c...)...).CombinedOutput(); err != nil {
				t.Fatalf("git %v: %v %s", c, err, out)
			}
		}
	}
	cfg = filepath.Join(p.tmp, "levels.toml")
	os.WriteFile(cfg, []byte("[[kind]]\nname = \"dir\"\ndesc = \"repo root and top-level dirs\"\ndefault = true\nbuiltin = \"dir\"\n"), 0o644)
	return ws1, ws2, cfg
}

// TestPickerLevels walks workspace, repo and targets with l and h, and with ctrl-l and ctrl-h with the modal layer off.
func TestPickerLevels(t *testing.T) {
	p := newPicker(t)
	ws1, ws2, cfg := levels(t, p)
	env := []string{"HOP_CONFIG=" + cfg, "HOP_WORKSPACES=" + ws1 + ":" + ws2}
	alpha := filepath.Join(ws1, "alpha")
	label := func(s string) func(*ptytest.Term) bool { return waitFor(regexp.QuoteMeta(s)) }
	settle := 300 * time.Millisecond
	if o := p.run(t, spec{dir: p.tmp, env: env}, `workspaces  2`, steps(settle,
		"l", label("repos  2 found"), settle, "j", "l", label("beta  2 targets  dir"), settle,
		"h", label("repos  2 found"), settle, "h", label("workspaces  2"), settle, "j", settle, "l")); o.rc != 0 || o.cd != filepath.Join(ws2, "gamma") {
		t.Errorf("l into ws1, j l into beta, h h back out, j l into ws2's one repo: rc %d cd %q", o.rc, o.cd)
	}
	if o := p.run(t, spec{dir: alpha, env: env}, `alpha  3 targets  dir`, steps(settle,
		"h", label("repos  3 found"), settle, "h", label("workspaces  2"), settle, "\r")); o.rc != 0 || o.cd != ws1 {
		t.Errorf("from targets, h is every repo and h again the workspaces: rc %d cd %q", o.rc, o.cd)
	}
	if o := p.run(t, spec{dir: p.tmp, env: env, args: []string{"-R"}}, `repos  3 found`, steps(settle,
		"l", label("alpha  3 targets  dir"), settle, "\r")); o.rc != 0 || o.cd != alpha {
		t.Errorf("l on a repo opens its targets without a cd, and enter there decides: rc %d cd %q", o.rc, o.cd)
	}
	if o := p.run(t, spec{dir: p.tmp, env: append(env, "HOP_VIM=0"), args: []string{"-w"}}, `workspaces  2`, steps(settle,
		"\x0c", label("repos  2 found"), settle, "\x08", label("workspaces  2"), settle, "\x1b")); o.rc != 0 || o.cd != "" {
		t.Errorf("HOP_VIM=0: ctrl-l drills and ctrl-h goes up: rc %d cd %q", o.rc, o.cd)
	}
}

// TestPickerStatus is suite_core's fzf status ladder, which every level routes through: a failure is reported with its status,
// no match says so, and a cancel is silent and succeeds.
func TestPickerStatus(t *testing.T) {
	p := newPicker(t)
	ws1, ws2, cfg := levels(t, p)
	real := mustLook(t, "fzf")
	stub := filepath.Join(p.tmp, "fakefzf")
	os.Mkdir(stub, 0o755)
	os.WriteFile(filepath.Join(stub, "fzf"), []byte("#!/bin/sh\nfor a; do case $a in --version|--filter*) exec '"+real+"' \"$@\";; esac; done\nexit $FAKE_RC\n"), 0o755)
	for _, args := range [][]string{{"-w"}, {"-R"}} {
		for rc, want := range map[string]struct {
			rc  int
			say string
		}{"2": {2, "hop: fzf exited with status 2"}, "1": {1, "hop: no match"}, "130": {0, ""}} {
			c := exec.Command(p.bin, args...)
			c.Dir = p.tmp
			c.Env = []string{"PATH=" + stub + ":" + os.Getenv("PATH"), "HOME=" + p.tmp, "TMPDIR=" + p.tmp, "TERM=xterm-256color", "FAKE_RC=" + rc,
				"HOP_CONFIG=" + cfg, "HOP_WORKSPACES=" + ws1 + ":" + ws2, "HOP_HISTFILE=" + filepath.Join(p.tmp, "hist"), "HOP_FZF_HEIGHT="}
			term, err := ptytest.Start(c, 24, 80)
			if err != nil {
				t.Fatal(err)
			}
			got := term.Wait(10 * time.Second)
			out := strings.TrimSpace(term.Plain())
			if got != want.rc || (want.say == "" && out != "") || !strings.Contains(out, want.say) {
				t.Errorf("hop %s with fzf exiting %s: rc %d %q, want %d %q", args[0], rc, got, out, want.rc, want.say)
			}
		}
	}
}
