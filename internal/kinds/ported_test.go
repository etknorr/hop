package kinds

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/testfix"
)

// TestFixtureRowsAreReal is suite_integration's enumeration checks: silent, and every dir absolute and present.
func TestFixtureRowsAreReal(t *testing.T) {
	root, cfg := fixture(t)
	var stderr bytes.Buffer
	rs := Generate(cfg, root, cfg.AllKinds(), &stderr)
	if stderr.Len() > 0 || len(rs) < 50 {
		t.Errorf("%d rows, stderr %q", len(rs), stderr.String())
	}
	for _, r := range rs {
		if !filepath.IsAbs(r.Dir) || !isDir(r.Dir) {
			t.Errorf("%s %s: dir %q is not an existing absolute dir", r.Kind, r.Name, r.Dir)
		}
	}
}

// TestWorktreeRows enumerates a git worktree from its own root, so no row points back into the main checkout.
func TestWorktreeRows(t *testing.T) {
	root, cfg := fixture(t)
	git := func(args ...string) {
		cmd := exec.Command("git", append([]string{"-C", root, "-c", "user.name=t", "-c", "user.email=t@t"}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	git("commit", "-qm", "fixture")
	wt := testfix.Resolved(t.TempDir()) + "/wt"
	git("worktree", "add", "-q", wt)
	if st, err := os.Lstat(wt + "/.git"); err != nil || st.IsDir() {
		t.Fatalf("a worktree's .git is a file: %v", err)
	}
	rs := Generate(cfg, wt, []string{"dir", "tg", "svc", "file"}, nil)
	if len(rs) < 20 {
		t.Fatalf("%d rows", len(rs))
	}
	for _, r := range rs {
		if !strings.HasPrefix(r.Dir, wt) || !strings.HasPrefix(r.Preview, wt) {
			t.Errorf("%s %s points outside the worktree: %s %s", r.Kind, r.Name, r.Dir, r.Preview)
		}
	}
}

func TestPreviewSkipDoesTheWork(t *testing.T) {
	root := buildRepo(t, map[string]string{"u/m": "x\n", "u/provider_aws.tf": "x\n", "u/zz.tf": "x\n"}, nil)
	for skip, want := range map[string]string{"": "provider_aws.tf", "\npreview_skip = ['provider_*.tf']": "zz.tf"} {
		cfg := loadSrc(t, "recipes = []\n[[kind]]\nname = 'k'\nmarker = 'm'\npreview = ['*.tf']"+skip+"\n")
		if rs := Generate(cfg, root, []string{"k"}, nil); len(rs) != 1 || rs[0].Preview != root+"/u/"+want {
			t.Errorf("preview_skip %q: %v, want %s", skip, rs, want)
		}
	}
}

// TestConfigFreeRepo: a repo of one root file gives the root row and that file, and every recipe stays silent.
func TestConfigFreeRepo(t *testing.T) {
	root := buildRepo(t, map[string]string{"notes.txt": "x\n"}, nil)
	cfg := loadSrc(t, "recipes = "+tomlList(config.Recipes())+"\n")
	var stderr bytes.Buffer
	wantRows(t, "dir", brief(Generate(cfg, root, []string{"dir"}, &stderr), root), "<root>|-|./")
	rs := Generate(cfg, root, []string{"file"}, &stderr)
	wantRows(t, "file", brief(rs, root), "notes.txt|.|notes.txt")
	if len(rs) == 1 && rs[0].Dir != root {
		t.Errorf("a root-level file's dir is the root: %s", rs[0].Dir)
	}
	if n := len(Generate(cfg, root, cfg.AllKinds(), &stderr)); n != 2 || stderr.Len() > 0 {
		t.Errorf("every recipe together: %d rows, stderr %q", n, stderr.String())
	}
}

func TestNoWorkspacesNoRows(t *testing.T) {
	if rs := WorkspaceRows(nil); len(rs) != 0 {
		t.Errorf("rows = %v", rs)
	}
	if rs := RepoRows(nil); len(rs) != 0 {
		t.Errorf("rows = %v", rs)
	}
}
