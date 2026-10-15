package match

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/etknorr/hop/spike/hopx/internal/testfix"
)

// TestFlagsMatchHop reads _HOP_MATCHER_FLAGS out of the worktree's lib/ui.zsh, so a change there fails here.
func TestFlagsMatchHop(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skip("zsh not available")
	}
	out, err := testfix.Zsh("/nonexistent", `print -rl -- "${_HOP_MATCHER_FLAGS[@]}"`, nil)
	if err != nil {
		t.Fatal(err)
	}
	if got := Lines(out); !slices.Equal(got, Flags) {
		t.Errorf("hop's flags:\n%q\nhopx's:\n%q", got, Flags)
	}
}

func fzf(t *testing.T) *FZF {
	t.Helper()
	f, err := New(os.Stderr)
	if err != nil {
		t.Skip(err)
	}
	return f
}

func TestFilter(t *testing.T) {
	f := fzf(t)
	row := "\x1b[1mvpc\x1b[0m\t/r/vpc\t/r/vpc/main.tf\t\x1b[2mterraform/vpc/\x1b[0m"
	got, err := f.Filter("vpc", []string{row})
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"vpc\t/r/vpc\t/r/vpc/main.tf\tterraform/vpc/"}; !slices.Equal(got, want) {
		t.Errorf("a row comes back whole, SGR stripped: %q", got)
	}
	if got, _ := f.Filter("zzqx", []string{row}); got != nil {
		t.Errorf("no match is nil, not an error: %q", got)
	}
	if got, _ := f.Filter("r/vpc/main", []string{row}); got != nil {
		t.Errorf("field 2 and 3 are never searched: %q", got)
	}
	if got, _ := f.Filter("terraform/vpc", []string{row}); len(got) != 1 {
		t.Errorf("field 4 is searched: %q", got)
	}
	if got, _ := f.Filter("vpc", []string{row}, "--nth=1"); len(got) != 1 {
		t.Errorf("--nth=1 still matches the display: %q", got)
	}
	if _, err := f.Filter("vpc", []string{row}, "--bogus-flag"); err == nil {
		t.Error("an fzf usage error must not read as no match")
	}
}

// TestHostileDefaults sets the FZF_DEFAULT_OPTS that broke hop once, and the result must not change.
func TestHostileDefaults(t *testing.T) {
	f := fzf(t)
	rs := []string{"b vpc\t/r/b\t/r/b\tb/", "a vpc\t/r/a\t/r/a\ta/"}
	clean, _ := f.Filter("vpc", rs)
	t.Setenv("FZF_DEFAULT_OPTS", "--no-sort --tac --nth=1 --accept-nth=1 --scheme=path")
	opts := filepath.Join(t.TempDir(), "opts")
	os.WriteFile(opts, []byte("--read0\n"), 0o644)
	t.Setenv("FZF_DEFAULT_OPTS_FILE", opts)
	if got, _ := f.Filter("vpc", rs); !slices.Equal(got, clean) {
		t.Errorf("a user default leaked in: %q vs %q", got, clean)
	}
}

func TestVersion(t *testing.T) {
	f := fzf(t)
	if v := f.Version(); !regexp.MustCompile(`^\d+\.\d+(\.\d+)?$`).MatchString(v) {
		t.Errorf("version %q", v)
	}
	if err := f.CheckVersion(); err != nil {
		t.Errorf("installed fzf refused: %v", err)
	}
	for _, tc := range []struct {
		a, b string
		want bool
	}{
		{"0.60.2", "0.60.3", true},
		{"0.60.3", "0.60.3", false},
		{"0.73.1", "0.60.3", false},
		{"0.9", "0.60.3", true},
		{"1.0", "0.60.3", false},
		{"0.60.3rc1", "0.60.3", false},
		{"0.44.1", "0.60.3", true},
	} {
		if got := Less(tc.a, tc.b); got != tc.want {
			t.Errorf("Less(%s, %s) = %v", tc.a, tc.b, got)
		}
	}
	stub := filepath.Join(t.TempDir(), "fzf")
	os.WriteFile(stub, []byte("#!/bin/sh\necho '0.44.1 (debian)'\n"), 0o755)
	old := &FZF{Bin: stub}
	if err := old.CheckVersion(); err == nil || !strings.Contains(err.Error(), "0.44.1") {
		t.Errorf("an old fzf must be refused by name: %v", err)
	}
}
