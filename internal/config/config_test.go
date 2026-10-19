package config

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func clearEnv(t *testing.T) {
	t.Helper()
	for _, v := range []string{"HOP_ACTION", "HOP_JUMP", "HOP_CODE", "HOP_CLIPBOARD", "HOP_HISTFILE", "HOP_FZF_HEIGHT",
		"HOP_VIM", "HOP_HIST_MAX", "HOP_DEFAULT_KINDS", "HOP_WORKSPACES", "HOP_REPOS", "HOP_WORKSPACES_FILE", "HOP_CONFIG"} {
		t.Setenv(v, "")
		os.Unsetenv(v)
	}
}

func write(t *testing.T, src string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(p, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestValidationErrors(t *testing.T) {
	clearEnv(t)
	cases := []struct {
		name, src, msg string
		line           int
	}{
		{"unknown kind key", "version = 1\n\n[[kind]]\nname = 'a'\ndirs = ['x']\nbogus = 1\n", `unknown key "bogus"`, 6},
		{"unknown top key", "version = 1\nshape = 'x'\n", `unknown key "shape"`, 2},
		{"unknown setting", "[settings]\naction = 'cd'\njumpy = 'x'\n", `unknown setting "jumpy"`, 3},
		{"two shapes", "[[kind]]\nname = 'a'\nfiles = ['*']\n\n[[kind]]\nname = 'b'\ndirs = ['x']\nmarker = 'm'\n", "set exactly one of", 8},
		{"no shape", "[[kind]]\nname = 'a'\ndesc = 'd'\n", "needs one of dirs", 2},
		{"layout column", "[[kind]]\nname = 'a'\nmarker = 'm'\nlayout = ['scope,zone']\n", `unknown column "zone"`, 4},
		{"layout dots", "[[kind]]\nname = 'a'\nmarker = 'm'\nlayout = ['scope...,name']\n", "only the last column may end in ...", 4},
		{"trim column", "[[kind]]\nname = 'a'\nmarker = 'm'\nlayout = ['scope']\ntrim = { zone = 'x' }\n", `trim: unknown column "zone"`, 5},
		{"name comma", "[[kind]]\nname = 'a,b'\ndirs = ['x']\n", "hold no comma or space", 2},
		{"name space", "[[kind]]\ndirs = ['x']\nname = 'a b'\n", "hold no comma or space", 3},
		{"name dash", "[[kind]]\nname = '-a'\ndirs = ['x']\n", "not start with '-'", 2},
		{"missing name", "[[kind]]\ndirs = ['x']\n", "needs a name", 1},
		{"extend unknown", "[[kind]]\nname = 'zz'\nextend = true\n", "no earlier kind", 3},
		{"bad builtin", "[[kind]]\nname = 'a'\nbuiltin = 'nope'\n", "unknown builtin", 3},
		{"bad depth", "[[kind]]\nname = 'a'\ndirs = ['x']\ndepth = 0\n", "depth must be a positive integer", 4},
		{"glob marker", "[[kind]]\nname = 'a'\nmarker = '*.hcl'\n", "marker must be a literal", 3},
		{"bad preset", "presets = ['nope']\n", "no such preset: nope", 1},
		{"syntax", "[[kind]\nname = 'a'\n", "expected end of table array name", -1},
		{"version", "version = 2\n", "newer than this hop", 1},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p := write(t, c.src)
			_, err := Load(p)
			var ce *Error
			if !errors.As(err, &ce) {
				t.Fatalf("want a config error, got %v", err)
			}
			if !strings.Contains(ce.Msg, c.msg) || (ce.Line != c.line && !(c.line < 0 && ce.Line > 0)) || ce.File != p {
				t.Errorf("got %v (line %d), want %q at line %d", err, ce.Line, c.msg, c.line)
			}
		})
	}
}

func TestEmptyRegistryLoadsEveryPreset(t *testing.T) {
	clearEnv(t)
	for _, src := range []string{"", "version = 1\n[settings]\naction = 'open'\n"} {
		c, err := Load(write(t, src))
		if err != nil {
			t.Fatal(err)
		}
		got := strings.Join(c.AllKinds(), " ")
		if got != "tg mod helm serverless puppet backstage dir file" {
			t.Errorf("kinds = %s", got)
		}
		if d := strings.Join(c.DefaultKinds(), " "); d != "tg mod helm dir" {
			t.Errorf("defaults = %s", d)
		}
	}
	c, err := Load(filepath.Join(t.TempDir(), "missing.toml"))
	if err != nil || len(c.Kinds) != 8 {
		t.Errorf("a missing file must behave like no config: %v %d", err, len(c.Kinds))
	}
}

func TestExtendAndRedeclare(t *testing.T) {
	clearEnv(t)
	src := `presets = ['terragrunt', 'dir']

[[kind]]
name = 'tg'
extend = true
trim = { scope = 'acct-', env = ['env-', 'e-'] }

[[kind]]
name = 'mine'
dirs = ['a', 'b']

[[kind]]
name = 'dir'
desc = 'replaced'
marker = 'Makefile'
`
	c, err := Load(write(t, src))
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(c.AllKinds(), " "); got != "tg dir mine" {
		t.Errorf("a redeclared kind must keep its menu slot: %s", got)
	}
	tg, _ := c.Lookup("tg")
	if tg.Marker != "terragrunt.hcl" || tg.Under != "terraform" || len(tg.Layouts) != 2 || !tg.Default {
		t.Errorf("extend must keep the preset's keys: %+v", tg)
	}
	want := []TrimSpec{{"scope", "acct-"}, {"env", "env-"}, {"env", "e-"}}
	if len(tg.Trim) != 3 || tg.Trim[0] != want[0] || tg.Trim[1] != want[1] || tg.Trim[2] != want[2] {
		t.Errorf("trim = %v", tg.Trim)
	}
	d, _ := c.Lookup("dir")
	if d.Shape != "marker" || d.Builtin != "" || d.Default || d.Desc != "replaced" {
		t.Errorf("a redeclared kind without extend replaces it: %+v", d)
	}
	ext := "presets = ['dir']\n[[kind]]\nname = 'dir'\nextend = true\nmarker = 'x'\n"
	c, err = Load(write(t, ext))
	if err != nil {
		t.Fatal(err)
	}
	if d, _ := c.Lookup("dir"); d.Shape != "marker" || d.Builtin != "" || !d.Default {
		t.Errorf("extend with a new shape drops the old one: %+v", d)
	}
}

func TestInapplicableWarns(t *testing.T) {
	clearEnv(t)
	c, err := Load(write(t, "[[kind]]\nname = 'a'\ndirs = ['x']\nexclude = ['y']\n"))
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Warnings) != 1 || !strings.Contains(c.Warnings[0], ":4: kind \"a\": exclude has no effect on a dirs kind") {
		t.Errorf("warnings = %q", c.Warnings)
	}
}

func TestSettingsPrecedence(t *testing.T) {
	clearEnv(t)
	src := "[settings]\naction = 'open'\njump = 'never'\nfzf_height = '50%'\nhist_max = 10\ndefault_kinds = ['dir']\n"
	p := write(t, src)
	c, err := Load(p)
	if err != nil {
		t.Fatal(err)
	}
	s := c.Settings
	if s.Action != "open" || s.Jump != "never" || *s.FzfHeight != "50%" || s.HistMax != 10 || strings.Join(c.DefaultKinds(), ",") != "dir" {
		t.Errorf("file settings: %+v", s)
	}
	t.Setenv("HOP_ACTION", "reveal")
	t.Setenv("HOP_FZF_HEIGHT", "")
	t.Setenv("HOP_DEFAULT_KINDS", "tg, mod")
	t.Setenv("HOP_JUMP", "sideways")
	c, _ = Load(p)
	s = c.Settings
	if s.Action != "reveal" || *s.FzfHeight != "" || strings.Join(c.DefaultKinds(), ",") != "tg,mod" {
		t.Errorf("env must beat the file, and an empty HOP_FZF_HEIGHT means fullscreen: %+v", s)
	}
	if s.Jump != "auto" || len(c.Warnings) != 1 {
		t.Errorf("a bad jump falls back to auto with a warning: %q %q", s.Jump, c.Warnings)
	}
	clearEnv(t)
	c, _ = Load(write(t, ""))
	s = c.Settings
	if s.Action != "cd" || s.Jump != "auto" || *s.FzfHeight != "80%" || !*s.Vim || s.HistMax != 300 || s.Code != "code" {
		t.Errorf("defaults: %+v", s)
	}
	if !strings.HasSuffix(s.HistFile, "/.local/state/hop/history") {
		t.Errorf("the history defaults to zsh hop's file: %s", s.HistFile)
	}
}

func TestPath(t *testing.T) {
	clearEnv(t)
	t.Setenv("XDG_CONFIG_HOME", "/x")
	if p := Path(); p != "/x/hop/config.toml" {
		t.Errorf("Path = %s", p)
	}
	t.Setenv("HOP_CONFIG", "/y.toml")
	if p := Path(); p != "/y.toml" {
		t.Errorf("Path = %s", p)
	}
}

func TestEricConfigLoads(t *testing.T) {
	clearEnv(t)
	c, err := Load(filepath.Join("..", "..", "testdata", "eric.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(c.AllKinds(), " "); got != "tg mod helm serverless puppet backstage dir file mesos conf rules" {
		t.Errorf("kinds = %s", got)
	}
	if got := strings.Join(c.DefaultKinds(), " "); got != "tg mod helm dir mesos" {
		t.Errorf("defaults = %s", got)
	}
	if len(c.Warnings) > 0 {
		t.Errorf("warnings: %q", c.Warnings)
	}
}
