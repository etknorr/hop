package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/spike/hopx/internal/testfix"
)

func hopx(t *testing.T, args ...string) (string, string, int) {
	t.Helper()
	var out, errb bytes.Buffer
	rc := run(args, &out, &errb)
	return out.String(), errb.String(), rc
}

func setup(t *testing.T) string {
	t.Helper()
	for _, v := range []string{"HOP_DEFAULT_KINDS", "HOP_WORKSPACES", "HOP_REPOS", "HOP_ACTION", "HOP_JUMP"} {
		t.Setenv(v, "")
	}
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("HOPX_HISTFILE", filepath.Join(t.TempDir(), "hist"))
	src, _ := os.ReadFile(filepath.Join("testdata", "fixture.toml"))
	td, _ := filepath.Abs("testdata")
	cfg := filepath.Join(t.TempDir(), "config.toml")
	os.WriteFile(cfg, []byte(strings.ReplaceAll(string(src), "@TESTDATA@", td)), 0o644)
	t.Setenv("HOPX_CONFIG", cfg)
	root := filepath.Join(t.TempDir(), "repo")
	if err := testfix.Build(root); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestUsageAndVersion(t *testing.T) {
	if o, _, rc := hopx(t, "-h"); rc != 0 || !strings.Contains(o, "usage: hopx") {
		t.Errorf("-h: rc %d", rc)
	}
	for _, v := range []string{"-V", "-v", "--version"} {
		if o, _, rc := hopx(t, v); rc != 0 || !strings.HasPrefix(o, "hopx ") {
			t.Errorf("%s: %q", v, o)
		}
	}
	for _, a := range [][]string{{"-Z"}, {"-o", "-e"}, {"--action"}, {"--action=bogus"}, {"--action=open", "-o"}, {"/", "x"}, {"x", "-"}, {"-k"},
		{"rows", "-w", "-R"}, {"rows", "-a", "-k", "dir"}, {"rows", "extra"}, {"__rows"}, {"config"}, {"__resolve-dump", "--bogus"}} {
		if _, _, rc := hopx(t, a...); rc != 2 {
			t.Errorf("%v: rc %d, want 2", a, rc)
		}
	}
}

func TestRowsForms(t *testing.T) {
	root := setup(t)
	def, _, rc := hopx(t, "rows", "--root", root)
	if rc != 0 || strings.Count(def, "\n") == 0 {
		t.Fatalf("rows: rc %d", rc)
	}
	hidden, _, _ := hopx(t, "__rows", root)
	if hidden != def {
		t.Error("__rows with no kind must be the default set")
	}
	k, _, _ := hopx(t, "rows", "--root", root, "-k", "svc, dir")
	hk, _, _ := hopx(t, "__rows", root, "svc", "dir")
	if k != hk || !strings.Contains(k, "<root>") {
		t.Error("-k and __rows disagree")
	}
	all, _, _ := hopx(t, "rows", "--root", root, "-a")
	if strings.Count(all, "\n") <= strings.Count(def, "\n") {
		t.Error("-a must add the non-default kinds")
	}
	_, e, rc := hopx(t, "rows", "--root", root, "-k", "nope")
	if rc != 1 || !strings.Contains(e, "unknown kind: nope") {
		t.Errorf("unknown kind: rc %d %q", rc, e)
	}
	if o, _, _ := hopx(t, "kinds"); !strings.Contains(o, "* tg") || !strings.Contains(o, "  fx") {
		t.Errorf("kinds:\n%s", o)
	}
}

func TestConfigImportWritesOnlyWhereTold(t *testing.T) {
	if _, err := exec.LookPath("zsh"); err != nil {
		t.Skip("zsh not available")
	}
	setup(t)
	out := filepath.Join(t.TempDir(), "out.toml")
	o, _, rc := hopx(t, "config", "import", filepath.Join("testdata", "fixture.zsh"), "-o", out)
	if rc != 0 || o != "" {
		t.Fatalf("import -o: rc %d, stdout %q", rc, o)
	}
	b, _ := os.ReadFile(out)
	o, _, _ = hopx(t, "config", "import", "-o", "", filepath.Join("testdata", "fixture.zsh"))
	if string(b) != o || !strings.Contains(o, "[[kind]]") {
		t.Error("stdout and -o output differ")
	}
	t.Setenv("HOPX_CONFIG", out)
	if o, _, rc := hopx(t, "config", "check"); rc != 0 || !strings.Contains(o, "15 kinds") {
		t.Errorf("check: rc %d %q", rc, o)
	}
}

func TestConfigErrorExits1(t *testing.T) {
	bad := filepath.Join(t.TempDir(), "bad.toml")
	os.WriteFile(bad, []byte("[[kind]]\nname = 'x'\n"), 0o644)
	t.Setenv("HOPX_CONFIG", bad)
	if _, e, rc := hopx(t, "kinds"); rc != 1 || !strings.Contains(e, "bad.toml:2:") {
		t.Errorf("rc %d %q", rc, e)
	}
}

// TestParityRows runs spike/parity/rows.sh against a real repo, which only a parity run has.
func TestParityRows(t *testing.T) {
	repo := os.Getenv("HOPX_PARITY_REPO")
	if repo == "" {
		t.Skip("set HOPX_PARITY_REPO to a repo matching testdata/eric.toml, e.g. ~/strava/configuration")
	}
	cmd := exec.Command("bash", filepath.Join("..", "parity", "rows.sh"), repo)
	out, err := cmd.CombinedOutput()
	t.Logf("\n%s", out)
	if err != nil {
		t.Errorf("rows.sh: %v", err)
	}
}

// TestParityResolve runs spike/parity/resolve.sh under HOP_JUMP=auto, or $PARITY_JUMPS, against a real repo.
func TestParityResolve(t *testing.T) {
	repo := os.Getenv("HOPX_PARITY_REPO")
	if repo == "" {
		t.Skip("set HOPX_PARITY_REPO to a repo matching testdata/eric.toml, e.g. ~/strava/configuration")
	}
	cmd := exec.Command("bash", filepath.Join("..", "parity", "resolve.sh"), repo)
	if os.Getenv("PARITY_JUMPS") == "" {
		cmd.Env = append(os.Environ(), "PARITY_JUMPS=auto")
	}
	out, err := cmd.CombinedOutput()
	t.Logf("\n%s", out)
	if err != nil {
		t.Errorf("resolve.sh: %v", err)
	}
}
