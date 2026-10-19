package doctor

import (
	"bytes"
	"flag"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/etknorr/hop/internal/testfix"
	"github.com/etknorr/hop/internal/upgrade"
)

var update = flag.Bool("update", false, "rewrite testdata/golden/ops/doctor*.golden")

func TestMain(m *testing.M) {
	toolTimeout = 30 * time.Second
	testfix.Main(m)
}

func put(t *testing.T, p, s string, mode os.FileMode) {
	t.Helper()
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(s), mode); err != nil {
		t.Fatal(err)
	}
}

// fake is a HOME holding a config, a workspaces file, a repo inside a workspace and a debug log, with stub tools on PATH.
// - Every tool prints a fixed version, and git passes everything else to the real one, so the goldens hold on any machine.
// - PATH is the stub dir alone, so zsh is missing and NOT INSTALLED has a line; the stubs use shell builtins only.
func fake(t *testing.T) (home, repo string) {
	t.Helper()
	realGit, err := exec.LookPath("git")
	if err != nil {
		t.Skip("git not installed")
	}
	base := testfix.Resolved(t.TempDir())
	home = filepath.Join(base, "home")
	repo = filepath.Join(home, "code", "repo")
	for _, d := range []string{"alpha", "beta/gamma", "zzsentinelkind-dir/x"} {
		put(t, filepath.Join(repo, d, "README.md"), "# "+d+"\n", 0o644)
	}
	stub := filepath.Join(base, "stub")
	for name, v := range map[string]string{"fzf": "0.60.3 (stub)", "gh": "gh version 2.0.0 (stub)", "bat": "bat 0.24.0", "code": "1.100.0\nabcdef\narm64"} {
		put(t, filepath.Join(stub, name), "#!/bin/sh\nwhile read -r _; do :; done\nprintf '%s\\n' '"+strings.ReplaceAll(v, "\n", "' '")+"'\n", 0o755)
	}
	put(t, filepath.Join(stub, "git"), "#!/bin/sh\n[ \"$1\" = --version ] && { echo 'git version 2.0.0 (stub)'; exit 0; }\nexec "+realGit+" \"$@\"\n", 0o755)
	cmd := exec.Command(realGit, "init", "-q", "-b", "main")
	cmd.Dir = repo
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	add := exec.Command(realGit, "add", "-A")
	add.Dir = repo
	add.Run()
	put(t, filepath.Join(home, ".config", "hop", "config.toml"), `version = 1

[settings]
hist_max = 50

[[kind]]
name = "zzsentinelkind"
desc = "the sentinel"
default = true
dirs = ["zzsentinelkind-dir"]

[[kind]]
name = "dir"
desc = "repo root and top-level dirs"
builtin = "dir"
`, 0o644)
	put(t, filepath.Join(home, ".config", "hop", "workspaces"), "zzsentinelws = ~/code\n", 0o644)
	put(t, filepath.Join(home, ".local", "state", "hop", "debug.log"), "2026-10-19T10:00:00 pick label=repo rows=3 query= st=0\n2026-10-19T10:00:01 dispatch key=enter dir=~/code/repo/alpha preview= rel=alpha\n", 0o644)
	for k, v := range map[string]string{
		"HOME": home, "PATH": stub, "TERM": "xterm-test", "COLUMNS": "100",
		"HOP_ACTION": "bogus", "HOP_CODE": filepath.Join(home, "bin", "code"),
		"HOP_SHELL": "zsh", "HOP_INIT_HASH": "oldhash",
	} {
		t.Setenv(k, v)
	}
	for _, k := range []string{"HOP_CONFIG", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "HOP_HISTFILE", "HOP_DEBUG", "HOP_DEBUG_LOG", "HOP_WORKSPACES", "HOP_REPOS", "HOP_HOPRC", "HOP_FZF_HEIGHT", "HOP_VIM"} {
		t.Setenv(k, "")
		os.Unsetenv(k)
	}
	t.Chdir(repo)
	t.Setenv("PWD", repo)
	return home, repo
}

func opts(short bool) Options {
	return Options{
		Short:    short,
		Install:  upgrade.Install{Method: upgrade.Checkout, Root: "/src/hop", Exe: "/src/hop/bin/hop"},
		Version:  "1.0.0 (abc1234)",
		InitHash: "freshhash",
		Recipes:  []string{"dir", "project", "file"},
	}
}

func golden(t *testing.T, name, got string) {
	t.Helper()
	p := filepath.Join(testfix.ModuleRoot(), "testdata", "golden", "ops", name)
	if *update {
		put(t, p, got, 0o644)
		return
	}
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("%v (run go test ./internal/doctor -update)", err)
	}
	if string(b) != got {
		t.Errorf("%s differs; got:\n%s", name, got)
	}
}

func run(o Options) string {
	var b bytes.Buffer
	Run(&b, o)
	return b.String()
}

func TestDoctorGolden(t *testing.T) {
	home, _ := fake(t)
	full := run(opts(false))
	golden(t, "doctor.golden", full)
	short := run(opts(true))
	golden(t, "doctor-short.golden", short)
	for name, out := range map[string]string{"full": full, "short": short} {
		if strings.Contains(out, home) {
			t.Errorf("%s prints $HOME literally", name)
		}
		if !strings.HasSuffix(out, "--- end ---\n") {
			t.Errorf("%s has no end marker", name)
		}
	}
	for _, s := range []string{"zzsentinelkind", "zzsentinelws", "bogus", "bin/code", "~/code/repo"} {
		if !strings.Contains(full, s) {
			t.Errorf("full mode lacks %q", s)
		}
		if strings.Contains(short, s) {
			t.Errorf("short mode leaks %q", s)
		}
	}
}

func TestDoctorOutsideARepo(t *testing.T) {
	fake(t)
	dir := t.TempDir()
	t.Chdir(dir)
	t.Setenv("PWD", dir)
	full := run(opts(false))
	for _, s := range []string{"git toplevel           NONE", "(not in a repo, so nothing to count)", "zzsentinelkind       -"} {
		if !strings.Contains(full, s) {
			t.Errorf("outside a repo, full mode lacks %q:\n%s", s, full)
		}
	}
	if short := run(opts(true)); !strings.Contains(short, "registered             2") {
		t.Errorf("short outside a repo:\n%s", short)
	}
}

func TestDoctorHomeForcedIntoOutput(t *testing.T) {
	home, _ := fake(t)
	t.Setenv("HOP_CONFIG", filepath.Join(home, "custom", "hop.toml"))
	t.Setenv("HOP_HISTFILE", filepath.Join(home, "elsewhere", "hist"))
	for _, short := range []bool{false, true} {
		out := run(opts(short))
		if strings.Contains(out, home) {
			t.Errorf("short=%v prints $HOME", short)
		}
		if short && strings.Contains(out, "elsewhere") {
			t.Error("short mode shows a customised path")
		}
	}
}

func TestDoctorConfigHints(t *testing.T) {
	home, _ := fake(t)
	os.Remove(filepath.Join(home, ".config", "hop", "config.toml"))
	put(t, filepath.Join(home, ".config", "hop", "config.zsh"), "hop_preset dir\n", 0o644)
	t.Setenv("HOP_CONFIG", filepath.Join(home, ".config", "hop", "config.zsh"))
	out := run(opts(false))
	for _, s := range []string{
		"MISSING, so the zero-config defaults",
		"HOP_CONFIG names a zsh hop config",
		"config.zsh             found; run 'hop import -o ~/.config/hop/config.toml' to use it",
	} {
		if !strings.Contains(out, s) {
			t.Errorf("lacks %q:\n%s", s, out)
		}
	}
	bad := filepath.Join(home, "bad.toml")
	put(t, bad, "[[kind]]\nname = 'x'\n", 0o644)
	t.Setenv("HOP_CONFIG", bad)
	out = run(opts(false))
	if !strings.Contains(out, "load                   FAILED: ~/bad.toml:2:") || !strings.Contains(out, "(the config failed to load, so there are no kinds)") {
		t.Errorf("a broken config:\n%s", out)
	}
	if out := run(opts(true)); strings.Contains(out, "bad.toml") {
		t.Error("short mode names the broken file")
	}
}

func TestDoctorSourcesAndModes(t *testing.T) {
	fake(t)
	t.Setenv("HOP_ACTION", "open")
	t.Setenv("HOP_JUMP", "sideways")
	t.Setenv("HOP_HOPRC", "1")
	t.Setenv("HOP_DEBUG", "1")
	t.Setenv("HOP_INIT_HASH", "freshhash")
	t.Setenv("HOP_CODE", "code")
	out := run(opts(false))
	for _, s := range []string{
		"HOP_ACTION             open (env)",
		"HOP_JUMP               sideways (env), so hop uses auto",
		"HOP_HIST_MAX           50 (config)",
		"HOP_VIM                on (default)",
		"HOP_HOPRC              1 (env), unsupported",
		"HOP_DEBUG              1",
		"VS Code reachable      yes",
		"shell                  zsh, integration current",
		"code     1.100.0",
	} {
		if !strings.Contains(out, s) {
			t.Errorf("lacks %q:\n%s", s, out)
		}
	}
	if short := run(opts(true)); !strings.Contains(short, "HOP_JUMP               (not a mode, withheld) (env), so hop uses auto") {
		t.Errorf("short withholds the bad mode:\n%s", short)
	}
}
