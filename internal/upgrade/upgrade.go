package upgrade

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/etknorr/hop/internal/version"
)

// DefaultRemote is where brew and go install releases are published; HOP_UPGRADE_REMOTE overrides it for tests.
const DefaultRemote = "https://github.com/etknorr/hop"

const formula = "etknorr/hop/hop"

var strict = regexp.MustCompile(`^v[0-9]+\.[0-9]+\.[0-9]+$`)

// Upgrader is one `hop upgrade` call: the install it moves and where it reports.
type Upgrader struct {
	Install
	Version        string
	Stale          string
	Stdout, Stderr io.Writer
}

func (u *Upgrader) err(lines ...string) {
	for _, l := range lines {
		fmt.Fprintln(u.Stderr, "hop upgrade: "+l)
	}
}

func (u *Upgrader) say(format string, a ...any) { fmt.Fprintf(u.Stdout, format+"\n", a...) }

func (u *Upgrader) usage() {
	u.say("usage: hop upgrade [--check] [VERSION]")
	u.say("")
	u.say("  hop upgrade           update to the newest release, the way hop was installed")
	u.say("  hop upgrade 1.2.0     install exactly that release (v1.2.0 works too); not under brew")
	u.say("  hop upgrade --check   report installed vs released, changing nothing")
	u.say("")
	switch u.Method {
	case Brew:
		u.say("  this hop is brew's: %s", u.Exe)
	case GoInstall:
		u.say("  this hop came from go install: %s", u.Exe)
	case Checkout:
		u.say("  this hop is built from the checkout at %s", u.Root)
		u.say("  refuses when that checkout is dirty, on a side branch, or has no origin")
	default:
		u.say("  this hop's install method is unknown: %s", u.Exe)
	}
}

// Run is the whole verb: parse, then hand off to the install method.
func (u *Upgrader) Run(args []string) int {
	check := false
	want := ""
	for _, a := range args {
		switch {
		case a == "--check" || a == "--dry-run" || a == "-n":
			check = true
		case a == "-h" || a == "--help":
			u.usage()
			return 0
		case strings.HasPrefix(a, "-"):
			u.err("unknown option: "+a, "Try: hop upgrade --help")
			return 2
		case want != "":
			u.err(fmt.Sprintf("takes at most one version, got %s and %s", want, a))
			return 2
		default:
			want = a
		}
	}
	if check && want != "" {
		u.err("--check reports on this install and takes no version, got "+want, "To move to a version: hop upgrade "+want)
		return 2
	}
	tag := ""
	if want != "" {
		t, ok := norm(want)
		if !ok {
			u.err("not a version: "+want, "Expected X.Y.Z, for example 1.0.0 or v1.0.0.")
			return 2
		}
		tag = t
	}
	if _, err := exec.LookPath("git"); err != nil {
		u.err("git is not installed, and every release check needs it.")
		return 1
	}
	switch u.Method {
	case Checkout:
		return u.checkout(check, tag)
	case Brew:
		if tag != "" && !check {
			u.err("brew installs the newest release only, so it cannot pin "+tag+".",
				"To pin: brew uninstall hop && go install "+version.Module+"@"+tag)
			return 2
		}
		if check {
			return u.report()
		}
		return u.runTool("brew", "upgrade", formula)
	case GoInstall:
		if check {
			return u.report()
		}
		return u.goInstall(tag)
	}
	if check {
		return u.report()
	}
	u.err("cannot tell how this hop was installed, so there is nothing to run: "+u.Exe,
		"Install it one of these ways, then upgrade from there:",
		"  brew tap etknorr/hop "+DefaultRemote+" && brew install "+formula,
		"  go install "+version.Module+"@latest",
		"  git clone "+DefaultRemote+" && cd hop && go build -o bin/hop .")
	return 1
}

// norm accepts 1.2.3 and v1.2.3 alike, as the tag name.
func norm(v string) (string, bool) {
	t := "v" + strings.TrimPrefix(v, "v")
	return t, strict.MatchString(t)
}

type semver [3]int

func parse(v string) (semver, bool) {
	var s semver
	p := strings.Split(strings.TrimPrefix(v, "v"), ".")
	if len(p) != 3 {
		return s, false
	}
	for i, x := range p {
		n, err := strconv.Atoi(x)
		if err != nil || n < 0 {
			return s, false
		}
		s[i] = n
	}
	return s, true
}

func cmpSemver(a, b semver) int {
	for i := range a {
		if a[i] != b[i] {
			return a[i] - b[i]
		}
	}
	return 0
}

// sortTags keeps the strict vX.Y.Z tags, newest first, so a prerelease or topic tag can never be "latest".
func sortTags(tags []string) []string {
	var out []string
	for _, t := range tags {
		if strict.MatchString(t) && !slices.Contains(out, t) {
			out = append(out, t)
		}
	}
	slices.SortFunc(out, func(a, b string) int {
		x, _ := parse(a)
		y, _ := parse(b)
		return cmpSemver(y, x)
	})
	return out
}

// remoteTags is the published release tags at url, newest first, from ls-remote so no API token is needed.
func remoteTags(url string) ([]string, error) {
	out, err := exec.Command("git", "ls-remote", "--tags", "--refs", url).Output()
	if err != nil {
		return nil, err
	}
	var tags []string
	for l := range strings.SplitSeq(string(out), "\n") {
		if _, ref, ok := strings.Cut(l, "\t"); ok {
			tags = append(tags, strings.TrimPrefix(ref, "refs/tags/"))
		}
	}
	return sortTags(tags), nil
}

func remote() string {
	if r := os.Getenv("HOP_UPGRADE_REMOTE"); r != "" {
		return r
	}
	return DefaultRemote
}

// report is --check for brew, go install and unknown installs: the binary's version against the newest published tag.
func (u *Upgrader) report() int {
	u.say("  %-10s %s", "installed", u.Version)
	tags, err := remoteTags(remote())
	if err != nil {
		u.err("could not list the releases at " + remote() + ", so there is nothing to compare.")
		return 1
	}
	if len(tags) == 0 {
		u.say("  %-10s %s", "released", "none yet, so there is nothing to update to")
		return 0
	}
	latest := tags[0]
	u.say("  %-10s %s", "released", latest)
	have, ok := parse(u.Version)
	l, _ := parse(latest)
	switch {
	case !ok:
		u.say("  %s is not a release, so it cannot be compared", u.Version)
	case cmpSemver(have, l) >= 0:
		u.say("  up to date")
	case u.Method == Unknown:
		u.say("  an update is available, but this install's method is unknown: run 'hop upgrade' for the options")
	default:
		u.say("  an update is available: run 'hop upgrade'")
	}
	return 0
}

func (u *Upgrader) runTool(name string, args ...string) int {
	if _, err := exec.LookPath(name); err != nil {
		u.err(name + " is not on PATH, and this hop was installed with it.")
		return 1
	}
	c := exec.Command(name, args...)
	c.Stdout, c.Stderr = u.Stdout, u.Stderr
	if err := c.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode()
		}
		u.err(err.Error())
		return 1
	}
	return 0
}

// goInstall runs go install, warning first when go would write somewhere other than this binary's dir.
func (u *Upgrader) goInstall(tag string) int {
	if _, err := exec.LookPath("go"); err != nil {
		u.err("go is not on PATH, and this hop was installed with go install.")
		return 1
	}
	if bin := goBin(); bin != "" && !sameDir(bin, filepath.Dir(u.Exe)) {
		u.err("go install writes to "+bin+", but this hop runs from "+filepath.Dir(u.Exe)+",",
			"so the hop on your PATH may stay at "+u.Version+".")
	}
	if tag == "" {
		tag = "latest"
	}
	return u.runTool("go", "install", version.Module+"@"+tag)
}

func goBin() string {
	out, err := exec.Command("go", "env", "GOBIN", "GOPATH").Output()
	if err != nil {
		return ""
	}
	l := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
	if len(l) > 0 && l[0] != "" {
		return l[0]
	}
	if len(l) > 1 && l[1] != "" {
		return filepath.Join(strings.Split(l[1], string(os.PathListSeparator))[0], "bin")
	}
	return ""
}

func sameDir(a, b string) bool {
	x, err1 := os.Stat(a)
	y, err2 := os.Stat(b)
	return err1 == nil && err2 == nil && os.SameFile(x, y)
}

// noop is a move that changed nothing, which is what someone runs when the last one "did not work", so it repeats a stale-shell warning.
func (u *Upgrader) noop() int {
	if u.Stale != "" {
		fmt.Fprintln(u.Stdout, u.Stale)
	}
	return 0
}
