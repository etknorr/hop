package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/etknorr/hop/internal/keymap"
	"github.com/etknorr/hop/internal/pick"
)

func TestKeyCallback(t *testing.T) {
	setup(t)
	keys := keymap.Map{Enter: "cd", Menu: true, Restore: true, Guard: true, Cols: 80}
	withSession(t, &pick.Session{Kinds: []string{"tg"}, All: []string{"tg", "helm"}, Keys: keys})
	t.Setenv("FZF_PROMPT", keymap.NormalPrompt)
	t.Setenv("FZF_QUERY", "")
	if o, _, rc := runHop(t, "__key", "esc"); rc != 0 || o != "abort" {
		t.Errorf("esc on an empty NORMAL query quits: rc %d %q", rc, o)
	}
	t.Setenv("FZF_QUERY", "zz")
	if o, _, _ := runHop(t, "__key", "esc"); o != "clear-query" {
		t.Errorf("esc on a NORMAL query clears it: %q", o)
	}
	t.Setenv("FZF_PROMPT", keymap.SearchPrompt)
	if o, _, _ := runHop(t, "__key", "esc"); o != keys.ToNormal() {
		t.Errorf("esc in SEARCH goes to NORMAL keeping the query: %q", o)
	}
	t.Setenv("FZF_PROMPT", keymap.MenuPrompt)
	if o, _, rc := runHop(t, "__sh", `hop __key enter 'helm'`); rc != 0 || o != keys.View(false) {
		t.Errorf("__sh dispatches enter on a menu row in process: rc %d %q", rc, o)
	}
	s, _ := pick.Load()
	if strings.Join(s.Current(), " ") != "helm" {
		t.Errorf("switching kinds makes it the current view for r and the next esc: %v", s.Current())
	}
	if o, _, _ := runHop(t, "__key", "enter", "nope"); o != "ignore" {
		t.Errorf("enter on something not a kind: %q", o)
	}
	if o, _, _ := runHop(t, "__key", "esc"); o != keys.View(false) {
		t.Errorf("esc in the menu goes back to the view: %q", o)
	}
	t.Setenv("FZF_PREVIEW_LABEL", "")
	if o, _, _ := runHop(t, "__key", "?"); !strings.Contains(o, "change-preview(hop __keys)+change-preview-label( keys )") {
		t.Errorf("? opens the overlay: %q", o)
	}
	t.Setenv("SHELL", "/bin/sh")
	if _, _, rc := runHop(t, "__sh", "exit 5"); rc != 5 {
		t.Errorf("__sh passes a foreign command's status through: rc %d", rc)
	}
	if o, _, rc := runHop(t, "__keys"); rc != 0 || !strings.Contains(o, "switch view, enter picks, esc back") || !strings.Contains(o, "refresh the current view") ||
		strings.Contains(o, "drill in") {
		t.Errorf("__keys names this picker's live keys only: rc %d\n%s", rc, o)
	}
	t.Setenv("HOP_SESSION", "")
	if _, e, rc := runHop(t, "__key", "esc"); rc != 2 || !strings.Contains(e, "HOP_SESSION") {
		t.Errorf("__key outside a picker: rc %d %q", rc, e)
	}
}

func TestGuardCallback(t *testing.T) {
	setup(t)
	withSession(t, &pick.Session{Kinds: []string{"tg"}, All: []string{"tg"}, Keys: keymap.Map{Enter: "cd", Menu: true, Restore: true, Guard: true, Cols: 80}})
	mark := filepath.Join(filepath.Dir(os.Getenv("HOP_SESSION")), "mark")
	t.Setenv("FZF_PROMPT", keymap.NormalPrompt)
	if o, _, _ := runHop(t, "__guard", "check", "b"); o != "print(ctrl-g)+accept" {
		t.Errorf("with no mark, b browses: %q", o)
	}
	if _, _, rc := runHop(t, "__sh", "hop __guard mark"); rc != 0 {
		t.Fatal("mark failed")
	}
	if b, err := os.ReadFile(mark); err != nil || len(b) == 0 {
		t.Fatalf("the mark lives in the session's private directory: %v", err)
	}
	if o, _, _ := runHop(t, "__guard", "check", "b"); o != "ignore" {
		t.Errorf("b right after an unparsed escape is refused: %q", o)
	}
	old := strconv.FormatFloat(float64(time.Now().Add(-time.Second).UnixMicro())/1e6, 'f', 6, 64)
	os.WriteFile(mark, []byte(old), 0o600)
	if o, _, _ := runHop(t, "__guard", "check", "o"); o != "print(ctrl-o)+accept" {
		t.Errorf("a second after the mark, o opens: %q", o)
	}
	runHop(t, "__guard", "mark")
	t.Setenv("HOP_GUARD_WINDOW", "0")
	if o, _, _ := runHop(t, "__guard", "check", "q"); o != "abort" {
		t.Errorf("HOP_GUARD_WINDOW=0 turns the guard off: %q", o)
	}
	t.Setenv("HOP_GUARD_WINDOW", "")
	if o, _, _ := runHop(t, "__guard", "check", "l"); o != "ignore" {
		t.Errorf("l has no drill here, so it stays ignore: %q", o)
	}
	t.Setenv("FZF_PROMPT", keymap.MenuPrompt)
	os.Remove(mark)
	if o, _, _ := runHop(t, "__guard", "check", "c"); o != "ignore" {
		t.Errorf("c on a menu row does nothing: %q", o)
	}
	for _, args := range [][]string{{"check", "j"}, {"check"}, {"bogus"}, {}} {
		if o, e, rc := runHop(t, append([]string{"__guard"}, args...)...); rc != 0 || o != "" || e != "" {
			t.Errorf("__guard %v is silent and succeeds, since fzf shows a failed bind as a dead key: rc %d %q %q", args, rc, o, e)
		}
	}
}

func TestHopw(t *testing.T) {
	setup(t)
	d := t.TempDir()
	outer, inner := filepath.Join(d, "work"), filepath.Join(d, "work", "code")
	deep := filepath.Join(inner, "repo", "sub")
	os.MkdirAll(deep, 0o755)
	t.Setenv("HOP_WORKSPACES", outer+":"+inner)
	cf := filepath.Join(t.TempDir(), "cmd")
	t.Setenv("HOP_CMDFILE", cf)
	t.Chdir(deep)
	t.Setenv("PWD", deep)
	if _, e, rc := runHop(t, "__hopw"); rc != 0 {
		t.Fatalf("rc %d %s", rc, e)
	}
	real, _ := filepath.EvalSymlinks(inner)
	if b, _ := os.ReadFile(cf); string(b) != real {
		t.Errorf("hopw takes the longest workspace holding PWD: %q, want %q", b, real)
	}
	t.Chdir(d)
	t.Setenv("PWD", d)
	if _, e, rc := runHop(t, "__hopw"); rc != 1 || e != "hop: "+d+" is not inside any configured workspace\n" {
		t.Errorf("outside every workspace: rc %d %q", rc, e)
	}
}
