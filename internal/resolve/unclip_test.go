package resolve

import (
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/rows"
	"github.com/etknorr/hop/internal/testfix"
)

// unclipRows are laid-out rows, coloured as fzf returns them under --ansi, with what _hop_unclip should make of each.
func unclipRows() []struct{ row, want string } {
	w := rows.Widths{14, 4, 8, 4, 0}
	mk := func(name, scope, dir, preview string, file bool) string {
		return rows.List([]rows.Row{rows.New("helm", scope, "prod", "-", name, dir, preview, file)}, "/r", &w)[0]
	}
	return []struct{ row, want string }{
		{mk("monitoring/service-prometheus-rules", "-", "/r/k/monitoring", "/r/k/monitoring/service-prometheus-rules.yaml", true), "monitoring/service-prometheus-rules"},
		{mk("api-server-demo-safe-to-delete", "-", "/r/t/env-prod/api-server-demo-safe-to-delete", "", false), "api-server-demo-safe-to-delete"},
		{mk("name-read-from-a-file-elsewhere", "-", "/r/t/other", "", false), ""},
		{mk("short", "-", "/r/t/short", "", false), ""},
		{mk("clipped-name-and-scope", "a-long-scope-name", "/r/t/clipped-name-and-scope", "", false), ""},
		// The whole rel is tried before its last segments, so here the name comes back as the rel, as hop's pattern does.
		{mk("ab-cd-ef-gh-ij-kl", "-", "/r/ab-cd-ef/ab-cd-ef-gh-ij-kl", "", false), "ab-cd-ef/ab-cd-ef-gh-ij-kl"},
		{mk("éééééééé-ééééééééé", "-", "/r/x/éééééééé-ééééééééé", "", false), "éééééééé-ééééééééé"},
		{"abcdef…uvwxyz\t/r/d\t/r/d\t\x1b[2mq/abcdefMuvwxyz/\x1b[0m", "abcdefMuvwxyz"},
	}
}

func unclipGot(row string) string {
	u, ok := unclip(row)
	if !ok {
		return ""
	}
	if f := strings.Split(u, "\t"); len(f) != 4 || f[1:][0] != strings.Split(row, "\t")[1] {
		return "fields changed: " + u
	}
	name, _, _ := strings.Cut(strings.Split(u, "\t")[0], " ")
	return name
}

func TestUnclip(t *testing.T) {
	t.Setenv("HOP_LAYOUT", "")
	for _, c := range unclipRows() {
		if got := unclipGot(c.row); got != c.want {
			t.Errorf("unclip(%q) = %q, want %q", c.row, got, c.want)
		}
	}
}

func TestUnclipLiveZsh03(t *testing.T) {
	t.Setenv("HOP_LAYOUT", "")
	home := testfix.RefHome(testfix.RefLayout)
	if home == "" || !testfix.HaveZsh() {
		t.Skipf("zsh or hop %s not available", testfix.RefLayout)
	}
	cs := unclipRows()
	args := make([]string, len(cs))
	for i, c := range cs {
		args[i] = c.row
	}
	out, err := testfix.ZshAt(home, "/dev/null", `local r
for r in "$@"; do
	if _hop_unclip "$r"; then print -r -- "1${REPLY//$'\n'/\n}"; else print -r -- 0; fi
done`, nil, args...)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSuffix(out, "\n"), "\n")
	if len(lines) != len(cs) {
		t.Fatalf("zsh printed %d lines for %d rows", len(lines), len(cs))
	}
	for i, c := range cs {
		want := ""
		if lines[i] != "0" {
			want = strings.TrimPrefix(lines[i], "1")
		}
		got, _ := unclip(c.row)
		if got != want {
			t.Errorf("row %d %q\n go  %q\n zsh %q", i, c.row, got, want)
		}
	}
}
