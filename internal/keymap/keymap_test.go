package keymap

import (
	"fmt"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
)

func zsh(t *testing.T, script string, args ...string) string {
	t.Helper()
	if !testfix.HaveZsh() {
		t.Skip("no zsh or reference hop")
	}
	out, err := testfix.Zsh("/dev/null", script, []string{"HOP_VIM=1"}, args...)
	if err != nil {
		t.Fatal(err)
	}
	return out
}

var enters = []string{"cd", "open", "reveal", "cd+open", "cd+reveal"}

// TestHeaderLiveZsh holds both mode headers to _hop_vim_header across the widths where they re-flow.
func TestHeaderLiveZsh(t *testing.T) {
	var cases, want []string
	for _, cols := range []int{40, 60, 78, 79, 80, 100, 119, 120, 150, 171, 172, 200} {
		for _, e := range enters {
			for _, h := range []struct {
				mode string
				menu bool
			}{{"NORMAL", true}, {"NORMAL", false}, {"SEARCH", false}} {
				root := ""
				if h.menu {
					root = "/r"
				}
				cases = append(cases, fmt.Sprintf("%d %s %s %s", cols, e, h.mode, root))
				want = append(want, strings.ReplaceAll(Header(h.mode, e, h.menu, cols), "\n", `\n`))
			}
		}
	}
	out := zsh(t, `for c in "$@"; do
		local -a w=(${=c})
		COLUMNS=${w[1]} _hop_mode=${w[2]}
		local h=$(_hop_vim_header ${w[3]} ${w[4]:-})
		print -r -- "${h//$'\n'/\\n}"
	done`, cases...)
	got := strings.Split(strings.TrimRight(out, "\n"), "\n")
	for i := range cases {
		if i >= len(got) || got[i] != want[i] {
			t.Errorf("%s:\n  zsh %q\n  go  %q", cases[i], at(got, i), want[i])
		}
	}
}

func at(s []string, i int) string {
	if i < len(s) {
		return s[i]
	}
	return "<missing>"
}

// zshBinds is _hop_vim_binds' args, prompt, header and exported actions for one picker shape.
func zshBinds(t *testing.T, enter string, cols int, reload, root, restore, query, drill, up, note, guard string) map[string]string {
	t.Helper()
	out := zsh(t, `local -a args
		local _hop_vim_prompt _hop_vim_head _hop_mode=$1
		local -x HOP_VIM_TO_NORMAL HOP_VIM_HELP_ON HOP_VIM_HELP_OFF HOP_VIM_TO_MENU HOP_VIM_PICK_KIND HOP_VIM_MENU_BACK
		COLUMNS=$2
		_hop_vim_binds "hop __preview {2} {3}" "$3" "$4" "$5" "$6" "$7" "$8" "${10}" "$9"
		print -rl -- "${(@)args//$'\n'/\\n}"
		print -r -- "PROMPT=$_hop_vim_prompt"
		print -r -- "HEAD=${_hop_vim_head//$'\n'/\\n}"
		print -r -- "TO_NORMAL=${HOP_VIM_TO_NORMAL//$'\n'/\\n}"
		print -r -- "TO_MENU=${HOP_VIM_TO_MENU//$'\n'/\\n}"
		print -r -- "HELP_ON=$HOP_VIM_HELP_ON"
		print -r -- "HELP_OFF=$HOP_VIM_HELP_OFF"`,
		enter, fmt.Sprint(cols), reload, root, restore, query, drill, up, note, guard)
	m := map[string]string{}
	var binds []string
	for _, l := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
		if k, v, ok := strings.Cut(l, "="); ok && slices.Contains([]string{"PROMPT", "HEAD", "TO_NORMAL", "TO_MENU", "HELP_ON", "HELP_OFF"}, k) {
			m[k] = normalize(v)
			continue
		}
		binds = append(binds, normalize(l))
	}
	m["BINDS"] = strings.Join(binds, "\n")
	return m
}

var (
	guardCheck = regexp.MustCompile(`^--bind=(.+?):transform:.*hop-guard check .*$`)
	guardMark  = regexp.MustCompile(`execute-silent\(\S*hop-guard mark /G/mark\)`)
	kindsMenu  = regexp.MustCompile(`reload\(\S*hop-kinds menu /R\)`)
	helpCmd    = regexp.MustCompile(`change-preview\(\S*hop-preview --keys [^)]*\)`)
)

// normalize maps zsh hop's helper scripts and shell transforms onto the hop __verb that does each one's job.
func normalize(l string) string {
	switch {
	case strings.HasPrefix(l, "--bind=esc:transform:"):
		return "--bind=esc:transform:hop __key esc"
	case strings.HasPrefix(l, "--bind=enter:transform:"):
		return "--bind=enter:transform:hop __key enter {2}"
	case strings.HasPrefix(l, "--bind=?:transform:"):
		return "--bind=?:transform:hop __key ?"
	case strings.HasPrefix(l, "--bind=c:transform:case ") && !strings.Contains(l, "hop-guard"):
		return "--bind=c:transform:hop __key c"
	}
	l = guardCheck.ReplaceAllString(l, "--bind=$1:transform:hop __guard check $1")
	l = guardMark.ReplaceAllString(l, "execute-silent(hop __guard mark)")
	l = kindsMenu.ReplaceAllString(l, "reload(hop __menu)")
	l = helpCmd.ReplaceAllString(l, "change-preview(hop __keys)")
	return strings.ReplaceAll(l, "reload(RESTORE)", "reload(hop __rows)")
}

// TestBindsLiveZsh holds every modal bind, both start modes and the actions esc and `?` hand back to _hop_vim_binds'.
// - `/` with a menu asks hop __key, so it is read as the action __key returns there.
func TestBindsLiveZsh(t *testing.T) {
	for _, c := range []struct {
		name  string
		m     Map
		query string
		note  string
	}{
		{"targets", Map{Enter: "cd", Menu: true, Restore: true, Reload: true, Up: true, Guard: true, Cols: 80}, "", ""},
		{"targets wide, open", Map{Enter: "open", Menu: true, Restore: true, Reload: true, Up: true, Guard: true, Cols: 200}, "", ""},
		{"targets search", Map{Enter: "cd", Menu: true, Restore: true, Reload: true, Up: true, Guard: true, Cols: 100}, "web", ""},
		{"targets note", Map{Enter: "cd+reveal", Menu: true, Restore: true, Reload: true, Up: true, Guard: true, Cols: 140}, "vpc zz", "ignored: zz"},
		{"workspaces", Map{Enter: "open", Drill: true, Guard: true, Cols: 80}, "", ""},
		{"repos", Map{Enter: "cd", Up: true, Guard: true, Cols: 80}, "", ""},
		{"unguarded", Map{Enter: "cd", Menu: true, Restore: true, Reload: true, Up: true, Cols: 80}, "", ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			arg := func(on bool, v string) string {
				if on {
					return v
				}
				return ""
			}
			z := zshBinds(t, c.m.Enter, c.m.Cols, arg(c.m.Reload, "RELOAD"), arg(c.m.Menu, "/R"), arg(c.m.Restore, "RESTORE"), c.query,
				arg(c.m.Drill, "drill"), arg(c.m.Up, "up"), c.note, arg(c.m.Guard, "/G/mark"))
			args, prompt, header := c.m.Binds(c.query, c.note)
			for i, a := range args {
				if c.m.Menu && a == "--bind=/:transform:hop __key /" {
					act, _ := c.m.Key("/", "", NormalPrompt, "", "", nil)
					args[i] = "--bind=/:" + act
				}
				args[i] = strings.ReplaceAll(args[i], "\n", `\n`)
			}
			if got := strings.Join(args, "\n"); got != z["BINDS"] {
				diff(t, z["BINDS"], got)
			}
			if prompt != z["PROMPT"] || strings.ReplaceAll(header, "\n", `\n`) != z["HEAD"] {
				t.Errorf("start: zsh %q %q, go %q %q", z["PROMPT"], z["HEAD"], prompt, header)
			}
			esc, _ := c.m.Key("esc", "", SearchPrompt, "x", "", nil)
			if strings.ReplaceAll(esc, "\n", `\n`) != z["TO_NORMAL"] {
				t.Errorf("esc in SEARCH:\n  zsh %q\n  go  %q", z["TO_NORMAL"], esc)
			}
			if c.m.Menu && c.m.ToMenu() != z["TO_MENU"] {
				t.Errorf(":\n  zsh %q\n  go  %q", z["TO_MENU"], c.m.ToMenu())
			}
			if on, _ := c.m.Key("?", "", NormalPrompt, "", "", nil); on != z["HELP_ON"] {
				t.Errorf("? opening:\n  zsh %q\n  go  %q", z["HELP_ON"], on)
			}
			if off, _ := c.m.Key("?", "", NormalPrompt, "", HelpLabel, nil); off != z["HELP_OFF"] {
				t.Errorf("? closing:\n  zsh %q\n  go  %q", z["HELP_OFF"], off)
			}
		})
	}
}

func diff(t *testing.T, want, got string) {
	t.Helper()
	w, g := strings.Split(want, "\n"), strings.Split(got, "\n")
	for i := range max(len(w), len(g)) {
		if at(w, i) != at(g, i) {
			t.Errorf("bind %d:\n  zsh %q\n  go  %q", i, at(w, i), at(g, i))
			return
		}
	}
}

// TestOverlayLiveZsh holds `?`'s overlay to bin/hop-preview --keys for each picker's live keys and Enter mode.
func TestOverlayLiveZsh(t *testing.T) {
	for _, live := range [][]string{{"r", ":", "h", "M-a"}, {"l"}, {"h"}, {"l", "h"}, nil, {"r", ":", "l", "h", "M-a"}} {
		for _, e := range enters {
			arg := strings.Join(live, ",")
			if arg == "" {
				arg = "-"
			}
			z := zsh(t, `"$HOP_HOME/bin/hop-preview" --keys "$1" "$2"`, arg, e)
			if g := Overlay(e, live); g != z {
				t.Errorf("%v %s:\nzsh:\n%s\ngo:\n%s", live, e, z, g)
			}
		}
	}
}

func TestKey(t *testing.T) {
	m := Map{Enter: "cd", Menu: true, Restore: true, Cols: 80}
	all := []string{"tg", "mod", "helm"}
	key := func(k, arg, prompt, query, label string) (string, []string) {
		return m.Key(k, arg, prompt, query, label, all)
	}
	for _, c := range []struct {
		k, arg, prompt, query, want string
	}{
		{"esc", "", NormalPrompt, "", "abort"},
		{"esc", "", NormalPrompt, "zz", "clear-query"},
		{"esc", "", SearchPrompt, "zz", m.ToNormal()},
		{"esc", "", MenuPrompt, "", m.View(false)},
		{"esc", "", MenuSearchPrompt, "he", m.MenuNormal()},
		{"enter", "/r/a", NormalPrompt, "", "accept"},
		{"enter", "/r/a", SearchPrompt, "x", "accept"},
		{"enter", "nope", MenuPrompt, "", "ignore"},
		{"alt-enter", "", NormalPrompt, "", "print(alt-enter)+accept"},
		{"alt-enter", "", MenuPrompt, "", "ignore"},
		{"c", "", MenuSearchPrompt, "", "ignore"},
		{"/", "", NormalPrompt, "", m.ToSearch()},
		{"/", "", MenuPrompt, "", m.MenuSearch()},
		{"bogus", "", NormalPrompt, "", "ignore"},
	} {
		if got, view := key(c.k, c.arg, c.prompt, c.query, ""); got != c.want || view != nil {
			t.Errorf("%s at %q query %q: %q %v, want %q", c.k, c.prompt, c.query, got, view, c.want)
		}
	}
	if got, view := key("enter", "helm", MenuPrompt, "", ""); got != m.View(false) || !slices.Equal(view, []string{"helm"}) {
		t.Errorf("enter on a menu row switches to that kind: %q %v", got, view)
	}
	if got, view := key("enter", "helm", MenuSearchPrompt, "he", ""); !strings.HasPrefix(got, RebindAll+"+clear-query+reload(hop __rows)") || view[0] != "helm" {
		t.Errorf("enter from the menu's search rebinds NORMAL too: %q", got)
	}
	if !strings.HasPrefix(m.View(false), "clear-query+reload(hop __rows)+change-prompt(> )+change-header(NORMAL") || !strings.HasSuffix(m.View(false), "+first") {
		t.Errorf("leaving the menu reloads the current view under NORMAL: %q", m.View(false))
	}
}

func TestVerbs(t *testing.T) {
	m := Map{Enter: "cd"}
	for k, want := range map[string]string{
		"o": "print(ctrl-o)+accept", "O": "print(ctrl-t)+accept", "e": "print(alt-o)+accept", "y": "print(ctrl-y)+accept",
		"Y": "print(alt-y)+accept", "b": "print(ctrl-g)+accept", "c": "print(alt-enter)+accept", "q": "abort", "p": "toggle-preview",
		"r": "", "l": "", "h": "", ":": "", "x": "", "space": "",
	} {
		if got := m.Verb(k); got != want {
			t.Errorf("Verb(%s) = %q, want %q", k, got, want)
		}
	}
	if len(Keys) != 26+26+10+1+30+2 {
		t.Errorf("%d NORMAL keys", len(Keys))
	}
	if slices.Contains(Keys, "(") || slices.Contains(Keys, ")") || slices.Contains(Keys, "esc") || slices.Contains(Keys, "enter") {
		t.Error("( ) esc and enter are bound on their own, never in the bulk list")
	}
}
