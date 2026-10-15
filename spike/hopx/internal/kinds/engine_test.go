package kinds

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/spike/hopx/internal/config"
	"github.com/etknorr/hop/spike/hopx/internal/rows"
	"github.com/etknorr/hop/spike/hopx/internal/testfix"
)

var update = flag.Bool("update", false, "rewrite testdata/golden from zsh hop's _hop_generate")

func testdata(p string) string { return filepath.Join(testfix.ModuleRoot(), "testdata", p) }

// fixture builds the repo and loads testdata/fixture.toml, whose @TESTDATA@ is this checkout's testdata.
func fixture(t *testing.T) (string, *config.Config) {
	t.Helper()
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root := filepath.Join(t.TempDir(), "repo")
	if err := testfix.Build(root); err != nil {
		t.Fatal(err)
	}
	src, err := os.ReadFile(testdata("fixture.toml"))
	if err != nil {
		t.Fatal(err)
	}
	cfg := config.New()
	text := strings.ReplaceAll(string(src), "@TESTDATA@", testdata(""))
	if err := cfg.Apply(text, "fixture.toml", true); err != nil {
		t.Fatal(err)
	}
	return root, cfg
}

func render(rs []rows.Row, root string) string {
	var b strings.Builder
	for _, r := range rs {
		b.WriteString(rows.Render(r, root))
		b.WriteByte('\n')
	}
	return b.String()
}

func TestGoldenRows(t *testing.T) {
	root, cfg := fixture(t)
	for _, k := range cfg.AllKinds() {
		t.Run(k, func(t *testing.T) {
			golden := testdata("golden/" + k + ".rows")
			if *update {
				out, err := testfix.Zsh(testdata("fixture.zsh"), `_hop_generate "$1" "$2"`, nil, root, k)
				if err != nil {
					t.Fatal(err)
				}
				os.WriteFile(golden, []byte(strings.ReplaceAll(out, root, "@ROOT@")), 0o644)
			}
			want, err := os.ReadFile(golden)
			if err != nil {
				t.Fatal(err)
			}
			var stderr bytes.Buffer
			got := strings.ReplaceAll(render(Generate(cfg, root, []string{k}, &stderr), root), root, "@ROOT@")
			if got != string(want) {
				t.Errorf("rows differ from %s\n--- got\n%s--- want\n%s", golden, rows.StripANSI(got), rows.StripANSI(string(want)))
			}
			if stderr.Len() > 0 {
				t.Errorf("stderr: %s", stderr.String())
			}
		})
	}
}

// TestLiveZsh re-runs zsh hop on a fresh fixture, which catches a golden that went stale against hop.
func TestLiveZsh(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skip("zsh or hop.zsh not available")
	}
	root, cfg := fixture(t)
	kinds := cfg.AllKinds()
	want, err := testfix.Zsh(testdata("fixture.zsh"), `r=$1; shift; _hop_generate "$r" "$@"`, nil, append([]string{root}, kinds...)...)
	if err != nil {
		t.Fatal(err)
	}
	got := render(Generate(cfg, root, kinds, os.Stderr), root)
	if got != want {
		t.Errorf("hopx and zsh hop differ on the fixture\n--- hopx\n%s--- zsh\n%s", rows.StripANSI(got), rows.StripANSI(want))
	}
}

func TestUnknownKindAndOrder(t *testing.T) {
	root, cfg := fixture(t)
	var stderr bytes.Buffer
	a := render(Generate(cfg, root, []string{"svc", "nope", "dir"}, &stderr), root)
	b := render(Generate(cfg, root, []string{"svc"}, nil), root) + render(Generate(cfg, root, []string{"dir"}, nil), root)
	if a != b {
		t.Error("rows are not in kind order")
	}
	if !strings.Contains(stderr.String(), "unknown kind: nope") {
		t.Errorf("stderr = %q", stderr.String())
	}
}

func TestNotARepo(t *testing.T) {
	_, cfg := fixture(t)
	dir := t.TempDir()
	var stderr bytes.Buffer
	rs := Generate(cfg, dir, []string{"dir", "svc"}, &stderr)
	if len(rs) != 1 || rs[0].Name != "<root>" {
		t.Errorf("want only the root row, got %v", rs)
	}
	if strings.Count(stderr.String(), "git ls-files failed") != 1 {
		t.Errorf("want one git error, got %q", stderr.String())
	}
}

func TestColumns(t *testing.T) {
	k := &config.Kind{
		Layouts: []string{"scope,name...", "scope,env,region,name..."},
		Trim:    []config.TrimSpec{{Col: "scope", Prefix: "acct-"}, {Col: "scope", Prefix: "a"}, {Col: "env", Prefix: "env-"}},
	}
	cases := []struct {
		path string
		want cols
		ok   bool
	}{
		{"acct-ab/env-prod/us-east-1/vpc", cols{"b", "prod", "us-east-1", "vpc"}, true},
		{"acct-ab/env-prod/us-east-1/rbac/reader", cols{"b", "prod", "us-east-1", "rbac/reader"}, true},
		{"acct-x/policies", cols{"x", "-", "-", "policies"}, true},
		{"lonely", cols{}, false},
	}
	for _, c := range cases {
		got, ok := columns(k, c.path)
		if ok != c.ok || (ok && got != c.want) {
			t.Errorf("columns(%q) = %v %v, want %v %v", c.path, got, ok, c.want, c.ok)
		}
	}
	tpl := &config.Kind{Layouts: []string{"scope,env,-"}, NameTemplate: "{scope}/{env}", Trim: []config.TrimSpec{{Col: "env", Prefix: "e"}}}
	if got, _ := columns(tpl, "svc/eprod/x"); got.name != "svc/prod" {
		t.Errorf("template after trim: %q", got.name)
	}
	none := &config.Kind{NameTemplate: "{scope}!", Trim: []config.TrimSpec{{Col: "name", Prefix: "p"}}}
	if got, _ := columns(none, "a/b/plain"); got != (cols{"a/b", "-", "-", "plain"}) {
		t.Errorf("no layout must skip trim and template: %v", got)
	}
	if got, _ := columns(none, "top"); got.scope != "." {
		t.Errorf("a root-level path's scope is zsh's :h, '.': %q", got.scope)
	}
}

func TestZglob(t *testing.T) {
	d := t.TempDir()
	for p, c := range map[string]string{"a2.tf": "x", "a.tf": "", "B1.tf": "x", ".h.tf": "x", "sub/x/c.md": "x", ".dot/d.md": "x", "e.md": "x"} {
		os.MkdirAll(filepath.Dir(filepath.Join(d, p)), 0o755)
		os.WriteFile(filepath.Join(d, p), []byte(c), 0o644)
	}
	os.Symlink("a2.tf", filepath.Join(d, "0.tf"))
	got := zglob(d, "*.tf")
	want := []string{d + "/a2.tf", d + "/B1.tf"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("*.tf = %v, want %v (no empty, dot or symlink, collated)", got, want)
	}
	got = zglob(d, "**/*.md")
	want = []string{d + "/e.md", d + "/sub/x/c.md"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("**/*.md = %v, want %v", got, want)
	}
}

func TestEntityName(t *testing.T) {
	d := t.TempDir()
	cases := map[string]string{
		"metadata:\n  name: \"q\"\n":            "q",
		"metadata:\n  name: 'q'  \n":            "q",
		"metadata:\n  name: \n":                 "f",
		"metadata:\n  name:\n  name: two\n":     "two",
		"spec:\n  name: no\n":                   "f",
		"metadata:\nspec:\n  name: no\n":        "f",
		"metadata:\n  name: last-no-newline":    "f",
		"metadata:\r\n  name: crlf\r\n":         "crlf",
		"metadata:\n  labels: {}\n  name: ok\n": "ok",
	}
	for src, want := range cases {
		p := filepath.Join(d, "f.yaml")
		os.WriteFile(p, []byte(src), 0o644)
		if got := entityName(p); got != want {
			t.Errorf("entityName(%q) = %q, want %q", src, got, want)
		}
	}
}

func TestZshPattern(t *testing.T) {
	cases := []struct {
		pat, s string
		want   bool
	}{
		{"*/shared/*", "infra/shared/terragrunt.hcl", true},
		{"infra/acct-b*", "infra/acct-b/x/terragrunt.hcl", true},
		{"provider_*.tf", "provider_aws.tf", true},
		{"(a|b).tf", "b.tf", true},
		{"[!a]*", "abc", false},
		{"x\\*", "x*", true},
	}
	for _, c := range cases {
		if got := zshPattern(c.pat, true).MatchString(c.s); got != c.want {
			t.Errorf("%q ~ %q = %v", c.s, c.pat, got)
		}
	}
}
