package resolve

import (
	"os"
	"path/filepath"
	"testing"
)

func write(t *testing.T, p, s string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
		t.Fatal(err)
	}
}

// TestGitFacts covers the git layouts _hop_git_facts reads without running git; TestHeadlessAgainstHop03 holds the rest to hop.
func TestGitFacts(t *testing.T) {
	d := t.TempDir()
	clone := filepath.Join(d, "clone")
	write(t, clone+"/.git/config", "[core]\n\tbare = false\n[remote \"origin\"]\n\turl = ssh://git@Host.example/Org/Repo.git/\n")
	write(t, clone+"/.git/HEAD", "ref: refs/heads/master\n")
	write(t, clone+"/.git/packed-refs", "# pack-refs\nabc refs/heads/master\n")

	wt := filepath.Join(d, "wt")
	write(t, wt+"/.git", "gitdir: "+clone+"/.git/worktrees/wt\n")
	write(t, clone+"/.git/worktrees/wt/commondir", "../..\n")
	write(t, clone+"/.git/worktrees/wt/HEAD", "0123456789abcdef\n")

	scp := filepath.Join(d, "scp")
	write(t, scp+"/.git/config", "[remote \"origin\"]\n  URL=\"git@host.example:org/repo\"\n")
	write(t, scp+"/.git/HEAD", "ref: refs/heads/trunk\n")
	write(t, scp+"/.git/refs/remotes/origin/HEAD", "ref: refs/remotes/origin/trunk\n")

	rt := filepath.Join(d, "reftable")
	write(t, rt+"/.git/config", "[remote \"origin\"]\n\turl = git@host.example:org/repo\n")
	write(t, rt+"/.git/HEAD", "ref: refs/heads/main\n")
	write(t, rt+"/.git/reftable/tables.list", "")

	noorigin := filepath.Join(d, "noorigin")
	write(t, noorigin+"/.git/config", "[remote \"upstream\"]\n\turl = git@host.example:org/repo\n")
	write(t, noorigin+"/.git/HEAD", "ref: refs/heads/main\n")

	for _, c := range []struct {
		dir, origin, branch, def string
		ok                       bool
	}{
		{clone, "host.example/org/repo", "master", "master", true},
		{wt, "host.example/org/repo", "", "master", true},
		{scp, "host.example/org/repo", "trunk", "trunk", true},
		{rt, "", "", "", false},
		{noorigin, "", "", "", false},
		{filepath.Join(d, "missing"), "", "", "", false},
	} {
		o, b, def, ok := gitFacts(c.dir)
		if o != c.origin || b != c.branch || def != c.def || ok != c.ok {
			t.Errorf("%s: (%q, %q, %q, %v), want (%q, %q, %q, %v)", filepath.Base(c.dir), o, b, def, ok, c.origin, c.branch, c.def, c.ok)
		}
	}
	if i, b, ok := mainCheckout([]string{wt, clone}); !ok || i != 1 || b != "master" {
		t.Errorf("mainCheckout(wt, clone) = %d %q %v, want the clone on master", i, b, ok)
	}
	if _, _, ok := mainCheckout([]string{clone, scp}); ok {
		t.Error("mainCheckout(clone, scp): both are on their default branch, so neither may win")
	}
	if _, _, ok := mainCheckout([]string{clone, noorigin}); ok {
		t.Error("mainCheckout(clone, noorigin): a checkout with no origin fails the rule")
	}
}

func TestElsewhereWordShape(t *testing.T) {
	for _, w := range []string{"x", "/abs/x", "~/x", "./x", "../x", "a/./b", "a/../b", "a/.."} {
		if _, _, ok := Elsewhere(w, "", "/", []Place{{Name: "r", Path: "/"}}, "auto", nil); ok {
			t.Errorf("Elsewhere(%q) tried other repos; only a relative path with no . or .. segment may", w)
		}
	}
}
