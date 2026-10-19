package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/version"
)

func TestInitAndComplete(t *testing.T) {
	setup(t)
	if o, _, rc := runHop(t, "init", "bash", "--cmd", "j"); rc != 0 || !strings.Contains(o, "j() {") || !strings.Contains(o, "complete -F _j_complete j") || strings.Contains(o, "hopr") {
		t.Errorf("init bash --cmd j: rc %d", rc)
	}
	if o, _, rc := runHop(t, "init", "zsh"); rc != 0 || !strings.Contains(o, "hopr() {") || !strings.Contains(o, "HOP_INIT_HASH="+version.InitHash()) {
		t.Errorf("init zsh: rc %d", rc)
	}
	if _, _, rc := runHop(t, "init"); rc != 2 {
		t.Errorf("init with no shell: rc %d", rc)
	}
	for _, sh := range []string{"tcsh", "pwsh"} {
		if _, e, rc := runHop(t, "init", sh); rc != 1 || !strings.Contains(e, "unsupported shell") {
			t.Errorf("init %s: rc %d %q", sh, rc, e)
		}
	}
	o, _, _ := runHop(t, "__complete", "-k", "sv")
	if !strings.Contains(o, "svc\tdirs\n") || !strings.Contains(o, "svc2\tdepth2\n") {
		t.Errorf("kinds complete from the loaded config, with descriptions: %q", o)
	}
	if o, _, _ := runHop(t, "__complete", "-k", "svc,"); !strings.Contains(o, "svc,svc2\t") || strings.Contains(o, "svc,svc\t") {
		t.Errorf("a chosen kind drops out of a comma list: %q", o)
	}
}

// TestOptionLoopCases is 0.3.1's rule that -h, -V and --doctor act wherever they sit and stop parsing there.
func TestOptionLoopCases(t *testing.T) {
	setup(t)
	for _, c := range []struct {
		args []string
		rc   int
		out  string
		err  string
	}{
		{[]string{"-a", "-V"}, 0, "hop ", ""},
		{[]string{"-v"}, 0, "hop ", ""},
		{[]string{"--version"}, 0, "hop ", ""},
		{[]string{"vpc", "-h"}, 0, "usage: hop", ""},
		{[]string{"-o", "-e", "-h"}, 0, "usage: hop", ""},
		{[]string{"--help"}, 0, "usage: hop", ""},
		{[]string{"--bogus", "-h"}, 2, "", "hop: unknown option: --bogus"},
		{[]string{"--doctor=x"}, 2, "", "hop: --doctor=x: unknown --doctor mode, want: --doctor=short"},
		{[]string{"-a", "--doctor=x", "-h"}, 2, "", "unknown --doctor mode"},
		{[]string{"--doctor"}, 0, "--- hop --doctor ---", ""},
		{[]string{"--doctor", "short"}, 0, "--- hop --doctor=short", ""},
		{[]string{"-c", "--doctor=short"}, 0, "--- hop --doctor=short", ""},
	} {
		o, e, rc := runHop(t, c.args...)
		if rc != c.rc || !strings.Contains(o, c.out) || !strings.Contains(e, c.err) {
			t.Errorf("%v: rc %d\nstdout %.80q\nstderr %q", c.args, rc, o, e)
		}
	}
}

func TestVersionStaleness(t *testing.T) {
	setup(t)
	o, _, _ := runHop(t, "-V")
	if lines := strings.Split(strings.TrimRight(o, "\n"), "\n"); len(lines) != 1 || !strings.HasPrefix(lines[0], "hop ") {
		t.Errorf("-V outside the shell function: %q", o)
	}
	t.Setenv("HOP_SHELL", "bash")
	t.Setenv("HOP_INIT_HASH", version.InitHash())
	if o, _, _ := runHop(t, "-V"); strings.Contains(o, "predates") {
		t.Errorf("a current integration: %q", o)
	}
	t.Setenv("HOP_INIT_HASH", "0123456789ab")
	if o, _, _ := runHop(t, "-V"); !strings.Contains(o, "\nhop: your shell integration predates this hop: run 'exec bash' to reload it\n") {
		t.Errorf("a stale integration: %q", o)
	}
}

func TestUsageText(t *testing.T) {
	setup(t)
	o, _, _ := runHop(t, "-h")
	for _, s := range []string{"hop upgrade --check", "hop init zsh", "hop import", "  kinds, * being in the default set:", "    * tg", "declare your own in " + os.Getenv("HOP_CONFIG"), "enter cd"} {
		if !strings.Contains(o, s) {
			t.Errorf("-h lacks %q", s)
		}
	}
	if strings.Contains(o, "* file") {
		t.Error("an opt-in kind is starred")
	}
	t.Setenv("HOP_ACTION", "open")
	if o, _, _ := runHop(t, "-h"); !strings.Contains(o, "enter open | c cd") {
		t.Error("the keys name what enter does")
	}
	bad := filepath.Join(t.TempDir(), "bad.toml")
	os.WriteFile(bad, []byte("[[kind]]\nname = 'x'\n"), 0o644)
	t.Setenv("HOP_CONFIG", bad)
	if o, _, rc := runHop(t, "-h"); rc != 0 || !strings.Contains(o, "(none: ") || !strings.Contains(o, "usage: hop") {
		t.Errorf("a broken config still gets usage: rc %d", rc)
	}
}

// TestUpgradeIsFirstWordOnly: anywhere else it's a query word, which must never reach the real install.
func TestUpgradeIsFirstWordOnly(t *testing.T) {
	setup(t)
	t.Chdir(t.TempDir())
	t.Setenv("HOP_WORKSPACES", "/nonexistent/ws")
	o, e, rc := runHop(t, "-a", "upgrade")
	if rc != 1 || strings.Contains(o+e, "hop upgrade:") || !strings.Contains(e, "not in a git repository") {
		t.Errorf("hop -a upgrade: rc %d %q %q", rc, o, e)
	}
	if o, _, rc := runHop(t, "upgrade", "--help"); rc != 0 || !strings.Contains(o, "usage: hop upgrade") {
		t.Errorf("upgrade --help: rc %d %q", rc, o)
	}
	if _, e, rc := runHop(t, "upgrade", "--force"); rc != 2 || !strings.Contains(e, "hop upgrade: unknown option: --force") {
		t.Errorf("upgrade --force: rc %d %q", rc, e)
	}
}
