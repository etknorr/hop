package keymap

import (
	"slices"
	"strings"
)

const (
	hdr  = "\x1b[1;36m"
	sub  = "\x1b[2m"
	key  = "\x1b[1;33m"
	off  = "\x1b[0m"
	rule = "──────────────────────────────────────────"
)

var enterSays = map[string]string{
	"cd":        "cd to the dir",
	"open":      "open in VS Code",
	"reveal":    "reveal in the VS Code explorer",
	"cd+open":   "cd, then open in VS Code",
	"cd+reveal": "cd, then reveal in VS Code",
}

func k(s string) string { return key + s + off }

// Overlay is `hop __keys`, bin/hop-preview --keys: both modes at once, since "what does this key do" is usually about the other one.
// - live is the optional keys the picker bound (r, :, l, h, M-a); one bound to ignore must not be taught.
// - It stays under 50 columns, so a narrow preview pane doesn't wrap it.
func Overlay(enter string, live []string) string {
	says, ok := enterSays[enter]
	if !ok {
		enter, says = "cd", enterSays["cd"]
	}
	has := func(s string) bool { return slices.Contains(live, s) }
	var b []string
	add := func(l ...string) { b = append(b, l...) }
	add(hdr+"hop keys"+off, sub+rule+off, hdr+"NORMAL"+off+sub+"  (letters are verbs)"+off,
		"  "+k("j")+" / "+k("k")+"          down / up",
		"  "+k("g")+" / "+k("G")+"          first / last row",
		"  "+k("^d")+" / "+k("^u")+"        half page down / up",
		"  "+k("enter")+"          "+says)
	if enter != "cd" {
		add("  " + k("c") + "              cd to the dir")
	}
	add("  "+k("o")+"              code -r the preview file",
		"  "+k("O")+"              code -n the dir as a folder",
		"  "+k("e")+"              $EDITOR the preview file",
		"  "+k("y")+" / "+k("Y")+"          copy dir / preview file",
		"  "+k("b")+"              gh browse")
	switch {
	case has("l") && has("h"):
		add("  " + k("l") + " / " + k("h") + "          drill in / back out a level")
	case has("l"):
		add("  " + k("l") + "              drill in a level")
	case has("h"):
		add("  " + k("h") + "              back out a level")
	}
	add("  " + k("p") + "              toggle the preview pane")
	if has("r") {
		add("  " + k("r") + "              refresh the current view")
	}
	add("  " + k("/") + "              switch to SEARCH")
	if has(":") {
		add("  " + k(":") + "              switch view, enter picks, esc back")
	}
	add("  "+k("?")+"              this help",
		"  "+k("esc")+"            clear the query, else quit",
		"  "+k("q")+"              quit",
		"",
		hdr+"SEARCH"+off+sub+"  (every key types)"+off,
		"  "+k("esc")+"            back to NORMAL, keeps query",
		"  "+k("enter")+"          "+says)
	if enter != "cd" {
		add("  " + k("M-enter") + "        cd to the dir")
	}
	add("  "+k("^o")+" / "+k("^t")+"        code file / code dir",
		"  "+k("^y")+" / "+k("M-y")+"       copy dir / preview file",
		"  "+k("M-o")+"            $EDITOR the preview file",
		"  "+k("M-B")+"            gh browse")
	if has("M-a") {
		add("  " + k("M-a") + "            reload with every kind")
	}
	add("  "+k("M-p")+"            toggle the preview pane",
		"",
		sub+"HOP_VIM=0 or --no-vim turns the modal layer off."+off)
	return strings.Join(b, "\n") + "\n"
}
