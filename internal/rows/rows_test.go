package rows

import (
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
)

var update = flag.Bool("update", false, "rewrite testdata/golden/row.golden from zsh hop's _hop_row")

// cases are _hop_row argument lists: kind scope env region name dir preview [f].
var cases = [][]string{
	{"tg", "acct-a", "prod", "us-east-1", "vpc", "/r/infra/vpc", "/r/infra/vpc/main.tf"},
	{"tg", "observability-platform-shared", "staging", "us-west-2", "eks", "/r/infra/eks", ""},
	{"helm", "kubernetes/services", "-", "-", "grp/app", "/r/kubernetes/services/grp", "/r/kubernetes/services/grp/app.yaml", "f"},
	{"mesos", "", "", "", "", "/r/mesos/x", "/r/mesos/x/service.conf"},
	{"backstage", "b", "dev", "eu", "a-name-that-is-longer-than-twenty-eight", "/r/b", "/r/b/x.yaml", "f"},
	{"dir", "-", "-", "-", "<root>", "/r", "/r/README.md"},
	{"x", "café-scope-with-accents-é", "playground-long", "r", "café", "/r/café", "/r/café"},
	{"ws", "~/src", "3 repos", "-", "src", "/elsewhere/src", "/elsewhere/src"},
	{"repo", "-", "-", "-", "hop", "@HOME@/code/hop", "@HOME@/code/hop/README.md"},
	{"repo", "-", "-", "-", "home", "@HOME@", "@HOME@"},
}

func renderCase(c []string, root string) string {
	r := New(c[0], c[1], c[2], c[3], c[4], c[5], c[6], len(c) > 7)
	return Render(r, root)
}

func expandHome(c []string) []string {
	out := make([]string, len(c))
	for i, s := range c {
		out[i] = strings.ReplaceAll(s, "@HOME@", os.Getenv("HOME"))
	}
	return out
}

func zshRows(t *testing.T) string {
	t.Helper()
	script := `local _hop_gen_root=$1; shift
local -a c
for line in "$@"; do
	c=("${(@ps:\x1f:)line}")
	_hop_row "${c[@]}"
done`
	args := []string{"/r"}
	for _, c := range cases {
		args = append(args, strings.Join(expandHome(c), "\x1f"))
	}
	out, err := testfix.Zsh("/dev/null", script, nil, args...)
	if err != nil {
		t.Fatal(err)
	}
	return strings.ReplaceAll(out, os.Getenv("HOME"), "@HOME@")
}

func goRows() string {
	var b strings.Builder
	for _, c := range cases {
		b.WriteString(renderCase(expandHome(c), "/r") + "\n")
	}
	return strings.ReplaceAll(b.String(), os.Getenv("HOME"), "@HOME@")
}

func TestRenderGolden(t *testing.T) {
	golden := filepath.Join(testfix.ModuleRoot(), "testdata", "golden", "row.golden")
	if *update {
		os.WriteFile(golden, []byte(zshRows(t)), 0o644)
	}
	want, err := os.ReadFile(golden)
	if err != nil {
		t.Fatal(err)
	}
	got := goRows()
	gl, wl := strings.Split(got, "\n"), strings.Split(string(want), "\n")
	for i := range max(len(gl), len(wl)) {
		var g, w string
		if i < len(gl) {
			g = gl[i]
		}
		if i < len(wl) {
			w = wl[i]
		}
		if g != w {
			t.Errorf("row %d\n got  %q\n want %q", i, g, w)
		}
	}
}

// TestRenderLiveZsh holds each row, laid out on its own, to the reference hop's _hop_row, which fits a lone row to itself.
func TestRenderLiveZsh(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skipf("zsh or hop %s not available", testfix.RefLayout)
	}
	var b strings.Builder
	for _, c := range cases {
		c = expandHome(c)
		b.WriteString(List([]Row{New(c[0], c[1], c[2], c[3], c[4], c[5], c[6], len(c) > 7)}, "/r", nil)[0] + "\n")
	}
	if got, want := strings.ReplaceAll(b.String(), os.Getenv("HOME"), "@HOME@"), zshRows(t); got != want {
		t.Errorf("go and _hop_row differ\n got  %q\n want %q", got, want)
	}
}

func TestFit(t *testing.T) {
	cases := []struct {
		s    string
		w    int
		tail bool
		want string
	}{
		{"short", 9, false, "short"},
		{"exactly-9", 9, false, "exactly-9"},
		{"playground", 9, false, "playgrou…"},
		{"kubernetes/services/grp", 22, true, "…bernetes/services/grp"},
		{"café-très-long-scope-name", 10, true, "…cope-name"},
		{"ééééééé", 5, false, "éééé…"},
	}
	for _, c := range cases {
		if got := Fit(c.s, c.w, c.tail); got != c.want {
			t.Errorf("Fit(%q, %d, %v) = %q, want %q", c.s, c.w, c.tail, got, c.want)
		}
	}
}

func TestRel(t *testing.T) {
	t.Setenv("HOME", "/home/u")
	cases := []struct {
		r    Row
		root string
		want string
	}{
		{New("k", "", "", "", "n", "/r", "", false), "/r", "./"},
		{New("k", "", "", "", "n", "/r/a", "", false), "/r", "a/"},
		{New("k", "", "", "", "n", "/r/a", "/r/a/f.txt", true), "/r", "a/f.txt"},
		{New("k", "", "", "", "n", "/rx/a", "", false), "/r", "/rx/a/"},
		{New("k", "", "", "", "n", "/home/u/src", "", false), "", "~/src/"},
		{New("k", "", "", "", "n", "/home/u", "", false), "", "~/"},
		{New("k", "", "", "", "n", "/home/uu", "", false), "", "/home/uu/"},
	}
	for _, c := range cases {
		if got := Rel(c.r, c.root); got != c.want {
			t.Errorf("Rel(%v, %q) = %q, want %q", c.r, c.root, got, c.want)
		}
	}
}

func TestSplitAndStrip(t *testing.T) {
	line := Render(New("tg", "s", "prod", "-", "vpc", "/r/v", "", false), "/r")
	f := Split(line)
	if len(f) != 4 || f[1] != "/r/v" || f[2] != "/r/v" || StripANSI(f[3]) != "v/" {
		t.Errorf("Split = %q", f)
	}
	if got := Split("a\t\tc"); len(got) != 4 || got[1] != "" || got[3] != "" {
		t.Errorf("Split must keep empty fields and pad a legacy row: %q", got)
	}
	if got := StripANSI("\x1b[1;36mx\x1b[0m y\x1b[2m"); got != "x y" {
		t.Errorf("StripANSI = %q", got)
	}
}

func TestSetEnvColors(t *testing.T) {
	t.Cleanup(func() { SetEnvColors(map[string][]string{"prod": {"prod"}, "staging": {"staging"}, "dev": {"dev"}}) })
	if envColour("playground") != "\x1b[35m" || envColour("dev") != "\x1b[34m" || envColour("-") != CDim {
		t.Error("by default only prod, staging and dev have a colour of their own")
	}
	SetEnvColors(map[string][]string{"prod": {"prod", "live"}, "dev": {"dev", "playground"}})
	for env, want := range map[string]string{"live": "\x1b[31m", "playground": "\x1b[34m", "staging": "\x1b[35m", "qa": "\x1b[35m"} {
		if got := envColour(env); got != want {
			t.Errorf("%s = %q, want %q", env, got, want)
		}
	}
}
