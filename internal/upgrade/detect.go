// Package upgrade is `hop upgrade`: brew, go install and git checkout installs, each moved its own way, or refused with the reason.
package upgrade

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"

	"github.com/etknorr/hop/internal/version"
)

// Method is how this binary was installed, which decides what an upgrade runs.
type Method string

const (
	Brew      Method = "brew"
	GoInstall Method = "go install"
	Checkout  Method = "checkout"
	Unknown   Method = "unknown"
)

// Install is the running binary: where it is, how it got there, and for a checkout, the work tree.
type Install struct {
	Method Method
	Exe    string
	Root   string
}

// Detect reads the method off the executable's real path and the build info.
// - brew's Cellar path wins, since brew builds from a git clone and that build looks like a checkout's.
// - A checkout is a binary inside a tree whose go.mod is this module, however it was built.
// - `go install mod@version` is the module path with a version and no VCS stamp.
func Detect(exe string, info version.Info) Install {
	if p, err := filepath.EvalSymlinks(exe); err == nil {
		exe = p
	}
	in := Install{Method: Unknown, Exe: exe}
	switch {
	case strings.Contains(exe, "/Cellar/hop/"):
		in.Method = Brew
	case moduleRoot(filepath.Dir(exe)) != "":
		in.Method, in.Root = Checkout, moduleRoot(filepath.Dir(exe))
	case info.ModPath == version.Module && info.ModVersion != "" && info.ModVersion != "(devel)" && info.Revision == "":
		in.Method = GoInstall
	}
	return in
}

// moduleRoot is the nearest dir at or above dir whose go.mod declares this module, or "".
func moduleRoot(dir string) string {
	for {
		if f, err := os.Open(filepath.Join(dir, "go.mod")); err == nil {
			sc := bufio.NewScanner(f)
			for sc.Scan() {
				if fs := strings.Fields(sc.Text()); len(fs) == 2 && fs[0] == "module" {
					f.Close()
					if fs[1] == version.Module {
						return dir
					}
					return ""
				}
			}
			f.Close()
			return ""
		}
		up := filepath.Dir(dir)
		if up == dir {
			return ""
		}
		dir = up
	}
}
