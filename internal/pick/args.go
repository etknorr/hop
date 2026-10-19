// Package pick is the picker: the fzf argv, the session its callbacks read, the `__sh` shim, the preview and the result parse.
package pick

import (
	"runtime"
	"strings"

	"github.com/etknorr/hop/internal/match"
)

// Opts is one picker: _hop_pick's arguments plus the _hop_pick_* fields _hop_res_pick sets by dynamic scope.
// - Height "" is fullscreen, which is HOP_FZF_HEIGHT set but empty.
// - Reload is alt-a's kind list; nil binds nothing, as on the workspace and repo levels.
// - Menu is a root to enumerate, so alt-k opens the kind menu and enter, esc and alt-enter ask `__key` first.
type Opts struct {
	Self, Label, Legend, Note, Query string
	Height                           string
	Reload                           []string
	Menu, FreezeLeft                 bool
	Select1, Ordered                 bool
}

const (
	Prompt = "hopx ▸ "
	// Expect is _hop_pick's --expect list; ctrl-g rides alt-B's print() instead, since a stray BEL byte is ctrl-g.
	Expect        = "ctrl-o,ctrl-t,ctrl-y,alt-o,alt-y"
	PreviewCmd    = "hopx __preview {2} {3}"
	PreviewWindow = "right,55%,border-left,wrap,<120(down,50%,border-top,wrap)"
	MenuPrompt    = ": "
	MenuHeader    = "KINDS  enter switch  esc back  type to filter"
	// MenuOpen clears the query so the kind list isn't filtered by the target query typed so far.
	MenuOpen = "change-prompt(" + MenuPrompt + ")+change-header(" + MenuHeader + ")+change-preview-label()+clear-query+reload(hopx __menu)"
)

// Header is the note, when the resolver left one, above the legend.
func (o Opts) Header() string {
	if o.Note != "" {
		return o.Note + "\n" + o.Legend
	}
	return o.Legend
}

// WithShell is --with-shell: fzf runs every callback as `<hopx> __sh <command>`, so no user shell parses a bind.
// - Windows fzf splits the value with strings.Fields, so a path holding a space has to be reached through PATH.
func WithShell(self string) string {
	if runtime.GOOS == "windows" {
		if strings.ContainsAny(self, " \t") {
			return "hopx __sh"
		}
		return self + " __sh"
	}
	return "'" + strings.ReplaceAll(self, "'", `'\''`) + "' __sh"
}

// Args is _hop_pick's argv without the modal layer: every callback is a `hopx __verb`, and no bind string holds a path.
func Args(o Opts) []string {
	a := append([]string{}, match.Flags...)
	a = append(a,
		"--with-shell="+WithShell(o.Self),
		"--accept-nth=2,3,4",
		"--no-multi",
		"--layout=reverse",
		"--info=inline",
		"--border=rounded",
		"--border-label= "+o.Label+" ",
		"--header-first",
		"--header-border=bottom",
		"--pointer=▸",
		"--expect="+Expect,
		"--preview="+PreviewCmd,
		"--preview-window="+PreviewWindow,
		"--bind=ctrl-/:toggle-preview",
		"--bind=alt-p:toggle-preview",
		"--bind=ctrl-r:refresh-preview",
		"--bind=ctrl-g:ignore",
		"--bind=alt-B:print(ctrl-g)+accept",
	)
	if o.Menu {
		a = append(a,
			"--bind=alt-enter:transform:hopx __key alt-enter",
			"--bind=enter:transform:hopx __key enter {2}",
			"--bind=esc:transform:hopx __key esc",
			"--bind=alt-k:"+MenuOpen,
		)
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
		a = append(a, "--bind=alt-a:reload(hopx __rows "+strings.Join(o.Reload, " ")+")")
	}
	if o.Select1 {
		a = append(a, "--select-1")
	}
	// Ordered opens on the resolver's best rows first; fzf's own ranking returns at the first keystroke.
	if o.Ordered {
		a = append(a, "--no-sort", "--bind=change:toggle-sort+unbind(change)")
	}
	return append(a, "--prompt="+Prompt, "--header="+o.Header())
}

// Legend is _hop_header: the keys, each line short enough for a 36-column list pane.
// - mode is what Enter does; on workspace and repo rows reveal is named open, since both run `code -n` there.
func Legend(mode string, folder, reload, menu bool) string {
	if folder {
		mode = strings.Replace(mode, "reveal", "open", 1)
	}
	lines := []string{"enter cd · ^O file · ^T folder", "^Y copy · M-y copy file · M-o edit"}
	if mode != "cd" {
		lines = []string{"enter " + mode + " · M-enter cd", "^O file · ^T folder · ^Y copy", "M-y copy file · M-o edit"}
	}
	last := "M-B github · M-p preview"
	switch {
	case reload && menu:
		lines = append(lines, last, "M-a all kinds · M-k kind menu")
	case reload:
		lines = append(lines, last+" · M-a all")
	case menu:
		lines = append(lines, last+" · M-k kinds")
	default:
		lines = append(lines, last)
	}
	return strings.Join(lines, "\n")
}
