package upgrade

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// A checkout moves exactly as zsh hop 0.3.1's did, then rebuilds the binary in place.
// - Nothing forces, cleans, resets or stashes: git's own refusal to clobber is the safety net.
// - Every refusal changes nothing, so each guard runs before the first ref moves.

// git runs against the checkout, never the caller's PWD, with output captured.
func (u *Upgrader) git(args ...string) (string, error) {
	out, err := exec.Command("git", append([]string{"-C", u.Root}, args...)...).Output()
	return strings.TrimRight(string(out), "\n"), err
}

func (u *Upgrader) gitOK(args ...string) bool {
	_, err := u.git(args...)
	return err == nil
}

// guardRepo is what --check and a move both need: a checkout of its own with an origin.
func (u *Upgrader) guardRepo() bool {
	top, err := u.git("rev-parse", "--show-toplevel")
	if err != nil || top == "" {
		u.err(u.Root+" is not a git checkout, so there is nothing to update.",
			"Reinstall with brew or go install; see the README install section.")
		return false
	}
	if resolved(top) != resolved(u.Root) {
		u.err(u.Root+" is not a checkout of its own; it sits inside "+top+".",
			"Updating would move that repo rather than hop, so this refuses.")
		return false
	}
	if !u.gitOK("remote", "get-url", "origin") {
		u.err("this checkout has no `origin` remote, so there is nowhere to fetch from.",
			"Add one: git -C "+u.Root+" remote add origin <url>")
		return false
	}
	return true
}

func resolved(p string) string {
	if r, err := filepath.EvalSymlinks(p); err == nil {
		return r
	}
	return p
}

// state is main, pinned (detached on a release tag), branch:<name>, or loose (detached anywhere else, which is never moved).
func (u *Upgrader) state() string {
	if b, err := u.git("symbolic-ref", "--quiet", "--short", "HEAD"); err == nil {
		if b == "main" {
			return "main"
		}
		return "branch:" + b
	}
	if u.releaseAt("HEAD") != "" {
		return "pinned"
	}
	return "loose"
}

// releaseAt is the vX.Y.Z tag pointing exactly at rev; for-each-ref, since `git tag` honours column.ui.
func (u *Upgrader) releaseAt(rev string) string {
	out, _ := u.git("for-each-ref", "--points-at", rev, "--format=%(refname:strip=2)", "refs/tags/v*")
	return first(sortTags(strings.Split(out, "\n")))
}

func first(s []string) string {
	if len(s) == 0 {
		return ""
	}
	return s[0]
}

// guardMove runs only before a move; untracked files are not dirt, since git's checkout refuses to overwrite one itself.
func (u *Upgrader) guardMove() bool {
	dirty, _ := u.git("status", "--porcelain", "--untracked-files=no")
	if dirty != "" {
		u.err("the install has uncommitted changes, and an update would discard them.", "Commit or stash them first. Changed:")
		fmt.Fprintln(u.Stderr, dirty)
		return false
	}
	switch s := u.state(); {
	case s == "main" || s == "pinned":
		return true
	case strings.HasPrefix(s, "branch:"):
		u.err("HEAD is on branch "+strings.TrimPrefix(s, "branch:")+", not main.",
			"That is work in progress as far as this command can tell, so it refuses.")
		return false
	}
	u.err("HEAD is detached at a commit that is not a release tag.", "Get back on main first: git -C "+u.Root+" checkout main")
	return false
}

// localTags is every local release tag, newest first.
func (u *Upgrader) localTags() []string {
	out, _ := u.git("for-each-ref", "--format=%(refname:strip=2)", "refs/tags/v*")
	return sortTags(strings.Split(out, "\n"))
}

// latest is the newest local release origin still publishes: a fetch never prunes, so a yanked tag lingers locally.
func (u *Upgrader) latest(tags []string) string {
	for _, t := range tags {
		if out, _ := u.git("ls-remote", "--tags", "--refs", "origin", "refs/tags/"+t); out != "" {
			return t
		}
	}
	return ""
}

// current is the checkout's VERSION, the release's own claim about itself, else git describe.
func (u *Upgrader) current() string {
	if b, err := os.ReadFile(filepath.Join(u.Root, "VERSION")); err == nil {
		if v := strings.Join(strings.Fields(string(b)), ""); v != "" {
			return v
		}
	}
	if d, _ := u.git("describe", "--tags", "--always", "--dirty"); d != "" {
		return d
	}
	return "unknown"
}

func (u *Upgrader) commit(ref string) string {
	c, _ := u.git("rev-parse", "--verify", "--quiet", ref+"^{commit}")
	return c
}

func (u *Upgrader) ancestor(a, b string) bool { return u.gitOK("merge-base", "--is-ancestor", a, b) }

func (u *Upgrader) checkout(check bool, tag string) int {
	if !u.guardRepo() {
		return 1
	}
	if !check && !u.guardMove() {
		return 1
	}
	if _, err := u.git("fetch", "--quiet", "--tags", "origin"); err != nil {
		u.err("could not fetch from origin, so nothing was changed.")
		return 1
	}
	tags := u.localTags()
	latest := u.latest(tags)
	cur := u.current()
	head, _ := u.git("rev-parse", "--short", "HEAD")
	installed := cur
	if head != "" {
		installed += "  (" + head + ")"
	}
	if check {
		u.say("  %-10s %s", "installed", installed)
		if latest == "" {
			u.say("  %-10s %s", "released", "none yet, so there is nothing to update to")
			return 0
		}
		u.say("  %-10s %s", "released", latest)
		if at := u.releaseAt("HEAD"); at != "" && at == latest {
			u.say("  up to date")
			return 0
		}
		if lc := u.commit("refs/tags/" + latest); lc != "" && u.ancestor(lc, "HEAD") {
			u.say("  up to date; this checkout already carries %s and later commits", latest)
			return 0
		}
		u.say("  an update is available: run 'hop upgrade'")
		u.guardMove()
		return 0
	}
	if tag == "" {
		if latest == "" {
			u.err("origin has no release tags yet, so there is nothing to update to.", "Installed: "+strings.Replace(installed, "  (", " (", 1))
			return 1
		}
		return u.track(latest)
	}
	if !u.gitOK("rev-parse", "--verify", "--quiet", "refs/tags/"+tag) {
		u.err("no such release: " + tag)
		if len(tags) > 0 {
			u.err("available: " + strings.Join(tags, ", "))
		}
		return 1
	}
	from, _ := u.git("rev-parse", "HEAD")
	to := u.commit("refs/tags/" + tag)
	if from != "" && from == to && u.state() != "main" {
		u.say("hop is already at %s, so nothing changed.", tag)
		return u.noop()
	}
	if !u.gitOK("-c", "advice.detachedHead=false", "checkout", "--quiet", "refs/tags/"+tag) {
		u.err("git refused to check out "+tag+", so nothing was changed.", "Its own message above names what is in the way.")
		return 1
	}
	was := cur
	if head != "" {
		was += " at " + head
	}
	u.say("hop is now pinned at %s (was %s).", tag, was)
	u.say("To follow releases again: hop upgrade")
	u.say("To go back to main by hand: git -C %s checkout main", u.Root)
	return u.rebuild()
}

// track leaves the checkout on main carrying tag, by fast-forward only; whether main can move is answered before anything does.
func (u *Upgrader) track(tag string) int {
	tagc := u.commit("refs/tags/" + tag)
	if tagc == "" {
		u.err("could not resolve " + tag + " to a commit.")
		return 1
	}
	mainc, _ := u.git("rev-parse", "--verify", "--quiet", "refs/heads/main")
	if mainc == "" {
		u.err("this checkout has no local main branch to bring up to date.", "Make one: git -C "+u.Root+" checkout -b main origin/main")
		return 1
	}
	state := u.state()
	pin := ""
	if state == "pinned" {
		pin = u.releaseAt("HEAD")
	}
	if mainc != tagc && !u.ancestor(mainc, tagc) && !u.ancestor(tagc, mainc) {
		u.err("main has diverged from "+tag+", so it cannot be fast-forwarded.", "Sort that out by hand; this will not rebase or merge for you.")
		return 1
	}
	if !u.collidesOK(tagc) {
		return 1
	}
	if pin != "" {
		u.say("hop is pinned at %s, so this returns you to main to follow releases.", pin)
		u.say("To stay pinned, name a version instead: hop upgrade %s", strings.TrimPrefix(pin, "v"))
	}
	head0, _ := u.git("rev-parse", "HEAD")
	if state != "main" && !u.gitOK("checkout", "--quiet", "main") {
		u.err("git refused to check out main, so nothing was changed.")
		return 1
	}
	switch {
	case mainc == tagc && state == "main":
		u.say("hop is already at %s on main, so nothing changed.", tag)
		return u.noop()
	case mainc == tagc:
		u.say("hop is on main at %s.", tag)
		return u.rebuild()
	case u.ancestor(tagc, mainc):
		u.say("main already carries %s and later commits, so there is nothing to update.", tag)
		if state == "main" {
			return u.noop()
		}
		return u.rebuild()
	}
	if !u.gitOK("merge", "--ff-only", "--quiet", "refs/tags/"+tag) {
		if state != "main" && head0 != "" {
			u.gitOK("-c", "advice.detachedHead=false", "checkout", "--quiet", "--detach", head0)
		}
		u.err("git refused to fast-forward main to " + tag + ", so nothing was changed.")
		return 1
	}
	u.say("hop is now at %s on main.", tag)
	return u.rebuild()
}

// collidesOK refuses when an untracked file sits where the target commit adds one, before the pin is left.
func (u *Upgrader) collidesOK(to string) bool {
	out, _ := u.git("diff", "--name-only", "--diff-filter=A", "HEAD", to)
	for p := range strings.SplitSeq(out, "\n") {
		if p == "" {
			continue
		}
		if _, err := os.Lstat(filepath.Join(u.Root, p)); err == nil {
			u.err(p+" is untracked here, and "+to[:min(7, len(to))]+" ships a file at that path.", "Move it aside first; this will not overwrite it.")
			return false
		}
	}
	return true
}

// rebuild replaces the running binary from the moved tree, then lets the new one say what it is.
// - go build writes a temp file and renames it, so the running process keeps its own inode.
func (u *Upgrader) rebuild() int {
	if _, err := exec.LookPath("go"); err != nil {
		u.err("the checkout moved, but go is not on PATH to rebuild "+u.Exe+".", "Build it by hand: cd "+u.Root+" && go build -o "+u.Exe+" .")
		return 1
	}
	c := exec.Command("go", "build", "-o", u.Exe, ".")
	c.Dir, c.Stdout, c.Stderr = u.Root, u.Stderr, u.Stderr
	if err := c.Run(); err != nil {
		u.err("the checkout moved, but go build failed, so "+u.Exe+" is the old binary.", "Build it by hand: cd "+u.Root+" && go build -o "+u.Exe+" .")
		return 1
	}
	u.say("rebuilt %s", u.Exe)
	v := exec.Command(u.Exe, "-V")
	v.Stdout, v.Stderr = u.Stdout, u.Stderr
	v.Run()
	return 0
}
