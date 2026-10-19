package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/match"
	"github.com/etknorr/hop/internal/mru"
	"github.com/etknorr/hop/internal/pick"
)

func withSession(t *testing.T, s *pick.Session) {
	t.Helper()
	dir, p, err := s.Write()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	t.Setenv("HOP_SESSION", p)
}

func TestRowsCallback(t *testing.T) {
	root := setup(t)
	plain, _, _ := runHop(t, "__rows", root, "svc", "dir")
	lines := match.Lines(plain)
	hist := os.Getenv("HOP_HISTFILE")
	pinned := strings.Split(lines[len(lines)-1], "\t")[1]
	os.WriteFile(hist, []byte(pinned+"\n"), 0o644)

	withSession(t, &pick.Session{Root: root, Kinds: []string{"svc", "dir"}})
	got, _, rc := runHop(t, "__rows")
	want := strings.Join(mru.Rank(lines, []string{pinned}), "\n") + "\n"
	if rc != 0 || got != want {
		t.Errorf("__rows in a picker is hop rows plus rank: rc %d\n%s\nwant\n%s", rc, got, want)
	}
	if !strings.HasPrefix(got, lines[len(lines)-1]) {
		t.Error("the remembered row comes first")
	}
	if again, _, _ := runHop(t, "__rows", "svc", "dir"); again != got {
		t.Error("kinds named on the command line override the session's")
	}
	if plain2, _, _ := runHop(t, "__rows", root, "svc", "dir"); plain2 != plain {
		t.Error("the absolute-root form stays unranked inside a picker")
	}

	under := filepath.Join(root, "svc")
	withSession(t, &pick.Session{Root: root, Under: under, Kinds: []string{"svc", "dir"}})
	got, _, _ = runHop(t, "__rows")
	for _, l := range match.Lines(got) {
		if d := strings.Split(l, "\t")[1]; d != under && !strings.HasPrefix(d, under+"/") {
			t.Errorf("-c keeps only rows under %s: %s", under, d)
		}
	}
	if len(match.Lines(got)) == 0 || len(match.Lines(got)) >= len(lines) {
		t.Errorf("-c narrowed %d rows to %d", len(lines), len(match.Lines(got)))
	}
}

func TestMenuCallback(t *testing.T) {
	root := setup(t)
	withSession(t, &pick.Session{Root: root, Kinds: []string{"tg"}})
	out, _, rc := runHop(t, "__menu")
	if rc != 0 {
		t.Fatalf("rc %d", rc)
	}
	n := map[string]int{}
	for _, k := range []string{"svc", "dir", "tg"} {
		rs, _, _ := runHop(t, "__rows", root, k)
		n[k] = len(match.Lines(rs))
	}
	for _, l := range match.Lines(out) {
		f := strings.Split(l, "\t")
		if len(f) != 3 || f[2] != root {
			t.Fatalf("menu row shape: %q", l)
		}
		if want, ok := n[f[1]]; ok && !strings.Contains(f[0], strings.Repeat(" ", 8-len(itoa(want)))+itoa(want)) {
			t.Errorf("%s: count %q, want %d", f[1], f[0], want)
		}
		delete(n, f[1])
	}
	if len(n) != 0 {
		t.Errorf("kinds missing from the menu: %v", n)
	}
}

func itoa(n int) string {
	var b []byte
	for {
		b = append([]byte{byte('0' + n%10)}, b...)
		if n /= 10; n == 0 {
			return string(b)
		}
	}
}

func TestKeyHeaderAndShim(t *testing.T) {
	setup(t)
	withSession(t, &pick.Session{Kinds: []string{"tg"}, All: []string{"tg", "helm"}, Header: "note\nlegend"})
	if o, _, rc := runHop(t, "__header"); rc != 0 || o != "note\nlegend" {
		t.Errorf("__header: %q", o)
	}
	t.Setenv("FZF_PROMPT", pick.MenuPrompt)
	if o, _, _ := runHop(t, "__key", "enter", "helm"); !strings.Contains(o, "reload(hop __rows helm)") {
		t.Errorf("__key enter in the menu: %q", o)
	}
	if o, _, rc := runHop(t, "__sh", `hop __key enter 'helm'`); rc != 0 || !strings.Contains(o, "reload(hop __rows helm)") {
		t.Errorf("__sh dispatches hop callbacks in process: rc %d %q", rc, o)
	}
	t.Setenv("SHELL", "/bin/sh")
	if _, _, rc := runHop(t, "__sh", "exit 5"); rc != 5 {
		t.Errorf("__sh passes a foreign command's status through: rc %d", rc)
	}
	t.Setenv("HOP_SESSION", "")
	if _, e, rc := runHop(t, "__key", "esc"); rc != 1 || !strings.Contains(e, "HOP_SESSION") {
		t.Errorf("__key outside a picker: rc %d %q", rc, e)
	}
}
