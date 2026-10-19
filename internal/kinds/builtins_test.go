package kinds

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/rows"
	"github.com/etknorr/hop/internal/testfix"
	"github.com/etknorr/hop/internal/workspace"
)

// wsTree makes a fake HOME holding two workspaces, so the ~ forms in ws and repo rows are exercised.
func wsTree(t *testing.T) (home, file string) {
	t.Helper()
	home, _ = filepath.EvalSymlinks(t.TempDir())
	for _, p := range []string{"src/alpha/.git", "src/Beta/.git", "src/beta2/.git", "work/one/.git", "solo/only/.git", "empty"} {
		os.MkdirAll(filepath.Join(home, p), 0o755)
	}
	os.WriteFile(filepath.Join(home, "src", "alpha", "README.md"), []byte("x\n"), 0o644)
	os.WriteFile(filepath.Join(home, "src", "Beta", "CLAUDE.md"), []byte("x\n"), 0o644)
	file = filepath.Join(home, "workspaces")
	os.WriteFile(file, []byte("src = ~/src\nwork = ~/work\n~/solo\nnothing = ~/empty\n"), 0o644)
	t.Setenv("HOME", home)
	return home, file
}

func TestWorkspaceAndRepoRowsMatchZsh(t *testing.T) {
	_, file := wsTree(t)
	wss := workspace.Parse(nil, file)
	ws := renderFit(WorkspaceRows(wss), "")
	repo := renderFit(RepoRows(workspace.RepoList(nil, wss)), "")
	if !strings.Contains(rowsStripped(ws), "~/src") || strings.Count(repo, "\n") != 5 {
		t.Fatalf("unexpected rows\n%s\n%s", rowsStripped(ws), rowsStripped(repo))
	}
	if !testfix.HaveZsh() {
		t.Skipf("zsh or hop %s not available", testfix.RefLayout)
	}
	env := []string{"HOP_WORKSPACES_FILE=" + file}
	zws, err := testfix.Zsh("/dev/null", `_hop_provider_ws`, env)
	if err != nil {
		t.Fatal(err)
	}
	zrepo, err := testfix.Zsh("/dev/null", `_hop_repo_targets; print -r -- "$REPLY"`, env)
	if err != nil {
		t.Fatal(err)
	}
	if ws != zws {
		t.Errorf("ws rows\n--- go\n%s--- zsh\n%s", rowsStripped(ws), rowsStripped(zws))
	}
	if repo != zrepo {
		t.Errorf("repo rows\n--- go\n%s--- zsh\n%s", rowsStripped(repo), rowsStripped(zrepo))
	}
}

func rowsStripped(s string) string {
	var b strings.Builder
	for _, l := range strings.Split(s, "\n") {
		if l != "" {
			b.WriteString(strings.Split(rows.StripANSI(l), "\t")[0] + "\n")
		}
	}
	return b.String()
}
