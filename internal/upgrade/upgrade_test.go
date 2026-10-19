package upgrade

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
	"github.com/etknorr/hop/internal/version"
)

// Nothing here reaches the network or a real install: the remote is a bare repo in the temp dir, and go and brew are stubs.
func TestMain(m *testing.M) {
	for k, v := range map[string]string{
		"GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": "",
		"GIT_AUTHOR_NAME": "hop tests", "GIT_AUTHOR_EMAIL": "hop-tests@example.invalid",
		"GIT_COMMITTER_NAME": "hop tests", "GIT_COMMITTER_EMAIL": "hop-tests@example.invalid",
	} {
		os.Setenv(k, v)
	}
	testfix.Main(m)
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func write(t *testing.T, p, s string) {
	t.Helper()
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
		t.Fatal(err)
	}
}

// origin is a bare repo whose main holds v0.1.0 then v0.2.0, annotated as real releases are.
// - v0.2.0 adds a file, which is what makes the untracked-collision case possible.
// - v0.3.0-rc1 and v0.2.0-notes sort ahead of v0.2.0, so an unfiltered tag list picks one of them.
func origin(t *testing.T, tagged bool) (bare, v1, v2 string) {
	t.Helper()
	d := testfix.Resolved(t.TempDir())
	src := filepath.Join(d, "src")
	os.MkdirAll(src, 0o755)
	git(t, src, "init", "-q", "-b", "main")
	write(t, filepath.Join(src, "go.mod"), "module "+version.Module+"\n\ngo 1.26\n")
	write(t, filepath.Join(src, "main.go"), "package main\n\nfunc main() {}\n")
	write(t, filepath.Join(src, "VERSION"), "0.1.0\n")
	git(t, src, "add", "-A")
	git(t, src, "commit", "-q", "--no-gpg-sign", "-m", "first release")
	if tagged {
		git(t, src, "tag", "-a", "-m", "release 0.1.0", "v0.1.0")
		write(t, filepath.Join(src, "VERSION"), "0.2.0\n")
		write(t, filepath.Join(src, "added.go"), "package main\n")
		git(t, src, "add", "-A")
		git(t, src, "commit", "-q", "--no-gpg-sign", "-m", "second release")
		git(t, src, "tag", "-a", "-m", "release 0.2.0", "v0.2.0")
		git(t, src, "tag", "-a", "-m", "not a release", "v0.3.0-rc1")
		git(t, src, "tag", "-a", "-m", "not a release either", "v0.2.0-notes")
		v1, v2 = git(t, src, "rev-parse", "v0.1.0^{commit}"), git(t, src, "rev-parse", "v0.2.0^{commit}")
	}
	bare = filepath.Join(d, "origin.git")
	git(t, d, "init", "--bare", "-q", "-b", "main", bare)
	git(t, src, "push", "-q", bare, "refs/heads/main:refs/heads/main", "--tags")
	return bare, v1, v2
}

func clone(t *testing.T, bare string) string {
	t.Helper()
	dir := filepath.Join(testfix.Resolved(t.TempDir()), "hop")
	git(t, filepath.Dir(dir), "clone", "-q", bare, dir)
	return dir
}

// stubs puts go and brew stand-ins first on PATH, each logging its argv to dir/<name>.log.
// - The go stub's build writes a script at -o's path, so rebuild can run "the new binary".
func stubs(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	write(t, filepath.Join(dir, "go"), `#!/bin/sh
echo "$*" >>"`+dir+`/go.log"
case $1 in
build) mkdir -p "$(dirname "$3")"; printf '#!/bin/sh\necho "hop rebuilt from %s"\n' "$(cat VERSION)" >"$3"; chmod +x "$3" ;;
env) printf '%s\n%s\n' "${STUB_GOBIN:-}" "${STUB_GOPATH:-/nonexistent/gopath}" ;;
esac
exit ${STUB_GO_RC:-0}
`)
	write(t, filepath.Join(dir, "brew"), `#!/bin/sh
echo "$*" >>"`+dir+`/brew.log"
exit ${STUB_BREW_RC:-0}
`)
	os.Chmod(filepath.Join(dir, "go"), 0o755)
	os.Chmod(filepath.Join(dir, "brew"), 0o755)
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return dir
}

func logOf(dir, name string) string {
	b, _ := os.ReadFile(filepath.Join(dir, name+".log"))
	return strings.TrimSpace(string(b))
}

func up(t *testing.T, in Install, ver string, args ...string) (string, int) {
	t.Helper()
	var b bytes.Buffer
	u := &Upgrader{Install: in, Version: ver, Stdout: &b, Stderr: &b}
	rc := u.Run(args)
	return b.String(), rc
}

func co(dir string) Install {
	return Install{Method: Checkout, Root: dir, Exe: filepath.Join(dir, "bin", "hop")}
}

func head(t *testing.T, dir string) string { return git(t, dir, "rev-parse", "HEAD") }

func branch(dir string) string {
	out, err := exec.Command("git", "-C", dir, "symbolic-ref", "--quiet", "--short", "HEAD").Output()
	if err != nil {
		return "DETACHED"
	}
	return strings.TrimSpace(string(out))
}

func want(t *testing.T, out string, rc, wantRC int, has []string, hasNot ...string) {
	t.Helper()
	if rc != wantRC {
		t.Errorf("rc %d, want %d\n%s", rc, wantRC, out)
	}
	for _, s := range has {
		if !strings.Contains(out, s) {
			t.Errorf("output lacks %q:\n%s", s, out)
		}
	}
	for _, s := range hasNot {
		if strings.Contains(out, s) {
			t.Errorf("output has %q:\n%s", s, out)
		}
	}
}

func TestFixtureHasTwoReleases(t *testing.T) {
	_, v1, v2 := origin(t, true)
	if v1 == "" || v2 == "" || v1 == v2 {
		t.Fatalf("v0.1.0 %q v0.2.0 %q", v1, v2)
	}
}

func TestCheckoutRefusals(t *testing.T) {
	stubs(t)
	bare, _, _ := origin(t, true)
	cases := []struct {
		name  string
		setup func(dir string) string
		args  []string
		rc    int
		has   []string
		not   []string
	}{
		{"not a git checkout", func(string) string { return t.TempDir() }, nil, 1, []string{"not a git checkout"}, nil},
		{"vendored inside another repo", func(string) string {
			outer := t.TempDir()
			git(t, outer, "init", "-q", "-b", "main")
			write(t, filepath.Join(outer, "vendor/hop/go.mod"), "module "+version.Module+"\n")
			git(t, outer, "add", "-A")
			git(t, outer, "commit", "-q", "--no-gpg-sign", "-m", "vendored")
			return filepath.Join(outer, "vendor", "hop")
		}, nil, 1, []string{"sits inside"}, nil},
		{"no origin", func(d string) string { git(t, d, "remote", "remove", "origin"); return d }, nil, 1, []string{"no `origin` remote"}, nil},
		{"dirty", func(d string) string {
			appendTo(t, filepath.Join(d, "main.go"), "// a local edit nobody wants silently discarded\n")
			return d
		},
			[]string{"0.1.0"}, 1, []string{"uncommitted changes", "main.go"}, nil},
		{"side branch", func(d string) string { git(t, d, "checkout", "-q", "-b", "wip"); return d }, nil, 1, []string{"not main"}, nil},
		{"detached off a release", func(d string) string {
			git(t, d, "checkout", "-q", "--detach")
			git(t, d, "commit", "-q", "--allow-empty", "--no-gpg-sign", "-m", "a local experiment")
			return d
		}, nil, 1, []string{"not a release tag"}, nil},
		{"detached at a topic tag reads as loose", func(d string) string {
			git(t, d, "checkout", "-q", "--detach")
			git(t, d, "commit", "-q", "--allow-empty", "--no-gpg-sign", "-m", "an experiment")
			git(t, d, "tag", "-a", "-m", "an experiment", "my-experiment")
			return d
		}, nil, 1, []string{"not a release tag"}, nil},
		{"unknown release names the real ones", func(d string) string { return d }, []string{"9.9.9"}, 1, []string{"no such release: v9.9.9", "v0.2.0, v0.1.0"}, []string{"rc1"}},
		{"dirt before the network", func(d string) string {
			git(t, d, "remote", "set-url", "origin", filepath.Join(d, "no-such-remote.git"))
			appendTo(t, filepath.Join(d, "main.go"), "// local\n")
			return d
		}, nil, 1, []string{"uncommitted changes"}, []string{"could not fetch"}},
		{"diverged main", func(d string) string {
			git(t, d, "checkout", "-q", "-B", "main", "v0.1.0")
			git(t, d, "commit", "-q", "--allow-empty", "--no-gpg-sign", "-m", "a local commit on main")
			return d
		}, nil, 1, []string{"diverged"}, nil},
		{"pin with no local main", func(d string) string {
			git(t, d, "checkout", "-q", "v0.1.0")
			git(t, d, "branch", "-q", "-D", "main")
			return d
		}, nil, 1, []string{"no local main branch", "checkout -b main origin/main"}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := c.setup(clone(t, bare))
			before, b0 := "", ""
			if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
				before, b0 = head(t, dir), branch(dir)
			}
			out, rc := up(t, co(dir), "devel", c.args...)
			want(t, out, rc, c.rc, c.has, c.not...)
			if before != "" && (head(t, dir) != before || branch(dir) != b0) {
				t.Errorf("a refusal moved HEAD")
			}
			if _, err := os.Stat(co(dir).Exe); err == nil {
				t.Errorf("a refusal rebuilt the binary")
			}
		})
	}
}

func appendTo(t *testing.T, p, s string) {
	t.Helper()
	f, err := os.OpenFile(p, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	f.WriteString(s)
	f.Close()
}

func TestUsageErrors(t *testing.T) {
	stubs(t)
	bare, _, _ := origin(t, true)
	dir := clone(t, bare)
	for _, c := range []struct {
		args []string
		has  string
	}{
		{[]string{"--check", "9.9.9"}, "takes no version"},
		{[]string{"not-a-version"}, "not a version"},
		{[]string{"--force"}, "unknown option"},
		{[]string{"0.1.0", "0.2.0"}, "at most one version"},
	} {
		before := head(t, dir)
		out, rc := up(t, co(dir), "devel", c.args...)
		want(t, out, rc, 2, []string{"hop upgrade: ", c.has})
		if head(t, dir) != before {
			t.Errorf("%v moved HEAD", c.args)
		}
	}
	out, rc := up(t, co(dir), "devel", "--help")
	want(t, out, rc, 0, []string{"usage: hop upgrade", "built from the checkout at " + dir})
}

func TestUntaggedRemote(t *testing.T) {
	stubs(t)
	bare, _, _ := origin(t, false)
	dir := clone(t, bare)
	before := head(t, dir)
	out, rc := up(t, co(dir), "devel")
	want(t, out, rc, 1, []string{"no release tags"})
	out, rc = up(t, co(dir), "devel", "--check")
	want(t, out, rc, 0, []string{"none yet"})
	if head(t, dir) != before {
		t.Error("moved HEAD")
	}
}

func TestCheck(t *testing.T) {
	stubs(t)
	bare, _, _ := origin(t, true)
	t.Run("an older pin reports both and an update", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "v0.1.0")
		before := head(t, dir)
		out, rc := up(t, co(dir), "devel", "--check")
		want(t, out, rc, 0, []string{"installed  0.1.0", "released   v0.2.0", "an update is available"}, "rc1", "notes")
		if head(t, dir) != before {
			t.Error("--check moved HEAD")
		}
	})
	t.Run("a local tag origin doesn't publish can't be newest", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "tag", "-a", "-m", "local only", "v9.9.9")
		out, rc := up(t, co(dir), "devel", "--check")
		want(t, out, rc, 0, []string{"v0.2.0"}, "9.9.9")
	})
	t.Run("column.ui and tag.sort change nothing", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "config", "column.ui", "always")
		git(t, dir, "config", "tag.sort", "v:refname")
		git(t, dir, "checkout", "-q", "v0.1.0")
		out, rc := up(t, co(dir), "devel", "--check")
		want(t, out, rc, 0, []string{"released   v0.2.0"}, "none yet")
	})
	t.Run("VERSION is the installed version", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "v0.1.0")
		write(t, filepath.Join(dir, "VERSION"), "9.9.9\n")
		out, _ := up(t, co(dir), "devel", "--check")
		want(t, out, 0, 0, []string{"installed  9.9.9"})
	})
	t.Run("no VERSION falls back to git describe", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "v0.1.0")
		os.Remove(filepath.Join(dir, "VERSION"))
		out, _ := up(t, co(dir), "devel", "--check")
		want(t, out, 0, 0, []string{"installed  v0.1.0"})
	})
	t.Run("the newest release is up to date", func(t *testing.T) {
		dir := clone(t, bare)
		out, rc := up(t, co(dir), "devel", "--check")
		want(t, out, rc, 0, []string{"up to date"}, "an update is available")
	})
	t.Run("a dirty tree is left alone and named", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "v0.1.0")
		appendTo(t, filepath.Join(dir, "main.go"), "// local\n")
		before := head(t, dir)
		out, rc := up(t, co(dir), "devel", "--check")
		want(t, out, rc, 0, []string{"v0.2.0", "uncommitted changes"})
		if head(t, dir) != before {
			t.Error("--check moved HEAD")
		}
	})
	t.Run("main ahead of the release is up to date", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "commit", "-q", "--allow-empty", "--no-gpg-sign", "-m", "after the release")
		out, rc := up(t, co(dir), "devel", "--check")
		want(t, out, rc, 0, []string{"up to date; this checkout already carries v0.2.0"}, "an update is available")
	})
	t.Run("not a checkout fails", func(t *testing.T) {
		out, rc := up(t, co(t.TempDir()), "devel", "--check")
		want(t, out, rc, 1, []string{"not a git checkout"})
	})
}

func TestCheckoutMoves(t *testing.T) {
	st := stubs(t)
	bare, v1, v2 := origin(t, true)
	t.Run("bare upgrade fast-forwards main and stays on it, then rebuilds", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "-B", "main", "v0.1.0")
		out, rc := up(t, co(dir), "devel")
		want(t, out, rc, 0, []string{"hop is now at v0.2.0 on main.", "rebuilt " + co(dir).Exe, "hop rebuilt from 0.2.0"})
		if head(t, dir) != v2 || branch(dir) != "main" || git(t, dir, "rev-parse", "refs/heads/main") != v2 {
			t.Errorf("head %s branch %s", head(t, dir), branch(dir))
		}
		if n := git(t, dir, "rev-list", "--count", "--merges", "main"); n != "0" {
			t.Errorf("%s merge commits: not a fast-forward", n)
		}
		if l := logOf(st, "go"); !strings.Contains(l, "build -o "+co(dir).Exe+" .") {
			t.Errorf("go log: %q", l)
		}
	})
	t.Run("from a pin says it leaves the pin and returns to main", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "v0.1.0")
		out, rc := up(t, co(dir), "devel")
		want(t, out, rc, 0, []string{"pinned at v0.1.0", "To stay pinned", "hop upgrade 0.1.0"})
		if branch(dir) != "main" || head(t, dir) != v2 {
			t.Errorf("head %s branch %s", head(t, dir), branch(dir))
		}
	})
	t.Run("from a pin with main behind fast-forwards the main ref", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "-B", "main", "v0.1.0")
		git(t, dir, "checkout", "-q", "v0.1.0")
		out, rc := up(t, co(dir), "devel")
		want(t, out, rc, 0, nil)
		if branch(dir) != "main" || head(t, dir) != v2 || git(t, dir, "rev-parse", "refs/heads/main") != v2 {
			t.Errorf("head %s branch %s", head(t, dir), branch(dir))
		}
		if n := git(t, dir, "rev-list", "--count", "--merges", "main"); n != "0" {
			t.Errorf("an annotated tag merged without --ff-only: %s merges", n)
		}
	})
	for _, v := range []string{"0.1.0", "v0.1.0"} {
		t.Run("a named version "+v+" pins, detached", func(t *testing.T) {
			dir := clone(t, bare)
			out, rc := up(t, co(dir), "devel", v)
			want(t, out, rc, 0, []string{"pinned at v0.1.0", "To follow releases again: hop upgrade", "checkout main", "hop rebuilt from 0.1.0"})
			if head(t, dir) != v1 || branch(dir) != "DETACHED" {
				t.Errorf("head %s branch %s", head(t, dir), branch(dir))
			}
		})
	}
	t.Run("pinning the release main stands on still detaches", func(t *testing.T) {
		dir := clone(t, bare)
		out, rc := up(t, co(dir), "devel", "0.2.0")
		want(t, out, rc, 0, []string{"pinned at v0.2.0"})
		if head(t, dir) != v2 || branch(dir) != "DETACHED" {
			t.Errorf("head %s branch %s", head(t, dir), branch(dir))
		}
	})
	t.Run("main ahead of the release is up to date, not an error", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "commit", "-q", "--allow-empty", "--no-gpg-sign", "-m", "after the release")
		before := head(t, dir)
		out, rc := up(t, co(dir), "devel")
		want(t, out, rc, 0, []string{"already carries v0.2.0"}, "rebuilt")
		if head(t, dir) != before || branch(dir) != "main" {
			t.Error("moved")
		}
	})
	t.Run("an untracked file the release ships is refused before the pin is left", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "-B", "main", "v0.1.0")
		git(t, dir, "checkout", "-q", "v0.1.0")
		write(t, filepath.Join(dir, "added.go"), "mine")
		before := head(t, dir)
		out, rc := up(t, co(dir), "devel")
		want(t, out, rc, 1, []string{"added.go"}, "returns you to main")
		if head(t, dir) != before || branch(dir) != "DETACHED" {
			t.Error("the pin was abandoned on a path that then refused")
		}
		if b, _ := os.ReadFile(filepath.Join(dir, "added.go")); string(b) != "mine" {
			t.Error("the untracked file was overwritten")
		}
	})
	t.Run("an untracked file elsewhere neither blocks nor is removed", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "-B", "main", "v0.1.0")
		write(t, filepath.Join(dir, "notes.txt"), "scratch")
		out, rc := up(t, co(dir), "devel")
		want(t, out, rc, 0, nil)
		if head(t, dir) != v2 {
			t.Error("did not move")
		}
		if _, err := os.Stat(filepath.Join(dir, "notes.txt")); err != nil {
			t.Error("the upgrade removed an untracked file")
		}
	})
	t.Run("the release already pinned changes nothing", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "v0.1.0")
		out, rc := up(t, co(dir), "devel", "v0.1.0")
		want(t, out, rc, 0, []string{"already at v0.1.0"}, "rebuilt")
	})
	t.Run("a no-op repeats a stale-shell warning, and only then", func(t *testing.T) {
		dir := clone(t, bare)
		var b bytes.Buffer
		u := &Upgrader{Install: co(dir), Version: "devel", Stale: "hop: your shell integration predates this hop: run 'exec zsh' to reload it", Stdout: &b, Stderr: &b}
		want(t, b.String(), u.Run(nil), 0, nil)
		want(t, b.String(), 0, 0, []string{"already at v0.2.0 on main", "exec zsh"})
		out, _ := up(t, co(dir), "devel")
		want(t, out, 0, 0, []string{"already at v0.2.0 on main"}, "exec")
	})
	t.Run("a failed rebuild says so and names the fix", func(t *testing.T) {
		dir := clone(t, bare)
		git(t, dir, "checkout", "-q", "-B", "main", "v0.1.0")
		t.Setenv("STUB_GO_RC", "1")
		out, rc := up(t, co(dir), "devel")
		want(t, out, rc, 1, []string{"go build failed", "go build -o " + co(dir).Exe})
		if head(t, dir) != v2 {
			t.Error("the move itself should stand")
		}
	})
}

// TestNoDestructiveGit is suite_upgrade's source scan: it covers paths no case happens to reach.
func TestNoDestructiveGit(t *testing.T) {
	var body string
	for _, f := range []string{"checkout.go", "upgrade.go"} {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		body += string(b)
	}
	for _, bad := range []string{`"clean"`, `"reset"`, `"-f"`, `"--force"`, `"stash"`, `"rebase"`, `"--no-ff"`, "RemoveAll"} {
		if strings.Contains(body, bad) {
			t.Errorf("the upgrade code holds %s", bad)
		}
	}
	if !strings.Contains(body, `"--ff-only"`) {
		t.Error("main is only ever advanced by fast-forward")
	}
}

func TestBrew(t *testing.T) {
	st := stubs(t)
	bare, _, _ := origin(t, true)
	t.Setenv("HOP_UPGRADE_REMOTE", bare)
	in := Install{Method: Brew, Exe: "/opt/homebrew/Cellar/hop/0.1.0/bin/hop"}
	out, rc := up(t, in, "0.1.0")
	want(t, out, rc, 0, nil)
	if l := logOf(st, "brew"); l != "upgrade etknorr/hop/hop" {
		t.Errorf("brew log %q", l)
	}
	out, rc = up(t, in, "0.1.0", "0.2.0")
	want(t, out, rc, 2, []string{"cannot pin v0.2.0", "go install github.com/etknorr/hop@v0.2.0"})
	out, rc = up(t, in, "0.1.0", "--check")
	want(t, out, rc, 0, []string{"installed  0.1.0", "released   v0.2.0", "an update is available: run 'hop upgrade'"}, "rc1")
	out, rc = up(t, in, "0.2.0", "--check")
	want(t, out, rc, 0, []string{"up to date"})
	t.Setenv("STUB_BREW_RC", "3")
	if _, rc := up(t, in, "0.1.0"); rc != 3 {
		t.Errorf("brew's status passes through: %d", rc)
	}
	if strings.Count(logOf(st, "brew"), "\n") != 1 {
		t.Errorf("--check and a refused pin must not run brew: %q", logOf(st, "brew"))
	}
}

func TestGoInstall(t *testing.T) {
	st := stubs(t)
	bare, _, _ := origin(t, true)
	t.Setenv("HOP_UPGRADE_REMOTE", bare)
	bin := t.TempDir()
	in := Install{Method: GoInstall, Exe: filepath.Join(bin, "hop")}
	t.Setenv("STUB_GOBIN", bin)
	out, rc := up(t, in, "0.1.0")
	want(t, out, rc, 0, nil, "writes to")
	out, rc = up(t, in, "0.1.0", "0.2.0")
	want(t, out, rc, 0, nil)
	l := logOf(st, "go")
	if !strings.Contains(l, "install github.com/etknorr/hop@latest") || !strings.Contains(l, "install github.com/etknorr/hop@v0.2.0") {
		t.Errorf("go log %q", l)
	}
	t.Setenv("STUB_GOBIN", "")
	t.Setenv("STUB_GOPATH", t.TempDir())
	out, _ = up(t, in, "0.1.0")
	want(t, out, 0, 0, []string{"go install writes to", "but this hop runs from " + bin})
	out, rc = up(t, in, "0.1.0", "--check")
	want(t, out, rc, 0, []string{"released   v0.2.0", "an update is available"})
	t.Setenv("HOP_UPGRADE_REMOTE", filepath.Join(bin, "nowhere.git"))
	out, rc = up(t, in, "0.1.0", "--check")
	want(t, out, rc, 1, []string{"could not list the releases"})
}

func TestUnknown(t *testing.T) {
	stubs(t)
	bare, _, _ := origin(t, true)
	t.Setenv("HOP_UPGRADE_REMOTE", bare)
	in := Install{Method: Unknown, Exe: "/somewhere/hop"}
	out, rc := up(t, in, "1.0.0")
	want(t, out, rc, 1, []string{"cannot tell how this hop was installed", "/somewhere/hop", "brew install etknorr/hop/hop", "go install github.com/etknorr/hop@latest", "git clone"})
	out, rc = up(t, in, "1.0.0", "--check")
	want(t, out, rc, 0, []string{"installed  1.0.0", "released   v0.2.0", "up to date"})
}

func TestDetect(t *testing.T) {
	tree := testfix.Resolved(t.TempDir())
	write(t, filepath.Join(tree, "go.mod"), "module "+version.Module+"\n\ngo 1.26\n")
	other := testfix.Resolved(t.TempDir())
	write(t, filepath.Join(other, "go.mod"), "module example.com/other\n")
	for _, c := range []struct {
		name string
		exe  string
		info version.Info
		m    Method
		root string
	}{
		{"brew's Cellar", "/opt/homebrew/Cellar/hop/1.0.0/bin/hop", version.Info{ModPath: version.Module, ModVersion: "v1.0.0", Revision: "abc"}, Brew, ""},
		{"a checkout build", filepath.Join(tree, "bin", "hop"), version.Info{ModPath: version.Module, ModVersion: "(devel)"}, Checkout, tree},
		{"another module's tree", filepath.Join(other, "bin", "hop"), version.Info{ModPath: version.Module, ModVersion: "v1.0.0"}, GoInstall, ""},
		{"go install", "/home/u/go/bin/hop", version.Info{ModPath: version.Module, ModVersion: "v1.0.0"}, GoInstall, ""},
		{"a release archive", "/usr/local/bin/hop", version.Info{ModPath: version.Module, ModVersion: "v1.0.0", Revision: "abc", Stamped: true}, Unknown, ""},
		{"go run", "/tmp/go-build1/exe/hop", version.Info{ModPath: version.Module, ModVersion: "(devel)"}, Unknown, ""},
	} {
		got := Detect(c.exe, c.info)
		if got.Method != c.m || got.Root != c.root {
			t.Errorf("%s: %+v, want %s %q", c.name, got, c.m, c.root)
		}
	}
}

func TestSortTags(t *testing.T) {
	got := strings.Join(sortTags([]string{"v0.9.0", "v0.10.0", "v0.10.0-rc1", "v1.0.0", "x", "", "v0.2.0-notes", "v0.10.0"}), " ")
	if got != "v1.0.0 v0.10.0 v0.9.0" {
		t.Errorf("sortTags = %q", got)
	}
}
