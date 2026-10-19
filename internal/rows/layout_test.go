package rows

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
)

// lists are _hop_row_raw argument lists, one list per entry, each laid out on its own.
// - The last list is laid out like the first one's first row, as _hop_row_like makes the resolver's ancestor rows.
func layoutLists() [][][]string {
	var fit [][]string
	for i := range 40 {
		n := fmt.Sprintf("svc-%02d-%s", i, strings.Repeat("x", 6+i%17))
		if i == 13 {
			n += "-" + strings.Repeat("long", 12) + fmt.Sprint(i)
		}
		fit = append(fit, []string{"helm", "kubernetes/services/platform-observability", "-", "-", n, "/r/k/" + n, "/r/k/" + n + ".yaml", "f"})
	}
	var capped [][]string
	for i := range 4 {
		n := strings.Repeat("n", 70) + fmt.Sprint(i)
		capped = append(capped, []string{"tg", "s", "prod", "-", n, "/r/c/" + n, ""})
	}
	return [][][]string{
		cases,
		fit,
		capped,
		{
			{"repo", "-", "-", "-", "hop", "/r/hop", "/r/hop/README.md"},
			{"repo", "-", "-", "-", "platform-configuration.retired-2026-09-14", "/r/pc", "/r/pc"},
		},
		{
			{"ws", "~/src", "3 repos", "-", "src", "/w/src", "/w/src"},
			{"d", "sc\x1fope", "dev", "eu-central-1-extra-long", "ééééé-ééééé-ééééé-ééééé-ééééé-ééééé-é", "/r/e", ""},
		},
		{
			{"dir", "terraform", "-", "-", "acct-security-tooling-prod-and-then-some", "/r/terraform/acct", "/r/terraform/acct"},
			{"dir", "-", "-", "-", "terraform", "/r/terraform", "/r/terraform"},
		},
	}
}

func hopxLayout() string {
	var b strings.Builder
	lists := layoutLists()
	var first string
	for i, l := range lists {
		var rs []Row
		for _, c := range l {
			c = expandHome(c)
			rs = append(rs, New(c[0], c[1], c[2], c[3], c[4], c[5], c[6], len(c) > 7))
		}
		var like *Widths
		if i == len(lists)-1 {
			w, ok := ParseWidths(first)
			if !ok {
				panic("ParseWidths failed on a laid-out row")
			}
			like = &w
		}
		out := List(rs, "/r", like)
		if i == 0 {
			first = out[0]
		}
		for _, r := range out {
			b.WriteString(r + "\n")
		}
	}
	return strings.ReplaceAll(b.String(), os.Getenv("HOME"), "@HOME@")
}

func zshLayout(t *testing.T, home string) string {
	t.Helper()
	script := `local _hop_gen_root=$1 n=$2; shift 2
local -a raw c
local list r first='' like
local -i i=0
for list in "$@"; do
	(( i++ ))
	raw=()
	for r in "${(@ps:\x1d:)list}"; do
		c=("${(@ps:\x1e:)r}")
		_hop_row_raw "${c[@]}"
		raw+=("$REPLY")
	done
	like=''
	(( i == n )) && like=$first
	_hop_layout "${(F)raw}" "$like"
	(( i == 1 )) && first=${REPLY%%$'\n'*}
	print -r -- "$REPLY"
done`
	lists := layoutLists()
	args := []string{"/r", fmt.Sprint(len(lists))}
	for _, l := range lists {
		var rs []string
		for _, c := range l {
			rs = append(rs, strings.Join(expandHome(c), "\x1e"))
		}
		args = append(args, strings.Join(rs, "\x1d"))
	}
	out, err := testfix.ZshAt(home, "/dev/null", script, nil, args...)
	if err != nil {
		t.Fatal(err)
	}
	return strings.ReplaceAll(out, os.Getenv("HOME"), "@HOME@")
}

func TestListLiveZsh03(t *testing.T) {
	t.Setenv("HOPX_LAYOUT", "")
	home := testfix.RefHome(testfix.RefLayout)
	if home == "" || !testfix.HaveZsh() {
		t.Skipf("zsh or hop %s not available", testfix.RefLayout)
	}
	got, want := hopxLayout(), zshLayout(t, home)
	gl, wl := strings.Split(got, "\n"), strings.Split(want, "\n")
	if len(gl) != len(wl) {
		t.Fatalf("hopx laid out %d lines, hop %s %d", len(gl), testfix.RefLayout, len(wl))
	}
	for i := range gl {
		if gl[i] != wl[i] {
			t.Errorf("line %d\n got  %q\n want %q", i, gl[i], wl[i])
		}
	}
}

func TestListWidths(t *testing.T) {
	t.Setenv("HOPX_LAYOUT", "")
	cases := []struct {
		name string
		list int
		want Widths
	}{
		{"mixed list", 0, Widths{39, 5, 22, 9, 9}},
		{"name past FitName fits 95% of distinct names", 1, Widths{29, 4, 22, 0, 0}},
		{"name capped at CapName", 2, Widths{56, 4, 1, 4, 0}},
		{"all-dash columns drop", 3, Widths{41, 4, 0, 0, 0}},
		{"region capped", 4, Widths{37, 4, 6, 7, 14}},
	}
	lists := layoutLists()
	for _, c := range cases {
		var rs []Row
		for _, a := range lists[c.list] {
			rs = append(rs, New(a[0], a[1], a[2], a[3], a[4], a[5], a[6], len(a) > 7))
		}
		w, ok := ParseWidths(List(rs, "/r", nil)[0])
		if !ok || w != c.want {
			t.Errorf("%s: widths %v (ok %v), want %v", c.name, w, ok, c.want)
		}
	}
}

func TestListFixed(t *testing.T) {
	t.Setenv("HOPX_LAYOUT", "fixed")
	var rs []Row
	for _, c := range cases {
		rs = append(rs, New(c[0], c[1], c[2], c[3], c[4], c[5], c[6], len(c) > 7))
	}
	for i, got := range List(rs, "/r", nil) {
		if want := Render(rs[i], "/r"); got != want {
			t.Errorf("row %d under HOPX_LAYOUT=fixed\n got  %q\n want %q", i, got, want)
		}
	}
}

func TestParseWidthsRejects(t *testing.T) {
	for _, s := range []string{"", "plain\t/d\t/d\tx", Off + Off + Off + "\t/d"} {
		if w, ok := ParseWidths(s); ok {
			t.Errorf("ParseWidths(%q) = %v, want a failure", s, w)
		}
	}
}
