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
