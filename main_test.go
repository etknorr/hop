package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
)

func TestMain(m *testing.M) { testfix.Main(m) }

func runHop(t *testing.T, args ...string) (string, string, int) {
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
	t.Setenv("HOP_HISTFILE", filepath.Join(t.TempDir(), "hist"))
	src, _ := os.ReadFile(filepath.Join("testdata", "fixture.toml"))
	td, _ := filepath.Abs("testdata")
	cfg := filepath.Join(t.TempDir(), "config.toml")
	os.WriteFile(cfg, []byte(strings.ReplaceAll(string(src), "@TESTDATA@", td)), 0o644)
	t.Setenv("HOP_CONFIG", cfg)
	root := filepath.Join(t.TempDir(), "repo")
	if err := testfix.Build(root); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestUsageAndVersion(t *testing.T) {
	if o, _, rc := runHop(t, "-h"); rc != 0 || !strings.Contains(o, "usage: hop") {
		t.Errorf("-h: rc %d", rc)
	}
	for _, v := range []string{"-V", "-v", "--version"} {
		if o, _, rc := runHop(t, v); rc != 0 || !strings.HasPrefix(o, "hop ") {
			t.Errorf("%s: %q", v, o)
		}
	}
	for _, a := range [][]string{{"-Z"}, {"-o", "-e"}, {"--action"}, {"--action=bogus"}, {"--action=open", "-o"}, {"/", "x"}, {"x", "-"}, {"-k"},
		{"__dump-rows", "-w", "-R"}, {"__dump-rows", "-a", "-k", "dir"}, {"__dump-rows", "extra"}, {"__rows"}, {"__config"}, {"__resolve-dump", "--bogus"}} {
		if _, _, rc := runHop(t, a...); rc != 2 {
			t.Errorf("%v: rc %d, want 2", a, rc)
		}
	}
}

func TestRowsForms(t *testing.T) {
	root := setup(t)
	def, _, rc := runHop(t, "__dump-rows", "--root", root)
	if rc != 0 || strings.Count(def, "\n") == 0 {
		t.Fatalf("rows: rc %d", rc)
	}
	hidden, _, _ := runHop(t, "__rows", root)
	if hidden != def {
		t.Error("__rows with no kind must be the default set")
	}
	k, _, _ := runHop(t, "__dump-rows", "--root", root, "-k", "svc, dir")
	hk, _, _ := runHop(t, "__rows", root, "svc", "dir")
	if k != hk || !strings.Contains(k, "<root>") {
		t.Error("-k and __rows disagree")
	}
	all, _, _ := runHop(t, "__dump-rows", "--root", root, "-a")
	if strings.Count(all, "\n") <= strings.Count(def, "\n") {
		t.Error("-a must add the non-default kinds")
	}
	_, e, rc := runHop(t, "__dump-rows", "--root", root, "-k", "nope")
	if rc != 1 || !strings.Contains(e, "unknown kind: nope") {
		t.Errorf("unknown kind: rc %d %q", rc, e)
	}
	if o, _, _ := runHop(t, "__kinds"); !strings.Contains(o, "* tg") || !strings.Contains(o, "  fx") {
		t.Errorf("kinds:\n%s", o)
	}
}

func TestConfigImportWritesOnlyWhereTold(t *testing.T) {
	if _, err := exec.LookPath("zsh"); err != nil {
		t.Skip("zsh not available")
	}
	setup(t)
	out := filepath.Join(t.TempDir(), "out.toml")
	o, _, rc := runHop(t, "import", filepath.Join("testdata", "fixture.zsh"), "-o", out)
	if rc != 0 || o != "" {
		t.Fatalf("import -o: rc %d, stdout %q", rc, o)
	}
	b, _ := os.ReadFile(out)
	o, _, _ = runHop(t, "import", "-o", "", filepath.Join("testdata", "fixture.zsh"))
	if string(b) != o || !strings.Contains(o, "[[kind]]") {
		t.Error("stdout and -o output differ")
	}
	t.Setenv("HOP_CONFIG", out)
	if o, _, rc := runHop(t, "__config", "check"); rc != 0 || !strings.Contains(o, "14 kinds") {
		t.Errorf("check: rc %d %q", rc, o)
	}
}

func TestConfigErrorExits1(t *testing.T) {
	bad := filepath.Join(t.TempDir(), "bad.toml")
	os.WriteFile(bad, []byte("[[kind]]\nname = 'x'\n"), 0o644)
	t.Setenv("HOP_CONFIG", bad)
	if _, e, rc := runHop(t, "__kinds"); rc != 1 || !strings.Contains(e, "bad.toml:2:") {
		t.Errorf("rc %d %q", rc, e)
	}
}

// TestParityRows runs test/parity/rows.sh against a real repo, which only a parity run has.
func TestParityRows(t *testing.T) {
	if os.Getenv("HOP_PARITY_REPO") == "" || os.Getenv("HOP_PARITY_HOME") == "" {
		t.Skip("set HOP_PARITY_HOME and HOP_PARITY_REPO, as test/parity/rows.sh asks")
	}
	cmd := exec.Command("bash", filepath.Join("test", "parity", "rows.sh"))
	cmd.Env = testfix.Inherited
	out, err := cmd.CombinedOutput()
	t.Logf("\n%s", out)
	if err != nil {
		t.Errorf("rows.sh: %v", err)
	}
}

// TestParityResolve runs test/parity/resolve.sh under HOP_JUMP=auto and HOP_VIM=1, or $PARITY_JUMPS and $PARITY_VIM, against a real repo.
// - One pass is about 4 minutes of zsh on Eric's repo, so the full matrix would outlast go test's 10-minute default timeout.
func TestParityResolve(t *testing.T) {
	if os.Getenv("HOP_PARITY_REPO") == "" || os.Getenv("HOP_PARITY_HOME") == "" {
		t.Skip("set HOP_PARITY_HOME and HOP_PARITY_REPO, as test/parity/resolve.sh asks")
	}
	cmd := exec.Command("bash", filepath.Join("test", "parity", "resolve.sh"))
	cmd.Env = testfix.Inherited
	if os.Getenv("PARITY_JUMPS") == "" {
		cmd.Env = append(cmd.Env, "PARITY_JUMPS=auto")
	}
	if os.Getenv("PARITY_VIM") == "" {
		cmd.Env = append(cmd.Env, "PARITY_VIM=1")
	}
	out, err := cmd.CombinedOutput()
	t.Logf("\n%s", out)
	if err != nil {
		t.Errorf("resolve.sh: %v", err)
	}
}
