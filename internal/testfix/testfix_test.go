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
	if _, err := os.Stat(filepath.Join(HopHome(), "go.mod")); err != nil {
		t.Errorf("HopHome %s is not the module root", HopHome())
	}
	if ref := RefHome(RefLayout); ref == "" {
		t.Errorf("hop %s does not unpack from %s", RefLayout, HopHome())
	} else if _, err := os.Stat(filepath.Join(ref, "hop.zsh")); err != nil {
		t.Errorf("RefHome %s has no hop.zsh", ref)
	}
}

func TestIsolated(t *testing.T) {
	if os.Getenv("HOME") == RealHome || !strings.HasPrefix(os.Getenv("XDG_STATE_HOME"), os.Getenv("HOME")+"/") {
		t.Errorf("HOME %s and XDG_STATE_HOME %s still reach the real home %s", os.Getenv("HOME"), os.Getenv("XDG_STATE_HOME"), RealHome)
	}
	for _, kv := range os.Environ() {
		k, _, _ := strings.Cut(kv, "=")
		if (strings.HasPrefix(k, "HOP_") || strings.HasPrefix(k, "FZF_")) && !strings.HasPrefix(k, "HOP_PARITY_") && !strings.HasPrefix(k, "HOP_TEST_") {
			t.Errorf("%s leaked into the tests", k)
		}
	}
}
