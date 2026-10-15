package workspace

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/spike/hopx/internal/testfix"
)

// tricky builds workspace dirs and a file exercising every _hop_ws_parse rule, returning the file.
func tricky(t *testing.T) (string, string) {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	for _, p := range []string{"a/r1/.git", "a/r2/.git", "a/.hid/.git", "a/notrepo/x", "b/R3/.git", "b/r4/.git", "nox"} {
		os.MkdirAll(filepath.Join(d, p), 0o755)
	}
	os.WriteFile(filepath.Join(d, "b", "wt"), nil, 0o644)
	os.MkdirAll(filepath.Join(d, "b", "wt-repo"), 0o755)
	os.WriteFile(filepath.Join(d, "b", "wt-repo", ".git"), []byte("gitdir: x\n"), 0o644)
	os.Chmod(filepath.Join(d, "nox"), 0o600)
	t.Cleanup(func() { os.Chmod(filepath.Join(d, "nox"), 0o755) })
	os.Symlink(filepath.Join(d, "a"), filepath.Join(d, "link"))
	lines := []string{
		"  # comment",
		"",
		" one = " + d + "/a   # trailing comment",
		"two=$WSD/a#notcomment",
		d + "/b",
		d + "/link",
		"three = ${WSD}/b\r",
		"one = " + d + "/b",
		" = " + d + "/a",
		"four = ~/does-not-exist-hopx",
		"five = " + d + "/$-a",
		"six = ${WSD",
		"seven=$WSD/a$UNSETVAR_HOPX",
		"nox = " + d + "/nox",
		"crlf = " + d + "/a\r",
	}
	f := filepath.Join(d, "workspaces")
	os.WriteFile(f, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
	return d, f
}

func TestParseMatchesZsh(t *testing.T) {
	d, f := tricky(t)
	t.Setenv("WSD", d)
	var got []string
	for _, w := range Parse(nil, f) {
		got = append(got, w.Name+"\t"+w.Path)
	}
	want := []string{"one\t" + d + "/a", "b\t" + d + "/b", "a\t" + d + "/a", "three\t" + d + "/b", "seven\t" + d + "/a", "crlf\t" + d + "/a"}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("Parse\n got  %q\n want %q", got, want)
	}
	if !testfix.HaveZsh() {
		return
	}
	out, err := testfix.Zsh("/dev/null", `_hop_ws_parse; print -rl -- "${reply[@]}"`, []string{"WSD=" + d, "HOP_WORKSPACES_FILE=" + f})
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(out) != strings.Join(got, "\n") {
		t.Errorf("zsh _hop_ws_parse\n%s\nhopx\n%s", out, strings.Join(got, "\n"))
	}
}

func TestParseListBeatsFile(t *testing.T) {
	d, f := tricky(t)
	got := Parse([]string{d + "/b", "", d + "/a"}, f)
	if len(got) != 2 || got[0].Name != "b" || got[1].Name != "a" {
		t.Errorf("Parse(list) = %v", got)
	}
	t.Setenv("HOME", d)
	got = Parse(nil, filepath.Join(d, "missing"))
	if len(got) != 0 {
		t.Errorf("guessed defaults under an empty HOME: %v", got)
	}
}

func TestReposAndRepoList(t *testing.T) {
	d, _ := tricky(t)
	got := Repos(d + "/b")
	want := []string{d + "/b/R3", d + "/b/r4", d + "/b/wt-repo"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("Repos = %v, want %v (collated, .git file counts)", got, want)
	}
	wss := []Workspace{{"a", d + "/a"}, {"b", d + "/b"}, {"again", d + "/a"}}
	all := RepoList(nil, wss)
	if len(all) != 5 || all[0] != d+"/a/r1" {
		t.Errorf("RepoList = %v", all)
	}
	if got := RepoList([]string{"/x", "", "/x", "/y"}, wss); strings.Join(got, ",") != "/x,/y" {
		t.Errorf("an explicit list wins and dedupes: %v", got)
	}
}

func TestExpand(t *testing.T) {
	t.Setenv("HOME", "/h")
	t.Setenv("V", "v")
	cases := map[string]string{
		"~": "/h", "~/x": "/h/x", "a/~/b": "a/~/b", "$V/x": "v/x", "${V}x": "vx", "$-x": "-x", "${V": "v{V", "$NOPE_HOPX/x": "/x",
	}
	for in, want := range cases {
		if got := Expand(in); got != want {
			t.Errorf("Expand(%q) = %q, want %q", in, got, want)
		}
	}
	if !testfix.HaveZsh() {
		return
	}
	for in, want := range cases {
		out, err := testfix.Zsh("/dev/null", `HOME=/h; _hop_ws_expand "$1"; print -r -- "$REPLY"`, []string{"V=v"}, in)
		if err != nil {
			t.Fatal(err)
		}
		if got := strings.TrimSuffix(out, "\n"); got != want {
			t.Errorf("zsh _hop_ws_expand(%q) = %q, hopx expects %q", in, got, want)
		}
	}
}
