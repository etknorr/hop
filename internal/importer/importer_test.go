package importer

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
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

func writeZsh(t *testing.T, src string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "c.zsh")
	if err := os.WriteFile(p, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// TestImportExample: the example's --fn kind is refused by name, and the rest round-trips in zsh hop's order.
func TestImportExample(t *testing.T) {
	needZsh(t)
	cfg := filepath.Join(testfix.RefHome(testfix.RefLayout), "config.example.zsh")
	if _, err := Import(cfg); err == nil || !strings.Contains(err.Error(), "kind irregular: --fn _hop_provider_irregular has no hop equivalent") {
		t.Errorf("an --fn kind must be refused by name: %v", err)
	}
	src, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	noFn := regexp.MustCompile(`(?ms)^_hop_provider_irregular\(\) \{.*?^\}\n|^hop_kind irregular .*?\n`).ReplaceAllString(string(src), "")
	stripped := writeZsh(t, noFn)
	res, err := Import(stripped)
	if err != nil {
		t.Fatal(err)
	}
	c := loadTOML(t, res.TOML(stripped))
	if got, want := strings.Join(c.AllKinds(), " "), zshKinds(t, stripped); got != want || strings.Contains(got, "irregular") {
		t.Errorf("kinds %q, zsh hop has %q", got, want)
	}
	tg, _ := c.Lookup("tg")
	if len(tg.Trim) != 1 || tg.Trim[0] != (config.TrimSpec{Col: "scope", Prefix: "proj-"}) || tg.Under != "terraform" {
		t.Errorf("tg = %+v", tg)
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
	b, _ := os.ReadFile(filepath.Join(td, "fixture.toml"))
	want, _, _ := strings.Cut(string(b), "\n# Not imported:")
	if got != want {
		t.Errorf("testdata/fixture.toml is stale\n--- import\n%s--- checked in\n%s", got, want)
	}
	if len(res.Warnings) != 0 {
		t.Errorf("warnings: %q", res.Warnings)
	}
	if got, want := strings.Join(loadTOML(t, got).AllKinds(), " "), zshKinds(t, filepath.Join(td, "fixture.zsh")); got != want {
		t.Errorf("kinds %q, zsh hop has %q", got, want)
	}
}

func TestImportMatchMatchesCheckedIn(t *testing.T) {
	needZsh(t)
	root := testfix.ModuleRoot()
	t.Chdir(root)
	res, err := Import(filepath.Join("testdata", "match.zsh"))
	if err != nil {
		t.Fatal(err)
	}
	got := strings.ReplaceAll(res.TOML(filepath.Join("testdata", "match.zsh")), tildePath("testdata"), "testdata")
	want, _ := os.ReadFile(filepath.Join(root, "testdata", "match.toml"))
	if got != string(want) {
		t.Errorf("testdata/match.toml is stale\n--- import\n%s", got)
	}
}

// TestPresetsMatchHop imports each of zsh hop's presets/*.zsh and compares it with the frozen definition.
func TestPresetsMatchHop(t *testing.T) {
	needZsh(t)
	if strings.Join(PresetOrder(), " ") != "terragrunt terraform-modules helm serverless puppet backstage dir file" {
		t.Errorf("preset order = %v", PresetOrder())
	}
	for _, name := range PresetOrder() {
		t.Run(name, func(t *testing.T) {
			src := filepath.Join(testfix.RefHome(testfix.RefLayout), "presets", name+".zsh")
			res, err := Import(src)
			if err != nil {
				t.Fatal(err)
			}
			got := loadTOML(t, res.TOML(src))
			want := config.New()
			if err := LoadPreset(want, name); err != nil {
				t.Fatal(err)
			}
			if got.RegistryKey() != want.RegistryKey() {
				t.Errorf("frozen preset differs from zsh hop's\nzsh: %s\ngo:  %s", got.RegistryKey(), want.RegistryKey())
			}
		})
	}
}

func TestImportEveryOption(t *testing.T) {
	needZsh(t)
	cfg := writeZsh(t, `hop_preset dir
hop_kind a --default --dirs 'x,y,' --depth 3 --preview 'p,*.q' --preview-skip 's*' --scope-literal L --desc 'all dirs'
hop_kind b --files 'f/*' --under f/ --strip-ext --layout 'scope,name...' --layout 'name' --trim 'scope:a,scope:b,name:n' --name-template '{scope}-{env}' --exclude 'e*' --name-fn _hop_entity_name
hop_kind c --marker m.txt --under u --exclude 'z' --desc "it's quoted"
hop_kind dir --fn _hop_provider_dir --preview 'ignored' --desc 'redeclared builtin'
hop_kind charts --default --fn _hop_provider_helm --desc 'helm, renamed'
typeset -g HOP_ACTION=open HOP_JUMP=unique HOP_VIM=0 HOP_HIST_MAX=50 HOP_DEFAULT_KINDS='a,b' HOP_FZF_HEIGHT=
typeset -g HOP_DEBUG=1 HOP_GUARD_WINDOW=0.2 HOP_FZF_MIN=0.55.0 HOP_HISTFILE=~/h HOP_HOPRC=1
`)
	res, err := Import(cfg)
	if err != nil {
		t.Fatal(err)
	}
	text := res.TOML(cfg)
	c := loadTOML(t, text)
	for _, want := range []string{"recipes = []", "action = 'open'", "jump = 'unique'", "vim = false", "hist_max = 50", "default_kinds = ['a', 'b']",
		"fzf_height = ''", "debug = true", "guard_window = '0.2'", "fzf_min = '0.55.0'", "hist_file = '" + os.Getenv("HOME") + "/h'",
		"env_colors = { prod = ['prod'], staging = ['staging'], dev = ['dev', 'playground'] }"} {
		if !strings.Contains(text, want) {
			t.Errorf("missing %q in\n%s", want, text)
		}
	}
	if strings.Contains(text, "extend") || strings.Contains(text, "hoprc") {
		t.Errorf("the import is flat and drops HOP_HOPRC:\n%s", text)
	}
	if len(res.Warnings) != 1 || !strings.Contains(res.Warnings[0], "HOP_HOPRC=1 is not carried over") {
		t.Errorf("warnings = %q", res.Warnings)
	}
	if got := strings.Join(c.AllKinds(), " "); got != "dir a b c charts" {
		t.Errorf("a redeclared kind keeps its slot: %s", got)
	}
	b, _ := c.Lookup("b")
	if b.Under != "f" || !b.StripExt || len(b.Layouts) != 2 || len(b.Trim) != 3 || b.NameFrom != "yaml:metadata.name" || b.NameTemplate != "{scope}-{env}" {
		t.Errorf("b = %+v", b)
	}
	a, _ := c.Lookup("a")
	if a.Depth != 3 || a.Scope != "L" || strings.Join(a.Dirs, ",") != "x,y" || !a.Default {
		t.Errorf("a = %+v", a)
	}
	if d, _ := c.Lookup("dir"); d.Builtin != "dir" || d.Desc != "redeclared builtin" || d.Preview != nil || d.Default {
		t.Errorf("an --fn kind keeps only its name, desc and default: %+v", d)
	}
	if h, _ := c.Lookup("charts"); h.Shape != "sources" || len(h.Sources) != 4 || !h.Default || h.Desc != "helm, renamed" {
		t.Errorf("--fn _hop_provider_helm inlines the four helm sources: %+v", h)
	}
	if k, _ := c.Lookup("c"); k.Desc != "it's quoted" {
		t.Errorf("c desc = %q", k.Desc)
	}
}

func TestImportEmptyIsEveryPreset(t *testing.T) {
	needZsh(t)
	cfg := writeZsh(t, "# nothing declared\n")
	res, err := Import(cfg)
	if err != nil {
		t.Fatal(err)
	}
	c := loadTOML(t, res.TOML(cfg))
	if got, want := strings.Join(c.AllKinds(), " "), zshKinds(t, cfg); got != want {
		t.Errorf("kinds %q, zsh hop has %q", got, want)
	}
}

func TestImportErrors(t *testing.T) {
	needZsh(t)
	for src, want := range map[string]string{
		"hop_kind x --dirs a --bogus 1\n":                "unknown option: --bogus",
		"f() { : }\nhop_kind x --fn f\n":                 "kind x: --fn f has no hop equivalent",
		"hop_kind x --files a --name-fn other\n":         "kind x: --name-fn other has no hop equivalent",
		"hop_kind x --dirs a --desc\n":                   "--desc needs a value",
		"hop_kind x --desc d\n":                          "needs one of",
		"hop_kind x --dirs a --depth 0\n":                "--depth must be a positive integer",
		"hop_kind x --dirs a --depth two\n":              "--depth must be a positive integer",
		"hop_preset nope\n":                              "no such preset",
		"hop_kind tg --dirs a --extend 1\n":              "unknown option: --extend",
		"hop_kind x --dirs a\ntypeset -g HOP_JUMP=bad\n": "",
	} {
		_, err := Import(writeZsh(t, src))
		if want == "" {
			if err != nil {
				t.Errorf("%q: %v", src, err)
			}
			continue
		}
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%q: got %v, want %q", src, err, want)
		}
	}
	res, _ := Import(writeZsh(t, "hop_kind x --dirs a\ntypeset -g HOP_JUMP=bad\n"))
	if len(res.Warnings) != 1 || !strings.Contains(res.Warnings[0], "HOP_JUMP=bad is not one of auto, unique, never") || len(res.Settings) != 0 {
		t.Errorf("a value zsh hop ignored is dropped with a warning: %q %v", res.Warnings, res.Settings)
	}
}

func TestImportBareProviderWarns(t *testing.T) {
	needZsh(t)
	res, err := Import(writeZsh(t, "hop_preset dir\n_hop_provider_extra() { : }\n"))
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Warnings) != 1 || !strings.Contains(res.Warnings[0], "_hop_provider_extra is a provider function, which hop cannot run; zsh hop listed it as kind extra") {
		t.Errorf("warnings = %q", res.Warnings)
	}
}

// TestEricConfig re-imports Eric's live config.zsh, only for a parity run, since that file is his to change.
func TestEricConfig(t *testing.T) {
	if os.Getenv("HOP_PARITY_REPO") == "" {
		t.Skip("set HOP_PARITY_REPO to check testdata/eric.toml against $HOP_PARITY_ZSHCONFIG, default ~/.config/hop/config.zsh")
	}
	needZsh(t)
	t.Setenv("HOME", testfix.RealHome)
	src := os.Getenv("HOP_PARITY_ZSHCONFIG")
	if src == "" {
		src = filepath.Join(testfix.RealHome, ".config", "hop", "config.zsh")
	}
	res, err := Import(src)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile(filepath.Join(testfix.ModuleRoot(), "testdata", "eric.toml"))
	if got := res.TOML(src); got != string(want) {
		t.Errorf("testdata/eric.toml is stale\n--- import\n%s", got)
	}
	c := loadTOML(t, string(want))
	if got := strings.Join(c.AllKinds(), " "); got != "tg mod helm serverless puppet backstage dir file mesos conf rules" {
		t.Errorf("kinds = %s", got)
	}
	if got := strings.Join(c.DefaultKinds(), " "); got != "tg mod helm dir mesos" {
		t.Errorf("defaults = %s", got)
	}
}
