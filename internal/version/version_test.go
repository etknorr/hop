package version

import (
	"runtime/debug"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
)

func TestMain(m *testing.M) { testfix.Main(m) }

func bi(ver string, kv ...string) func() (*debug.BuildInfo, bool) {
	return func() (*debug.BuildInfo, bool) {
		b := &debug.BuildInfo{Main: debug.Module{Path: Module, Version: ver}}
		for i := 0; i+1 < len(kv); i += 2 {
			b.Settings = append(b.Settings, debug.BuildSetting{Key: kv[i], Value: kv[i+1]})
		}
		return b, true
	}
}

func TestRead(t *testing.T) {
	none := func() (*debug.BuildInfo, bool) { return nil, false }
	for _, c := range []struct {
		name, stamp string
		bi          func() (*debug.BuildInfo, bool)
		ver, line   string
		checkout    bool
	}{
		{"release -X wins", "1.0.0", bi("v0.0.0-2026-abc", "vcs.revision", "abcdef1234", "vcs.modified", "false"), "1.0.0", "hop 1.0.0", false},
		{"a v in -X is dropped", "v1.2.3", none, "1.2.3", "hop 1.2.3", false},
		{"go install records the tag", "", bi("v1.0.1"), "1.0.1", "hop 1.0.1", false},
		{"go install of a pseudo-version is devel", "", bi("v1.0.2-0.20261019120000-abcdef123456"), "devel", "hop devel", false},
		{"checkout between releases", "", bi("v1.0.2-0.20261019120000-abcdef123456+dirty", "vcs.revision", "abcdef1234567", "vcs.modified", "true"), "devel", "hop devel (abcdef1, dirty)", true},
		{"checkout clean on a tag", "", bi("v1.0.0", "vcs.revision", "1234567890", "vcs.modified", "false"), "1.0.0", "hop 1.0.0 (1234567)", true},
		{"no build info", "", none, "devel", "hop devel", false},
		{"(devel) with no VCS stamp", "", bi("(devel)"), "devel", "hop devel", false},
	} {
		i := read(c.stamp, c.bi)
		if i.Version != c.ver || line(i) != c.line || i.Checkout() != c.checkout {
			t.Errorf("%s: version %q line %q checkout %v; want %q %q %v", c.name, i.Version, line(i), i.Checkout(), c.ver, c.line, c.checkout)
		}
	}
}

func TestStale(t *testing.T) {
	if s := Stale("", "zsh"); s != "" {
		t.Errorf("no HOP_INIT_HASH means no call through the function, so nothing to say: %q", s)
	}
	if s := Stale(InitHash(), "zsh"); s != "" {
		t.Errorf("a current hash says nothing: %q", s)
	}
	if s := Stale("000000000000", "fish"); s != "hop: your shell integration predates this hop: run 'exec fish' to reload it" {
		t.Errorf("stale: %q", s)
	}
	if s := Stale("000000000000", ""); !strings.Contains(s, "'exec $SHELL'") {
		t.Errorf("stale with no HOP_SHELL: %q", s)
	}
}
