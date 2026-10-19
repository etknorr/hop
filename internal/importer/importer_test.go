package importer

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/testfix"
)

func needZsh(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("zsh"); err != nil {
		t.Skip("zsh not available")
	}
}

func loadTOML(t *testing.T, text string) *config.Config {
	t.Helper()
	c := config.New()
	if err := c.Apply(text, "imported", true); err != nil {
		t.Fatalf("%v\n%s", err, text)
	}
	if len(c.Kinds) == 0 {
		c.LoadAllPresets()
	}
	return c
}

// zshKinds is the menu order zsh hop itself builds from cfg.
func zshKinds(t *testing.T, cfg string) string {
	t.Helper()
	out, err := testfix.Zsh(cfg, `print -r -- "${_HOP_ALL_KINDS[*]}"`, nil)
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(out)
}

func TestImportExample(t *testing.T) {
	needZsh(t)
	cfg := filepath.Join(testfix.HopHome(), "config.example.zsh")
	res, err := Import(cfg)
	if err != nil {
		t.Fatal(err)
	}
	c := loadTOML(t, res.TOML(cfg))
	if got, want := strings.Join(c.AllKinds(), " "), zshKinds(t, cfg); got != want {
		t.Errorf("kinds %q, zsh hop has %q", got, want)
	}
	k, _ := c.Lookup("irregular")
	if k.Shape != "exec" || k.Exec[len(k.Exec)-1] != "_hop_provider_irregular" {
		t.Errorf("an --fn kind imports as exec through compat.zsh: %+v", k)
	}
	tg, _ := c.Lookup("tg")
	if len(tg.Trim) != 1 || tg.Trim[0] != (config.TrimSpec{Col: "scope", Prefix: "proj-"}) {
		t.Errorf("tg trim = %v", tg.Trim)
	}
}

func TestImportFixtureMatchesCheckedIn(t *testing.T) {
	needZsh(t)
	td := filepath.Join(testfix.ModuleRoot(), "testdata")
	res, err := Import(filepath.Join(td, "fixture.zsh"))
	if err != nil {
		t.Fatal(err)
	}
	got := res.TOML(filepath.Join(td, "fixture.zsh"))
	got = strings.ReplaceAll(got, tildePath(td), "@TESTDATA@")
	want, _ := os.ReadFile(filepath.Join(td, "fixture.toml"))
	if got != string(want) {
		t.Errorf("testdata/fixture.toml is stale\n--- import\n%s--- checked in\n%s", got, want)
	}
	if len(res.Warnings) != 0 {
		t.Errorf("warnings: %q", res.Warnings)
	}
	if got, want := strings.Join(loadTOML(t, got).AllKinds(), " "), zshKinds(t, filepath.Join(td, "fixture.zsh")); got != want {
		t.Errorf("kinds %q, zsh hop has %q", got, want)
	}
}

// TestPresetsMatchHop imports each hop presets/*.zsh as a config and compares it with the embedded TOML.
func TestPresetsMatchHop(t *testing.T) {
	needZsh(t)
	for _, name := range config.PresetOrder {
		t.Run(name, func(t *testing.T) {
			src := filepath.Join(testfix.HopHome(), "presets", name+".zsh")
			res, err := Import(src)
			if err != nil {
				t.Fatal(err)
			}
			got := loadTOML(t, res.TOML(src))
			want := config.New()
			if err := want.LoadPreset(name); err != nil {
				t.Fatal(err)
			}
			if got.RegistryKey() != want.RegistryKey() {
				t.Errorf("embedded preset differs from zsh hop's\nzsh: %s\ngo:  %s", got.RegistryKey(), want.RegistryKey())
			}
		})
	}
}

func TestImportEveryOption(t *testing.T) {
	needZsh(t)
	cfg := filepath.Join(t.TempDir(), "c.zsh")
	os.WriteFile(cfg, []byte(`hop_preset dir
hop_kind a --default --dirs 'x,y,' --depth 3 --preview 'p,*.q' --preview-skip 's*' --scope-literal L --desc 'all dirs'
hop_kind b --files 'f/*' --under f/ --strip-ext --layout 'scope,name...' --layout 'name' --trim 'scope:a,scope:b,name:n' --name-template '{scope}-{env}' --exclude 'e*' --name-fn _hop_entity_name
hop_kind c --marker m.txt --under u --exclude 'z' --desc "it's quoted"
hop_kind dir --fn _hop_provider_dir --desc 'redeclared builtin'
typeset -g HOP_ACTION=open HOP_JUMP=unique HOP_VIM=0 HOP_HIST_MAX=50 HOP_DEFAULT_KINDS='a,b' HOP_FZF_HEIGHT=
`), 0o644)
	res, err := Import(cfg)
	if err != nil {
		t.Fatal(err)
	}
	text := res.TOML(cfg)
	c := loadTOML(t, text)
	for _, want := range []string{"action = 'open'", "jump = 'unique'", "vim = false", "hist_max = 50", "default_kinds = ['a', 'b']", "fzf_height = ''"} {
		if !strings.Contains(text, want) {
			t.Errorf("missing %q in\n%s", want, text)
		}
	}
	b, _ := c.Lookup("b")
	if b.Under != "f" || !b.StripExt || len(b.Layouts) != 2 || len(b.Trim) != 3 || b.NameFrom != "yaml:metadata.name" || b.NameTemplate != "{scope}-{env}" {
		t.Errorf("b = %+v", b)
	}
	a, _ := c.Lookup("a")
	if a.Depth != 3 || a.Scope != "L" || strings.Join(a.Dirs, ",") != "x,y" || !a.Default {
		t.Errorf("a = %+v", a)
	}
	if d, _ := c.Lookup("dir"); d.Builtin != "dir" || d.Desc != "redeclared builtin" {
		t.Errorf("dir = %+v", d)
	}
	if k, _ := c.Lookup("c"); k.Desc != "it's quoted" {
		t.Errorf("c desc = %q", k.Desc)
	}
}

func TestImportErrors(t *testing.T) {
	needZsh(t)
	for src, want := range map[string]string{
		"hop_kind x --dirs a --bogus 1\n": "unknown option: --bogus",
		"hop_kind x --fn nope\n":          "--fn nope is not a defined function",
		"hop_kind x --dirs a --desc\n":    "--desc needs a value",
		"hop_kind x --desc d\n":           "needs one of",
		"hop_kind x --dirs a --depth 0\n": "--depth must be a positive integer",
		"hop_preset nope\n":               "no such preset",
	} {
		cfg := filepath.Join(t.TempDir(), "c.zsh")
		os.WriteFile(cfg, []byte(src), 0o644)
		if _, err := Import(cfg); err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%q: got %v, want %q", src, err, want)
		}
	}
}

// TestEricConfig re-imports Eric's live config.zsh, only for a parity run, since that file is his to change.
func TestEricConfig(t *testing.T) {
	if os.Getenv("HOP_PARITY_REPO") == "" {
		t.Skip("set HOP_PARITY_REPO to check testdata/eric.toml against ~/.config/hop/config.zsh")
	}
	needZsh(t)
	src := filepath.Join(os.Getenv("HOME"), ".config", "hop", "config.zsh")
	res, err := Import(src)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile(filepath.Join(testfix.ModuleRoot(), "testdata", "eric.toml"))
	if got := res.TOML(src); got != string(want) {
		t.Errorf("testdata/eric.toml is stale\n--- import\n%s", got)
	}
}
