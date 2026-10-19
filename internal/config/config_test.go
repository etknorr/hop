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
		"HOP_VIM", "HOP_HIST_MAX", "HOP_DEFAULT_KINDS", "HOP_WORKSPACES", "HOP_REPOS", "HOP_WORKSPACES_FILE", "HOP_CONFIG",
		"HOP_DEBUG", "HOP_DEBUG_LOG", "HOP_FZF_MIN", "HOP_GUARD_WINDOW", "HOP_HOPRC", "HOP_SESSION"} {
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
		{"helm builtin", "[[kind]]\nname = 'a'\nbuiltin = 'helm'\n", `use recipes = ["helm"], or run hop import`, 3},
		{"bad depth", "[[kind]]\nname = 'a'\ndirs = ['x']\ndepth = 0\n", "depth must be a positive integer", 4},
		{"empty marker", "[[kind]]\nname = 'a'\nmarker = []\n", "marker needs at least one", 3},
		{"climbing marker", "[[kind]]\nname = 'a'\nmarker = ['../x']\n", "must be a relative path", 3},
		{"recursive marker", "[[kind]]\nname = 'a'\nmarker = ['**/x']\n", "must be a relative path", 3},
		{"min_depth on dirs", "[[kind]]\nname = 'a'\ndirs = ['x']\nmin_depth = 1\n", "min_depth applies only to a marker shape", 4},
		{"nested on files", "[[kind]]\nname = 'a'\nnested = false\nfiles = ['x']\n", "nested applies only to a marker shape", 3},
		{"negative min_depth", "[[kind]]\nname = 'a'\nmarker = 'm'\nmin_depth = -1\n", "non-negative integer", 4},
		{"sources and shape", "[[kind]]\nname = 'a'\ndirs = ['x']\n[[kind.source]]\nfiles = ['y']\n", "cannot also set dirs", 3},
		{"sources and option", "[[kind]]\nname = 'a'\npreview = ['x']\n[[kind.source]]\nfiles = ['y']\n", "preview belongs on each [[kind.source]]", 3},
		{"source without shape", "[[kind]]\nname = 'a'\n[[kind.source]]\nfiles = ['y']\n[[kind.source]]\nscope = 'z'\n", "source 2: set exactly one of", 5},
		{"source two shapes", "[[kind]]\nname = 'a'\n[[kind.source]]\nfiles = ['y']\nmarker = 'm'\n", "source 1: set exactly one of", 5},
		{"source builtin", "[[kind]]\nname = 'a'\n[[kind.source]]\nbuiltin = 'dir'\n", "not builtin", 4},
		{"source desc", "[[kind]]\nname = 'a'\n[[kind.source]]\nfiles = ['y']\ndesc = 'd'\n", "desc belongs on the [[kind]]", 5},
		{"source unknown key", "[[kind]]\nname = 'a'\n[[kind.source]]\nfiles = ['y']\n\nbogus = 1\n", `unknown key "bogus"`, 6},
		{"source min_depth", "[[kind]]\nname = 'a'\n[[kind.source]]\nmarker = 'm'\n[[kind.source]]\nfiles = ['y']\nmin_depth = 2\n", "source 2: min_depth applies only", 7},
		{"bad recipe", "recipes = ['nope']\n", "no such recipe: nope", 1},
		{"presets key", "presets = ['dir']\n", "presets are now recipes", 1},
		{"file jump", "[settings]\njump = 'sideways'\n", `jump "sideways" is not one of auto, unique, never`, 2},
		{"file action", "[settings]\n\naction = 'fly'\n", `action "fly" is not one of cd, open`, 3},
		{"env colour class", "[settings]\nenv_colors = { live = ['prod'] }\n", `unknown class "live"`, 2},
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

func TestZeroConfigDefaults(t *testing.T) {
	clearEnv(t)
	for _, src := range []string{"", "version = 1\n[settings]\naction = 'open'\n"} {
		c, err := Load(write(t, src))
		if err != nil {
			t.Fatal(err)
		}
		if got := strings.Join(c.AllKinds(), " "); got != "dir project file" {
			t.Errorf("kinds = %s", got)
		}
		if d := strings.Join(c.DefaultKinds(), " "); d != "dir project" {
			t.Errorf("defaults = %s", d)
		}
		if strings.Join(c.Loaded, " ") != "dir project file" {
			t.Errorf("loaded = %v", c.Loaded)
		}
	}
	c, err := Load(filepath.Join(t.TempDir(), "missing.toml"))
	if err != nil || len(c.Kinds) != 3 {
		t.Errorf("a missing file must behave like no config: %v %d", err, len(c.Kinds))
	}
	c, err = Load(write(t, "recipes = []\n"))
	if err != nil || len(c.Kinds) != 0 {
		t.Errorf("recipes = [] names nothing, so it gets nothing: %v %d", err, len(c.Kinds))
	}
	c, err = Load(write(t, "[[kind]]\nname = 'mine'\ndirs = ['x']\n"))
	if err != nil || strings.Join(c.AllKinds(), " ") != "mine" {
		t.Errorf("a config declaring a kind gets exactly that kind: %v", c.AllKinds())
	}
	c, err = Load(write(t, "recipes = ['helm', 'dir']\n"))
	if err != nil || strings.Join(c.AllKinds(), " ") != "helm dir" || strings.Join(c.Loaded, " ") != "helm dir" {
		t.Errorf("recipes load in the order named: %v %v", c.AllKinds(), c.Loaded)
	}
}

func TestEveryRecipeLoadsClean(t *testing.T) {
	clearEnv(t)
	if strings.Join(Recipes(), " ") != "dir project file terragrunt terraform-modules helm serverless puppet backstage" {
		t.Errorf("recipes = %v", Recipes())
	}
	for _, r := range Recipes() {
		c := New()
		if err := c.LoadRecipe(r); err != nil {
			t.Errorf("%s: %v", r, err)
		}
		if len(c.Warnings) > 0 || len(c.Kinds) != 1 || c.Kinds[0].Desc == "" || c.Kinds[0].Shape == "" {
			t.Errorf("%s: %d kinds, warnings %q, every kind needs a shape and a desc", r, len(c.Kinds), c.Warnings)
		}
	}
}

func TestZshConfigHint(t *testing.T) {
	clearEnv(t)
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	os.MkdirAll(filepath.Join(dir, "hop"), 0o755)
	os.WriteFile(filepath.Join(dir, "hop", "config.zsh"), []byte("hop_preset dir\n"), 0o644)
	want := "hop: found config.zsh; run 'hop import -o ~/.config/hop/config.toml' to use it"
	for _, hc := range []string{"", filepath.Join(dir, "hop", "config.zsh")} {
		t.Setenv("HOP_CONFIG", hc)
		c, err := Load(Path())
		if err != nil || len(c.Warnings) != 1 || c.Warnings[0] != want || len(c.Kinds) != 3 {
			t.Errorf("HOP_CONFIG=%q: %v %q %d", hc, err, c.Warnings, len(c.Kinds))
		}
	}
	t.Setenv("HOP_CONFIG", "")
	t.Setenv("HOP_SESSION", "x")
	if c, _ := Load(Path()); len(c.Warnings) != 0 {
		t.Errorf("a callback must not print the hint: %q", c.Warnings)
	}
	os.Unsetenv("HOP_SESSION")
	t.Setenv("HOP_CONFIG", filepath.Join(dir, "elsewhere.toml"))
	if c, _ := Load(Path()); len(c.Warnings) != 0 {
		t.Errorf("a HOP_CONFIG naming TOML never prints the hint: %q", c.Warnings)
	}
	t.Setenv("HOP_CONFIG", "")
	os.WriteFile(filepath.Join(dir, "hop", "config.toml"), []byte("recipes = ['dir']\n"), 0o644)
	if c, _ := Load(Path()); len(c.Warnings) != 0 {
		t.Errorf("a config.toml beside config.zsh needs no hint: %q", c.Warnings)
	}
}

func TestHoprcWarns(t *testing.T) {
	clearEnv(t)
	t.Setenv("HOP_HOPRC", "1")
	c, _ := Load(write(t, ""))
	if len(c.Warnings) != 1 || !strings.Contains(c.Warnings[0], "hop no longer reads a repo's .hoprc") {
		t.Errorf("warnings = %q", c.Warnings)
	}
}

func TestSources(t *testing.T) {
	clearEnv(t)
	src := `recipes = []

[[kind]]
name = 'h'
desc = 'two shapes'
default = true

  [[kind.source]]
  dirs = ['a', 'b']
  preview = ['x']

  [[kind.source]]
  marker = ['m', '*.n', 'p/q']
  under = 'u'
  min_depth = 1
  nested = false
  depth = 3
`
	c, err := Load(write(t, src))
	if err != nil {
		t.Fatal(err)
	}
	h, _ := c.Lookup("h")
	if h.Shape != "sources" || len(h.Sources) != 2 || !h.Default || h.Desc != "two shapes" {
		t.Fatalf("h = %+v", h)
	}
	s0, s1 := h.Sources[0], h.Sources[1]
	if s0.Shape != "dirs" || s0.Name != "h" || strings.Join(s0.Preview, ",") != "x" || !s0.Nested {
		t.Errorf("source 1 = %+v", s0)
	}
	if s1.Shape != "marker" || strings.Join(s1.Marker, ",") != "m,*.n,p/q" || s1.MinDepth != 1 || s1.Nested || s1.Under != "u" {
		t.Errorf("source 2 = %+v", s1)
	}
	if len(c.Warnings) != 1 || !strings.Contains(c.Warnings[0], ":17: kind \"h\": source 2: depth has no effect on a marker source") {
		t.Errorf("warnings = %q", c.Warnings)
	}
	ext := src + "\n[[kind]]\nname = 'h'\nextend = true\nfiles = ['f']\n"
	c, err = Load(write(t, ext))
	if err != nil {
		t.Fatal(err)
	}
	if h, _ := c.Lookup("h"); h.Shape != "files" || h.Sources != nil || !h.Default {
		t.Errorf("extend with a shape replaces the sources: %+v", h)
	}
}

func TestEnvColors(t *testing.T) {
	clearEnv(t)
	c, err := Load(write(t, "[settings]\nenv_colors = { dev = ['dev', 'sandbox'] }\n"))
	if err != nil {
		t.Fatal(err)
	}
	got := c.Settings.EnvColors
	if strings.Join(got["dev"], ",") != "dev,sandbox" || strings.Join(got["prod"], ",") != "prod" || strings.Join(got["staging"], ",") != "staging" {
		t.Errorf("a class left out keeps its default: %v", got)
	}
}

func TestExtendAndRedeclare(t *testing.T) {
	clearEnv(t)
	src := `recipes = ['terragrunt', 'dir']

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
	if strings.Join(tg.Marker, ",") != "terragrunt.hcl" || tg.MinDepth != 1 || !tg.Default {
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
	ext := "recipes = ['dir']\n[[kind]]\nname = 'dir'\nextend = true\nmarker = 'x'\n"
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
	if s.Jump != "auto" || s.JumpRaw != "sideways" || s.ActionRaw != "reveal" || len(c.Warnings) != 0 {
		t.Errorf("a bad HOP_JUMP falls back to auto, kept raw for the caller to warn about: %q %q %q", s.Jump, s.JumpRaw, c.Warnings)
	}
	clearEnv(t)
	c, _ = Load(write(t, ""))
	s = c.Settings
	if s.Action != "cd" || s.Jump != "auto" || *s.FzfHeight != "80%" || !*s.Vim || s.HistMax != 300 || s.Code != "code" ||
		s.ActionRaw != "" || s.JumpRaw != "" || s.Debug || s.GuardWindow != "0.15" || s.FzfMin != "" {
		t.Errorf("defaults: %+v", s)
	}
	if !strings.HasSuffix(s.DebugLog, "/.local/state/hop/debug.log") {
		t.Errorf("the debug log defaults to zsh hop's file: %s", s.DebugLog)
	}
	c, err = Load(write(t, "[settings]\ndebug = true\nguard_window = 0.3\nfzf_min = '0.55.0'\ndebug_log = '/x/log'\n"))
	if s := c.Settings; err != nil || !s.Debug || s.GuardWindow != "0.3" || s.FzfMin != "0.55.0" || s.DebugLog != "/x/log" {
		t.Errorf("file settings: %v %+v", err, c.Settings)
	}
	t.Setenv("HOP_DEBUG", "1")
	t.Setenv("HOP_GUARD_WINDOW", "0")
	t.Setenv("HOP_FZF_MIN", "0.50.0")
	t.Setenv("HOP_DEBUG_LOG", "/y/log")
	c, _ = Load(write(t, "[settings]\nguard_window = 0.3\n"))
	if s := c.Settings; !s.Debug || s.GuardWindow != "0" || s.FzfMin != "0.50.0" || s.DebugLog != "/y/log" {
		t.Errorf("env settings: %+v", s)
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
	t.Setenv("HOP_CONFIG", "/home/me/.config/hop/config.zsh")
	if p := Path(); p != "/x/hop/config.toml" {
		t.Errorf("a .zsh HOP_CONFIG is zsh hop's and never read as TOML: Path = %s", p)
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


func TestWorkspaceSettings(t *testing.T) {
	clearEnv(t)
	t.Setenv("XDG_CONFIG_HOME", "/xdg")
	c, _ := Load(write(t, ""))
	if c.Settings.WorkspacesFile != "/xdg/hop/workspaces" {
		t.Errorf("the workspaces file follows XDG_CONFIG_HOME: %s", c.Settings.WorkspacesFile)
	}
	os.Unsetenv("XDG_CONFIG_HOME")
	c, _ = Load(write(t, ""))
	if c.Settings.WorkspacesFile != filepath.Join(os.Getenv("HOME"), ".config", "hop", "workspaces") {
		t.Errorf("else ~/.config: %s", c.Settings.WorkspacesFile)
	}
	t.Setenv("HOP_WORKSPACES", "/a::/b c:/d")
	c, _ = Load(write(t, "[settings]\nworkspaces = ['/file']\n"))
	if strings.Join(c.Settings.Workspaces, "|") != "/a|/b c|/d" {
		t.Errorf("HOP_WORKSPACES splits on colons and beats the file: %q", c.Settings.Workspaces)
	}
}
