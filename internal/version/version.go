// Package version is the binary's version, where it came from, and the hash its shell integration is checked against.
package version

import (
	"regexp"
	"runtime/debug"
	"strings"

	"github.com/etknorr/hop/internal/shell"
)

// Version is the release build's -X value, which goreleaser and the formula set; empty in any other build.
var Version = ""

// Module is this binary's module path, which `go install` records and upgrade checks for.
const Module = "github.com/etknorr/hop"

var release = regexp.MustCompile(`^v?[0-9]+\.[0-9]+\.[0-9]+$`)

// Info is what the build recorded about itself.
type Info struct {
	Version    string
	Revision   string
	Dirty      bool
	ModPath    string
	ModVersion string
	Stamped    bool
}

// Checkout reports a plain `go build` in a work tree: VCS stamped, no release -X.
func (i Info) Checkout() bool { return !i.Stamped && i.Revision != "" }

// Read is Info from the -X value and the build info.
// - `go install mod@v1.2.3` records v1.2.3 and no VCS keys; a checkout build records vcs.revision and, since Go 1.24, a pseudo-version.
// - A checkout build is "devel" unless HEAD sits clean on a release tag, so a pseudo-version never reads as a release.
func Read() Info { return read(Version, debug.ReadBuildInfo) }

func read(stamp string, bi func() (*debug.BuildInfo, bool)) Info {
	i := Info{Version: "devel"}
	if b, ok := bi(); ok {
		i.ModPath, i.ModVersion = b.Main.Path, b.Main.Version
		for _, s := range b.Settings {
			switch s.Key {
			case "vcs.revision":
				i.Revision = s.Value
			case "vcs.modified":
				i.Dirty = s.Value == "true"
			}
		}
		if release.MatchString(i.ModVersion) {
			i.Version = strings.TrimPrefix(i.ModVersion, "v")
		}
	}
	if stamp != "" {
		i.Version, i.Stamped = strings.TrimPrefix(stamp, "v"), true
	}
	return i
}

// String is the bare version: 1.0.0, or devel for a checkout build between releases.
func String() string { return Read().Version }

// Line is `hop -V`'s first line: `hop 1.0.0`, with `(abc1234, dirty)` added for a checkout build.
func Line() string { return line(Read()) }

func line(i Info) string {
	s := "hop " + i.Version
	if !i.Checkout() {
		return s
	}
	rev := i.Revision
	if len(rev) > 7 {
		rev = rev[:7]
	}
	if i.Dirty {
		return s + " (" + rev + ", dirty)"
	}
	return s + " (" + rev + ")"
}

// InitHash is the hash `hop init` bakes into every script, which the shell hands back as HOP_INIT_HASH.
func InitHash() string { return shell.Hash() }

// Stale is the line -V and --doctor add when the shell's integration came from other templates than this binary's.
// - Empty when the call didn't come through the shell function, since then there is nothing to compare.
func Stale(initHash, sh string) string {
	if initHash == "" || initHash == InitHash() {
		return ""
	}
	reload := "exec $SHELL"
	if sh != "" {
		reload = "exec " + sh
	}
	return "hop: your shell integration predates this hop: run '" + reload + "' to reload it"
}
