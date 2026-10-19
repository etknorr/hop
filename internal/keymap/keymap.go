// Package keymap is the modal layer (lib/ui.zsh:36-311): NORMAL and SEARCH binds, their headers, and the actions `hop __key` returns.
package keymap

import (
	"slices"
	"strings"
)

// Keys is _HOP_VIM_KEYS: every key NORMAL owns, which is every printable ASCII key plus two page keys.
// - fzf's --disabled stops filtering, never insertion, so `ignore` on each unowned key is what makes NORMAL real.
// - ( and ) are absent because fzf balances parens inside unbind(...); they get binds and unbinds of their own.
var Keys = func() []string {
	var k []string
	for c := 'a'; c <= 'z'; c++ {
		k = append(k, string(c))
	}
	for c := 'A'; c <= 'Z'; c++ {
		k = append(k, string(c))
	}
	for c := '0'; c <= '9'; c++ {
		k = append(k, string(c))
	}
	k = append(k, "space")
	for _, c := range "!\"#$%&'*+,-./:;<=>?@[\\]^_`{|}~" {
		k = append(k, string(c))
	}
	return append(k, "ctrl-d", "ctrl-u")
}()

// GuardKeys are the keys whose action leaves the picker, so the escape guard has to cover them.
var GuardKeys = []string{"o", "O", "e", "y", "Y", "b", "c", "l", "h", "q"}

// guardOwn are the alt- keys hop or fzf already owns, which must not become mark binds.
// - alt-b, alt-d and alt-f are fzf's word motions, which SEARCH needs; alt-g and alt-c are the shell widgets' muscle memory.
var guardOwn = []string{"a", "o", "p", "y", "B", "b", "c", "d", "f", "g", "ctrl-d", "ctrl-u"}

const (
	NormalPrompt     = "> "
	SearchPrompt     = "/ "
	MenuPrompt       = ": "
	MenuSearchPrompt = ":/ "
	MenuHeader       = "VIEW  enter switch  esc back  j/k move  / filter"
	PreviewCmd       = "hop __preview {2} {3}"
	HelpLabel        = " keys "
)

// Header is _hop_vim_header: the mode name first, re-flowed to three lines when one won't fit the list pane.
// - Above 120 columns the preview takes 55%, so the pane is 45% of the terminal; fzf clips a header rather than wrapping it.
func Header(mode, enter string, menu bool, cols int) string {
	avail := cols
	if cols >= 120 {
		avail = cols * 45 / 100
	}
	avail -= 4
	e, alt, c := "enter "+enter, "", ""
	if enter != "cd" {
		alt, c = "  M-enter cd", "  c cd"
	}
	if mode == "SEARCH" {
		l := "SEARCH  type to filter  esc normal  " + e + alt + "  ^o code  ^y yank  M-B browse"
		if len(l) > avail {
			l = "SEARCH  type to filter\nesc normal  " + e + alt + "\n^o code  ^y yank  M-B browse"
		}
		return l
	}
	view := ""
	if menu {
		view = "  : view"
	}
	l := "NORMAL  j/k move  g/G top/bot  / search" + view + "  ? help  " + e + c + "  q quit"
	if len(l) > avail {
		l = "NORMAL  j/k move  g/G top/bot\n/ search" + view + "  ? help\n" + e + c + "  q quit"
	}
	return l
}

// Map is one picker's modal keymap.
type Map struct {
	// Enter is what Enter does here, already named open on folder rows.
	Enter                            string
	Menu, Restore, Reload, Drill, Up bool
	Guard                            bool
	Cols                             int
}

func (m Map) normal() string { return Header("NORMAL", m.Enter, m.Menu, m.Cols) }
func (m Map) search() string { return Header("SEARCH", m.Enter, false, m.Cols) }

// Live is the optional keys this picker binds, which the `?` overlay names; the legend must never advertise a dead key.
func (m Map) Live() []string {
	var l []string
	if m.Restore {
		l = append(l, "r")
	}
	if m.Menu {
		l = append(l, ":")
	}
	if m.Drill {
		l = append(l, "l")
	}
	if m.Up {
		l = append(l, "h")
	}
	if m.Reload {
		l = append(l, "M-a")
	}
	return l
}

var (
	keyList   = strings.Join(Keys, ",")
	UnbindAll = "unbind(" + keyList + ")+unbind(()+unbind())"
	RebindAll = "rebind(" + keyList + ")+rebind(()+rebind())"
)

// Restore puts the real preview back on every nav key, which is what closes the `?` overlay; the label is the overlay's state.
const Restore = "change-preview(" + PreviewCmd + ")+change-preview-label()"

// ToSearch is `/`: end-of-line because ctrl-a isn't a NORMAL key, so a kept query's cursor can sit at its start.
func (m Map) ToSearch() string {
	return UnbindAll + "+enable-search+end-of-line+change-prompt(" + SearchPrompt + ")+change-header(" + m.search() + ")+" + Restore
}

// ToNormal is esc from SEARCH: the query stays and keeps filtering, so j/k walk the filtered rows.
// - Search stays enabled in NORMAL; disabling it once left a cleared query unmatched, frozen at 0 rows.
func (m Map) ToNormal() string {
	return RebindAll + "+change-prompt(" + NormalPrompt + ")+change-header(" + m.normal() + ")+" + Restore
}

// ToMenu is `:`, the kind menu in place; clear-query first, or a kept query filters the kind list to nothing.
func (m Map) ToMenu() string {
	return "clear-query+change-prompt(" + MenuPrompt + ")+change-header(" + MenuHeader + ")+change-preview-label()+reload(hop __menu)"
}

// View is leaving the menu for the session's current view; the query filtered kinds, so it goes.
func (m Map) View(fromSearch bool) string {
	s := "clear-query+reload(hop __rows)+change-prompt(" + NormalPrompt + ")+change-header(" + m.normal() + ")+" + Restore + "+first"
	if fromSearch {
		s = RebindAll + "+" + s
	}
	return s
}

// MenuSearch is `/` inside the menu: its own prompt, so esc and enter still know the list holds kinds.
func (m Map) MenuSearch() string {
	return UnbindAll + "+enable-search+end-of-line+change-prompt(" + MenuSearchPrompt + ")+" + Restore
}

// MenuNormal is esc from the menu's search, back to its NORMAL with the filter kept.
func (m Map) MenuNormal() string {
	return RebindAll + "+change-prompt(" + MenuPrompt + ")+change-header(" + MenuHeader + ")"
}

const helpOn = "show-preview+change-preview(hop __keys)+change-preview-label(" + HelpLabel + ")"

// Verb is a NORMAL key's action, or "" for ignore; letter verbs ride print()+accept, since an --expect key stays live after unbind.
// - The printed name is the key SEARCH uses for the same verb, so one dispatch arm serves both modes.
func (m Map) Verb(k string) string {
	switch k {
	case "j":
		return "down+" + Restore
	case "k":
		return "up+" + Restore
	case "g":
		return "first+" + Restore
	case "G":
		return "last+" + Restore
	case "ctrl-d":
		return "half-page-down+" + Restore
	case "ctrl-u":
		return "half-page-up+" + Restore
	case "o":
		return "print(ctrl-o)+accept"
	case "O":
		return "print(ctrl-t)+accept"
	case "e":
		return "print(alt-o)+accept"
	case "y":
		return "print(ctrl-y)+accept"
	case "Y":
		return "print(alt-y)+accept"
	case "b":
		return "print(ctrl-g)+accept"
	case "c":
		return "print(alt-enter)+accept"
	case "p":
		return "toggle-preview"
	case "q":
		return "abort"
	case "r":
		if m.Restore {
			return "reload(hop __rows)"
		}
	case "l":
		if m.Drill {
			return "print(ctrl-l)+accept"
		}
	case "h":
		if m.Up {
			return "print(ctrl-h)+accept"
		}
	case "/":
		return m.ToSearch()
	case ":":
		if m.Menu {
			return m.ToMenu()
		}
	}
	return ""
}

// Binds is _hop_vim_binds: the whole modal --bind set, plus the prompt and header the picker opens with.
// - A CLI query starts in SEARCH, filtering; an empty one starts in NORMAL with search off, which lists the same rows.
// - A resolver note rides --header, and the start bind skips change-header, which would wipe it.
func (m Map) Binds(query, note string) (args []string, prompt, header string) {
	for _, k := range Keys {
		act := m.Verb(k)
		switch {
		case k == "?" || (k == "/" && m.Menu):
			act = "transform:hop __key " + k
		case act == "":
			act = "ignore"
		case m.Guard && slices.Contains(GuardKeys, k):
			act = "transform:hop __guard check " + k
		case k == "c" && m.Menu:
			act = "transform:hop __key c"
		}
		args = append(args, "--bind="+k+":"+act)
	}
	args = append(args, "--bind=(:ignore", "--bind=):ignore")
	// fzf turns any ESC it can't parse into a bindable alt-<char>, so one rule covers OSC, DCS, PM, APC, SOS and ST.
	// - execute-silent blocks fzf until it returns, which is load-bearing: an async mark would race the payload behind it.
	if m.Guard {
		for _, k := range Keys {
			if !slices.Contains(guardOwn, k) {
				args = append(args, "--bind=alt-"+k+":execute-silent(hop __guard mark)")
			}
		}
	}
	args = append(args, "--bind=esc:transform:hop __key esc")
	if m.Menu {
		args = append(args, "--bind=enter:transform:hop __key enter {2}")
	}
	if query == "" {
		return append(args, "--disabled"), NormalPrompt, m.normal()
	}
	header = m.search()
	if note != "" {
		header = note + "\n" + header
		return append(args, "--bind=start:"+UnbindAll+"+enable-search+change-prompt("+SearchPrompt+")+"+Restore), SearchPrompt, header
	}
	return append(args, "--bind=start:"+m.ToSearch()), SearchPrompt, header
}

func inMenu(prompt string) bool { return strings.HasPrefix(prompt, ":") }

// Key is `hop __key`, every decision a bind can't make, read from fzf's exported state so no POSIX `case` runs under fish.
// - The prompt is the mode: NORMAL is search-off at startup and search-on after an esc, so FZF_INPUT_STATE can't say.
// - view is non-nil when enter switched the menu to a kind, which the caller records as the session's current view.
func (m Map) Key(key, arg, prompt, query, label string, kinds []string) (act string, view []string) {
	switch key {
	case "esc":
		switch {
		case prompt == MenuSearchPrompt:
			return m.MenuNormal(), nil
		case inMenu(prompt):
			return m.View(false), nil
		case prompt == SearchPrompt:
			return m.ToNormal(), nil
		case query != "":
			return "clear-query", nil
		}
		return "abort", nil
	case "enter":
		if !inMenu(prompt) {
			return "accept", nil
		}
		if !slices.Contains(kinds, arg) {
			return "ignore", nil
		}
		return m.View(prompt == MenuSearchPrompt), []string{arg}
	case "alt-enter", "c":
		if inMenu(prompt) {
			return "ignore", nil
		}
		return "print(alt-enter)+accept", nil
	case "/":
		if inMenu(prompt) {
			return m.MenuSearch(), nil
		}
		return m.ToSearch(), nil
	case "?":
		if label != "" {
			return Restore, nil
		}
		return helpOn, nil
	}
	return "ignore", nil
}
