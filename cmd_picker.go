package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/etknorr/hop/internal/act"
	"github.com/etknorr/hop/internal/guard"
	"github.com/etknorr/hop/internal/keymap"
	"github.com/etknorr/hop/internal/pick"
	"github.com/etknorr/hop/internal/workspace"
)

// pickerVerbs are the modal layer's callbacks and hopw, each the first word only.
var pickerVerbs = map[string]func(args []string, stdout, stderr io.Writer) int{
	"__key":   cmdKey,
	"__keys":  cmdKeys,
	"__guard": cmdGuard,
	"__hopw":  cmdHopw,
}

func loadSession(stderr io.Writer) *pick.Session {
	s, err := pick.Load()
	if err != nil {
		fmt.Fprintln(stderr, "hop:", err)
		return nil
	}
	return s
}

// cmdKey is `hop __key <key> [arg]`, the decisions a bind can't make, from the state fzf exports to every callback.
// - Enter on a menu row records the kind as the current view, so r and esc out of a later menu come back to it.
func cmdKey(args []string, stdout, stderr io.Writer) int {
	s := loadSession(stderr)
	if s == nil || len(args) == 0 {
		return 2
	}
	a, view := s.Keys.Key(args[0], argAt(args, 1), os.Getenv("FZF_PROMPT"), os.Getenv("FZF_QUERY"), os.Getenv("FZF_PREVIEW_LABEL"), s.All)
	if view != nil {
		s.View = view
		if err := s.Save(); err != nil {
			fmt.Fprintln(stderr, "hop:", err)
		}
	}
	io.WriteString(stdout, a)
	return 0
}

// cmdKeys is the `?` overlay.
func cmdKeys(args []string, stdout, stderr io.Writer) int {
	s := loadSession(stderr)
	if s == nil {
		return 2
	}
	io.WriteString(stdout, keymap.Overlay(s.Keys.Enter, s.Keys.Live()))
	return 0
}

// cmdGuard is `hop __guard mark` and `hop __guard check <key>`; the mark lives in the session's private directory.
// - check prints the key's NORMAL action, or ignore when the guard refuses it; c on a menu row is ignore either way.
// - Anything malformed is silent and succeeds, since fzf would show a failed transform as a dead key.
func cmdGuard(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		return 0
	}
	mark := ""
	if p := pick.Path(); p != "" {
		mark = filepath.Join(filepath.Dir(p), "mark")
	}
	switch args[0] {
	case "mark":
		guard.Mark(mark)
		return 0
	case "check":
		if len(args) < 2 || !slices.Contains(keymap.GuardKeys, args[1]) {
			return 0
		}
		s := loadSession(stderr)
		if s == nil {
			return 0
		}
		k := args[1]
		a := s.Keys.Verb(k)
		if k == "c" && s.Keys.Menu {
			a, _ = s.Keys.Key("c", "", os.Getenv("FZF_PROMPT"), "", "", nil)
		}
		if a == "" || a == "ignore" {
			io.WriteString(stdout, "ignore")
			return 0
		}
		if !guard.Check(mark, guard.Window(os.Getenv("HOP_GUARD_WINDOW"))) {
			a = "ignore"
		}
		io.WriteString(stdout, a)
	}
	return 0
}

// cmdHopw is hopw: cd to the workspace holding the physical $PWD, longest prefix first, since workspaces can nest.
func cmdHopw(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 {
		fmt.Fprintln(stderr, "hop: hopw takes no arguments")
		return 2
	}
	cfg, err := load(stderr)
	if err != nil {
		fmt.Fprintln(stderr, "hop:", err)
		return 1
	}
	set := cfg.Settings
	pwd := logicalPWD()
	ws, ok := wsFor(realpath(pwd), workspace.Parse(set.Workspaces, set.WorkspacesFile))
	if !ok {
		fmt.Fprintf(stderr, "hop: %s is not inside any configured workspace\n", pwd)
		return 1
	}
	return act.CD(ws, stdout, stderr, set.HistFile, set.HistMax)
}

// wsFor is _hop_ws_for: the longest workspace path that is dir or one of its parents.
func wsFor(dir string, wss []workspace.Workspace) (string, bool) {
	best := ""
	for _, w := range wss {
		if (dir == w.Path || strings.HasPrefix(dir, w.Path+"/")) && len(w.Path) > len(best) {
			best = w.Path
		}
	}
	return best, best != ""
}
