// Package pick is the picker: the fzf argv, the session its callbacks read, the `__sh` shim, the preview and the result parse.
package pick

import (
	"regexp"
	"runtime"
	"strings"

	"github.com/etknorr/hop/internal/keymap"
	"github.com/etknorr/hop/internal/match"
)

// Opts is one picker: _hop_pick's arguments plus the _hop_pick_* fields _hop_res_pick sets by dynamic scope.
// - Height "" is fullscreen, which is HOP_FZF_HEIGHT set but empty.
// - Reload is alt-a's kind list; nil binds nothing, as on the workspace and repo levels.
// - Menu is a root to enumerate kinds from, Drill and Up the level moves ctrl-l and ctrl-h make.
// - Vim is the modal layer; without it the picker is plain fzf search under the legend.
// - ShellQuotes is an fzf that parses quotes in --with-shell, 0.71.0 on.
// - Enter names what Enter does, for the modal headers, and Cols is the terminal width they're fitted to.
type Opts struct {
	Self, Label, Legend, Note, Query string
	Height, Enter                    string
	Reload                           []string
	Menu, Drill, Up, FreezeLeft      bool
	ShellQuotes                      bool
	Select1, Ordered                 bool
	Vim                              bool
	Cols                             int
}

// Keys is the modal keymap; the session carries it, so every `hop __key` builds the same strings the argv did.
// - The guard exists only with the modal layer, and r only where `:` can enumerate kinds.
func (o Opts) Keys() keymap.Map {
	return keymap.Map{Enter: o.Enter, Menu: o.Menu, Restore: o.Menu, Reload: len(o.Reload) > 0, Drill: o.Drill, Up: o.Up, Guard: o.Vim, Cols: o.Cols}
}

const (
	Prompt = "hop ▸ "
	// Expect is _hop_pick's --expect list; ctrl-g rides alt-B's print() instead, since a stray BEL byte is ctrl-g.
	Expect        = "ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y"
	PreviewCmd    = keymap.PreviewCmd
	PreviewWindow = "right,55%,border-left,wrap,<120(down,50%,border-top,wrap)"
)

// Header is the note, when the resolver left one, above the legend.
func (o Opts) Header() string {
	if o.Note != "" {
		return o.Note + "\n" + o.Legend
	}
	return o.Legend
}

var plainPath = regexp.MustCompile(`^[A-Za-z0-9_./+@%:,=-]+$`)

// WithShell is --with-shell: fzf runs every callback as `<hop> __sh <command>`, so no user shell parses a bind.
//   - fzf before 0.71.0 splits the value on whitespace and keeps quotes (#4709), so only a plain path goes in as it is.
//   - A path that needs quoting is quoted for fzf that parses quotes, and otherwise reached through PATH, as on Windows,
//     whose fzf splits with strings.Fields too.
func WithShell(self string, quotes bool) string {
	switch {
	case plainPath.MatchString(self):
		return self + " __sh"
	case runtime.GOOS == "windows" && !strings.ContainsAny(self, " \t"):
		return self + " __sh"
	case quotes && runtime.GOOS != "windows":
		return "'" + strings.ReplaceAll(self, "'", `'\''`) + "' __sh"
	}
	return "hop __sh"
}

// Args is _hop_pick's argv: every callback is a `hop __verb`, and no bind string holds a path.
func Args(o Opts) []string {
	expect := Expect
	if o.Drill {
		expect += ",ctrl-l"
	}
	if o.Up {
		expect += ",ctrl-h"
	}
	a := append([]string{}, match.Flags...)
	a = append(a,
		"--with-shell="+WithShell(o.Self, o.ShellQuotes),
		"--accept-nth=2,3,4",
		"--no-multi",
		"--layout=reverse",
		"--info=inline",
		"--border=rounded",
		"--border-label= "+o.Label+" ",
		"--header-first",
		"--header-border=bottom",
		"--pointer=▸",
		"--expect="+expect,
		"--preview="+PreviewCmd,
		"--preview-window="+PreviewWindow,
		"--bind=ctrl-/:toggle-preview",
		"--bind=alt-p:toggle-preview",
		"--bind=ctrl-r:refresh-preview",
		"--bind=ctrl-g:ignore",
		"--bind=alt-B:print(ctrl-g)+accept",
	)
	// alt-enter always cds, but a menu row names a kind, not a dir, so with a menu it asks whether one is on screen.
	if o.Vim && o.Menu {
		a = append(a, "--bind=alt-enter:transform:hop __key alt-enter")
	} else {
		a = append(a, "--bind=alt-enter:print(alt-enter)+accept")
	}
	if o.Height != "" {
		a = append(a, "--height="+o.Height, "--min-height=18")
	}
	if o.FreezeLeft {
		a = append(a, "--freeze-left=1")
	}
	if o.Query != "" {
		a = append(a, "--query="+o.Query)
	}
	if len(o.Reload) > 0 {
		a = append(a, "--bind=alt-a:reload(hop __rows "+strings.Join(o.Reload, " ")+")")
	}
	if o.Select1 {
		a = append(a, "--select-1")
	}
	// Ordered opens on the resolver's best rows first; fzf's own ranking returns at the first keystroke.
	if o.Ordered {
		a = append(a, "--no-sort", "--bind=change:toggle-sort+unbind(change)")
	}
	if !o.Vim {
		return append(a, "--prompt="+Prompt, "--header="+o.Header())
	}
	binds, prompt, header := o.Keys().Binds(o.Query, o.Note)
	a = append(a, binds...)
	return append(a, "--prompt="+prompt, "--header="+header)
}

// Legend is _hop_header, the non-modal legend: the keys, each line short enough for a 36-column list pane.
// - mode is what Enter does; on workspace and repo rows reveal is named open, since both run `code -n` there.
// - hop 0.3.1 names alt-a `M-a +conf`, after one user's kind; 1.0 says what it does.
func Legend(mode string, folder, reload bool) string {
	mode = EnterName(mode, folder)
	lines := []string{"enter cd · ^O file · ^T folder", "^Y copy · M-y copy file · M-o edit"}
	if mode != "cd" {
		lines = []string{"enter " + mode + " · M-enter cd", "^O file · ^T folder · ^Y copy", "M-y copy file · M-o edit"}
	}
	if reload {
		lines = append(lines, "M-B github · M-a all · M-p preview")
	} else {
		lines = append(lines, "M-B github · M-p preview")
	}
	return strings.Join(lines, "\n")
}

// EnterName is _hop_enter_mode's naming: on folder rows reveal runs `code -n` too, so it is called open.
func EnterName(mode string, folder bool) string {
	if folder {
		return strings.Replace(mode, "reveal", "open", 1)
	}
	return mode
}
