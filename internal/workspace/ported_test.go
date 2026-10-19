package workspace

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func names(wss []Workspace) string {
	var out []string
	for _, w := range wss {
		out = append(out, w.Name+"="+w.Path)
	}
	return strings.Join(out, " ")
}

func writeFile(t *testing.T, dir, src string) string {
	t.Helper()
	f := filepath.Join(dir, "workspaces")
	if err := os.WriteFile(f, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	return f
}

// TestPayloadsAreInert is suite_workspaces' payload block: nothing in a workspaces file is ever run.
func TestPayloadsAreInert(t *testing.T) {
	d, _ := filepath.EvalSymlinks(t.TempDir())
	os.MkdirAll(filepath.Join(d, "ok"), 0o755)
	sentinel := filepath.Join(d, "ran")
	f := writeFile(t, d, strings.Join([]string{
		"ok = " + d + "/ok",
		"a = $(touch " + sentinel + ")",
		"b = `touch " + sentinel + "`",
		"c = " + d + "/ok; touch " + sentinel,
		"$(touch " + sentinel + ") = " + d + "/ok",
	}, "\n")+"\n")
	got := Parse(nil, f)
	if names(got) != "ok="+d+"/ok $(touch "+sentinel+")="+d+"/ok" {
		t.Errorf("only the legitimate path parses, and a payload name is inert text: %s", names(got))
	}
	Repos(d + "/ok")
	RepoList(nil, got)
	if _, err := os.Stat(sentinel); err == nil {
		t.Error("a payload ran")
	}
}

func TestFileRules(t *testing.T) {
	d, _ := filepath.EvalSymlinks(t.TempDir())
	for _, p := range []string{"x", "y=z", "src", "code", "work"} {
		os.MkdirAll(filepath.Join(d, p), 0o755)
	}
	os.WriteFile(filepath.Join(d, "afile"), []byte("x\n"), 0o644)
	os.Symlink(filepath.Join(d, "gone"), filepath.Join(d, "dangling"))
	t.Setenv("HOME", d)
	cases := []struct{ label, src, want string }{
		{"an empty file means no workspaces, not the built-in default", "", ""},
		{"a comments-only file means no workspaces", "# one\n   # two\n", ""},
		{"no trailing newline still parses the last line", "x = " + d + "/x", "x=" + d + "/x"},
		{"the first = splits, so a path may hold =", "w = " + d + "/y=z\n", "w=" + d + "/y=z"},
		{"a run of spaces and tabs around both fields is stripped", " \t n \t=\t " + d + "/x \t\n", "n=" + d + "/x"},
		{"a bare ~ is $HOME", "h = ~\n", "h=" + d},
		{"only unusable paths means none", "a = " + d + "/missing\nb = " + d + "/x/nope\n", ""},
		{"a file and a dangling symlink are skipped", "f = " + d + "/afile\nl = " + d + "/dangling\nx = " + d + "/x\n", "x=" + d + "/x"},
	}
	for _, c := range cases {
		if got := names(Parse(nil, writeFile(t, d, c.src))); got != c.want {
			t.Errorf("%s: %q, want %q", c.label, got, c.want)
		}
	}
	want := "src=" + d + "/src code=" + d + "/code work=" + d + "/work"
	if got := names(Parse(nil, filepath.Join(d, "missing"))); got != want {
		t.Errorf("a missing file guesses ~/src ~/code ~/projects ~/dev ~/work, keeping those that exist: %q", got)
	}
}

func TestReposDepthOne(t *testing.T) {
	d, _ := filepath.EvalSymlinks(t.TempDir())
	os.MkdirAll(filepath.Join(d, "ws", "group", "deep", ".git"), 0o755)
	os.MkdirAll(filepath.Join(d, "ws", "plain"), 0o755)
	if got := Repos(filepath.Join(d, "ws")); len(got) != 0 {
		t.Errorf("a repo one level deeper and a dir without .git are not repos: %v", got)
	}
	if got := Repos(filepath.Join(d, "missing")); got != nil {
		t.Errorf("a missing workspace has no repos: %v", got)
	}
}
