package mru

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
)

func row(name, dir string) string { return name + "\t" + dir + "\t" + dir + "\t" + name + "/" }

func names(rs []string) string {
	var out []string
	for _, r := range rs {
		n, _, _ := strings.Cut(r, "\t")
		out = append(out, n)
	}
	return strings.Join(out, " ")
}

func TestRank(t *testing.T) {
	rs := []string{row("a", "/r/a"), row("b", "/r/b"), row("c", "/r/c"), row("b2", "/r/b"), row("d", "/r/d")}
	for _, tc := range []struct {
		name string
		hist []string
		want string
	}{
		{"no history", nil, "a b c b2 d"},
		{"history naming no row", []string{"/gone", "/elsewhere"}, "a b c b2 d"},
		{"rank order, rest in input order", []string{"/r/c", "/r/a"}, "c a b b2 d"},
		{"two rows sharing a dir keep their input order", []string{"/r/b"}, "b b2 a c d"},
		{"a repeated entry keeps its first rank", []string{"/r/d", "/r/b", "/r/d"}, "d b b2 a c"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := names(Rank(rs, tc.hist)); got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestRemember(t *testing.T) {
	d := t.TempDir()
	live := []string{}
	for i := range 5 {
		p := filepath.Join(d, fmt.Sprintf("d%d", i))
		os.Mkdir(p, 0o755)
		live = append(live, p)
	}
	hist := filepath.Join(d, "state", "hist")
	os.MkdirAll(filepath.Dir(hist), 0o755)
	os.WriteFile(hist, []byte(strings.Join([]string{live[1], "", "relative/x", filepath.Join(d, "dead"), live[0], live[2]}, "\n")+"\n"), 0o644)

	Remember(hist, live[0], 300)
	if got, want := Load(hist), []string{live[0], live[1], live[2]}; !slices.Equal(got, want) {
		t.Errorf("dedupe, absolute and live only:\n got %v\nwant %v", got, want)
	}
	Remember(hist, live[3], 2)
	if got, want := Load(hist), []string{live[3], live[0]}; !slices.Equal(got, want) {
		t.Errorf("the cap:\n got %v\nwant %v", got, want)
	}
	Remember(filepath.Join(d, "new", "deeper", "hist"), live[4], 300)
	if got := Load(filepath.Join(d, "new", "deeper", "hist")); !slices.Equal(got, []string{live[4]}) {
		t.Errorf("a missing parent is created: %v", got)
	}
	Remember("", live[0], 300)
	Remember(hist, "", 300)
	if got := Load(hist); len(got) != 2 {
		t.Errorf("an empty path or dir is a no-op: %v", got)
	}
	if ents, _ := os.ReadDir(filepath.Dir(hist)); len(ents) != 1 {
		t.Errorf("a temp file was left behind: %v", ents)
	}
}

// TestRememberAtomic reads the file while writers rewrite it, and every read must be a whole history.
func TestRememberAtomic(t *testing.T) {
	d := t.TempDir()
	var dirs []string
	for i := range 40 {
		p := filepath.Join(d, fmt.Sprintf("dir-with-a-long-name-%03d", i))
		os.Mkdir(p, 0o755)
		dirs = append(dirs, p)
	}
	hist := filepath.Join(d, "hist")
	for _, p := range dirs {
		Remember(hist, p, 300)
	}
	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Go(func() {
		for i := 0; ; i++ {
			select {
			case <-stop:
				return
			default:
				Remember(hist, dirs[i%len(dirs)], 300)
			}
		}
	})
	for range 2000 {
		b, err := os.ReadFile(hist)
		if err != nil {
			t.Fatal(err)
		}
		if n := strings.Count(string(b), "\n"); n != len(dirs) || !strings.HasSuffix(string(b), "\n") {
			t.Fatalf("a reader saw a partial history: %d lines", n)
		}
	}
	close(stop)
	wg.Wait()
}

// TestRankAgainstZsh runs hop's own _hop_rank over the same rows and history.
func TestRankAgainstZsh(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skip("zsh not available")
	}
	var rs, hist []string
	for i := range 60 {
		rs = append(rs, row(fmt.Sprintf("n%02d", i), fmt.Sprintf("/r/d%d", i%23)))
	}
	for _, i := range []int{7, 3, 7, 22, 40, 0, 15} {
		hist = append(hist, fmt.Sprintf("/r/d%d", i))
	}
	d := t.TempDir()
	hf := filepath.Join(d, "hist")
	os.WriteFile(hf, []byte(strings.Join(hist, "\n")+"\n"), 0o644)
	rf := filepath.Join(d, "rows")
	os.WriteFile(rf, []byte(strings.Join(rs, "\n")), 0o644)
	out, err := testfix.Zsh("/nonexistent", `_hop_rank "$(<"$1")"`, []string{"HOP_HISTFILE=" + hf}, rf)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := strings.Join(Rank(rs, Load(hf)), "\n")+"\n", out; got != want {
		t.Errorf("go:\n%s\nzsh:\n%s", names(Rank(rs, Load(hf))), names(strings.Split(out, "\n")))
	}
}
