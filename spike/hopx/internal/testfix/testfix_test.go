package testfix

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestBuild(t *testing.T) {
	root := filepath.Join(t.TempDir(), "repo")
	if err := Build(root); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command("git", "-C", root, "ls-files", "-s", "--", "svc/gitlink", "sym/link").Output()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(out), "160000") || !strings.Contains(string(out), "120000") {
		t.Errorf("want a gitlink and a symlink in the index:\n%s", out)
	}
	if _, err := os.Stat(filepath.Join(HopHome(), "hop.zsh")); err != nil {
		t.Errorf("HopHome %s has no hop.zsh", HopHome())
	}
}
