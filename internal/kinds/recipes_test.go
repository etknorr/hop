package kinds

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/importer"
	"github.com/etknorr/hop/internal/rows"
	"github.com/etknorr/hop/internal/testfix"
)

// buildRepo is a git repo holding files, plus tracked symlinks and tracked paths deleted from the worktree after adding.
func buildRepo(t *testing.T, files, links map[string]string, deleted ...string) string {
	t.Helper()
	root := testfix.Resolved(t.TempDir())
	write := func(p, c string) {
		full := filepath.Join(root, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(c), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for p, c := range files {
		write(p, c)
	}
	for _, p := range deleted {
		write(p, "x\n")
	}
	for p, target := range links {
		full := filepath.Join(root, p)
		os.MkdirAll(filepath.Dir(full), 0o755)
		if err := os.Symlink(target, full); err != nil {
			t.Fatal(err)
		}
	}
	for _, args := range [][]string{{"init", "-q"}, {"add", "-A"}} {
		cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	for _, p := range deleted {
		os.Remove(filepath.Join(root, p))
	}
	return root
}

func loadSrc(t *testing.T, src string) *config.Config {
	t.Helper()
	c := config.New()
	if err := c.Apply(src, "test.toml", true); err != nil {
		t.Fatal(err)
	}
	if len(c.Warnings) > 0 {
		t.Fatalf("warnings: %q", c.Warnings)
	}
	return c
}

// brief is each row as name|scope|rel, the columns a recipe decides.
func brief(rs []rows.Row, root string) []string {
	out := make([]string, len(rs))
	for i, r := range rs {
		out[i] = r.Name + "|" + r.Scope + "|" + rows.Rel(r, root)
	}
	return out
}

func wantRows(t *testing.T, label string, got []string, want ...string) {
	t.Helper()
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("%s\n--- got\n%s\n--- want\n%s", label, strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestMarkerOptions(t *testing.T) {
	root := buildRepo(t, map[string]string{
		"a.txt":              "x\n",
		"p1/a.txt":           "x\n",
		"p1/sub/b.x":         "x\n",
		"p2/q.x":             "x\n",
		"p2/r.x":             "x\n",
		"p3/m/init.pp":       "x\n",
		"p3/m/other.pp":      "x\n",
		"p4/init.pp":         "x\n",
		"deep/x/y/a.txt":     "x\n",
		"deep/x/a.txt":       "x\n",
		"skip/me/a.txt":      "x\n",
		"u/top/a.txt":        "x\n",
		"u/a.txt":            "x\n",
		"u/top/inner/b.x":    "x\n",
		"u/other/deeper/b.x": "x\n",
		"p5/README.md":       "x\n",
		"p5/a.txt":           "",
		"p6/c.x":             "x\n",
		"p6/README.md/inner": "x\n",
	}, nil)
	cfg := loadSrc(t, `recipes = []
[[kind]]
name = 'all'
marker = ['a.txt', '*.x', 'm/init.pp']
exclude = ['skip/*']
preview = ['README.md', 'a.txt']

[[kind]]
name = 'top'
marker = ['a.txt', '*.x', 'm/init.pp']
min_depth = 1
nested = false

[[kind]]
name = 'under'
marker = ['a.txt', '*.x']
under = 'u'
min_depth = 1
nested = false
`)
	gen := func(k string) []rows.Row { return Generate(cfg, root, []string{k}, nil) }
	wantRows(t, "all", brief(gen("all"), root),
		"a.txt|.|./",
		"x|deep|deep/x/",
		"y|deep/x|deep/x/y/",
		"p1|.|p1/",
		"sub|p1|p1/sub/",
		"p2|.|p2/",
		"p3|.|p3/",
		"p5|.|p5/",
		"p6|.|p6/",
		"u|.|u/",
		"deeper|u/other|u/other/deeper/",
		"top|u|u/top/",
		"inner|u/top|u/top/inner/",
	)
	wantRows(t, "min_depth 1 drops the root, so it cannot swallow every match below it", brief(gen("top"), root),
		"x|deep|deep/x/",
		"p1|.|p1/",
		"p2|.|p2/",
		"p3|.|p3/",
		"p5|.|p5/",
		"p6|.|p6/",
		"me|skip|skip/me/",
		"u|.|u/",
	)
	wantRows(t, "under counts depth from under", brief(gen("under"), root),
		"deeper|other|u/other/deeper/",
		"top|.|u/top/",
	)
	for _, r := range gen("all") {
		switch r.Name {
		case "p5":
			if r.Preview != root+"/p5/README.md" {
				t.Errorf("p5 preview = %s", r.Preview)
			}
		case "p6":
			if r.Preview != root+"/p6/README.md" {
				t.Errorf("a literal preview candidate is -s, so a dir wins: %s", r.Preview)
			}
		}
	}
}

func TestSourcesInOrder(t *testing.T) {
	root := buildRepo(t, map[string]string{"b/one/f": "x\n", "a/c/m": "x\n", "z.yaml": "x\n"}, nil)
	cfg := loadSrc(t, `recipes = []
[[kind]]
name = 'k'
  [[kind.source]]
  files = ['*.yaml']
  [[kind.source]]
  dirs = ['b']
  [[kind.source]]
  marker = 'm'
`)
	rs := Generate(cfg, root, []string{"k"}, nil)
	wantRows(t, "rows come out source by source", brief(rs, root), "z.yaml|.|z.yaml", "one|b|b/one/", "c|a|a/c/")
	for _, r := range rs {
		if r.Kind != "k" {
			t.Errorf("a source's rows carry the kind's name: %+v", r)
		}
	}
}

func TestDirSkipAndPreview(t *testing.T) {
	root := buildRepo(t, map[string]string{
		"target/x": "x\n", "tmp/x": "x\n", "build/x": "x\n", "docs/README.md": "x\n", "docs/guide.md": "x\n", "src/CLAUDE.md": "x\n",
		".github/x": "x\n", ".vscode/x": "x\n",
	}, nil)
	def := loadSrc(t, "recipes = ['dir']\n")
	wantRows(t, "default skip", brief(Generate(def, root, []string{"dir"}, nil), root), "<root>|-|./", ".github|-|.github/", "build|-|build/", "docs|-|docs/", "src|-|src/")
	bare := loadSrc(t, "recipes = []\n[[kind]]\nname = 'dir'\nbuiltin = 'dir'\n")
	wantRows(t, "an imported dir kind keeps 0.3.1's skip", brief(Generate(bare, root, []string{"dir"}, nil), root),
		"<root>|-|./", ".github|-|.github/", ".vscode|-|.vscode/", "build|-|build/", "docs|-|docs/", "src|-|src/")
	cfg := loadSrc(t, "recipes = ['dir']\n[[kind]]\nname = 'dir'\nextend = true\nskip = ['b*', '.*']\npreview = ['guide.md']\n")
	rs := Generate(cfg, root, []string{"dir"}, nil)
	wantRows(t, "skip replaces the default, and takes globs", brief(rs, root), "<root>|-|./", "docs|-|docs/", "src|-|src/", "target|-|target/", "tmp|-|tmp/")
	if rs[1].Preview != root+"/docs/guide.md" || rs[2].Preview != root+"/src" {
		t.Errorf("a declared preview replaces README.md, README, CLAUDE.md: %s %s", rs[1].Preview, rs[2].Preview)
	}
}

// TestRecipes runs every shipped recipe over a repo shaped for it, each with a false positive it must reject.
func TestRecipes(t *testing.T) {
	root := buildRepo(t, map[string]string{
		"package.json":                                     "{}\n",
		"packages/api/package.json":                        "{}\n",
		"packages/web/package.json":                        "{}\n",
		"packages/web/examples/demo/package.json":          "{}\n",
		"node_modules/left-pad/package.json":               "{}\n",
		"lib/vendor/dep/go.mod":                            "x\n",
		".github/actions/lint/Dockerfile":                  "x\n",
		"services/billing/go.mod":                          "x\n",
		"services/billing/Dockerfile":                      "x\n",
		"services/billing/testdata/m/go.mod":               "x\n",
		"dotnet/App.sln":                                   "x\n",
		"dotnet/src/App.csproj":                            "x\n",
		"dotnet/tests/App.Tests.csproj":                    "x\n",
		"docs/Makefile":                                    "x\n",
		"terragrunt.hcl":                                   "x\n",
		"live/prod/vpc/terragrunt.hcl":                     "x\n",
		"live/prod/vpc/.terragrunt-cache/h/terragrunt.hcl": "x\n",
		"modules/net/main.tf":                              "x\n",
		"modules/net/examples/basic/main.tf":               "x\n",
		"modules/db/variables.tf":                          "x\n",
		"charts/web/Chart.yaml":                            "x\n",
		"charts/web/charts/redis/Chart.yaml":               "x\n",
		"fns/thumbs/serverless.yml":                        "x\n",
		"sam/app/template.yaml":                            "x\n",
		"site/modules/ntp/manifests/init.pp":               "x\n",
		"catalog-info.yaml":                                "metadata:\n  name: whole-repo\n",
		"services/billing/catalog-info.yaml":               "metadata:\n  name: billing-svc\n",
		"README.md":                                        "x\n",
	}, nil)
	cfg := config.New()
	if err := cfg.Apply("recipes = "+tomlList(config.Recipes())+"\n", "test.toml", true); err != nil {
		t.Fatal(err)
	}
	want := map[string][]string{
		"project":    {"docs|.|docs/", "dotnet|.|dotnet/", "api|packages|packages/api/", "web|packages|packages/web/", "billing|services|services/billing/"},
		"tg":         {"vpc|live/prod|live/prod/vpc/"},
		"mod":        {"db|modules|modules/db/", "net|modules|modules/net/"},
		"helm":       {"web|charts|charts/web/", "redis|charts/web/charts|charts/web/charts/redis/"},
		"serverless": {"thumbs|fns|fns/thumbs/", "app|sam|sam/app/"},
		"puppet":     {"ntp|site/modules|site/modules/ntp/"},
		"backstage":  {"whole-repo|.|catalog-info.yaml", "billing-svc|services/billing|services/billing/catalog-info.yaml"},
	}
	for kind, w := range want {
		var stderr bytes.Buffer
		wantRows(t, kind, brief(Generate(cfg, root, []string{kind}, &stderr), root), w...)
		if stderr.Len() > 0 {
			t.Errorf("%s stderr: %s", kind, stderr.String())
		}
	}
	if d := strings.Join(cfg.DefaultKinds(), " "); d != "dir project tg mod helm" {
		t.Errorf("defaults = %s", d)
	}
}

func tomlList(s []string) string {
	q := make([]string, len(s))
	for i, v := range s {
		q[i] = "'" + v + "'"
	}
	return "[" + strings.Join(q, ", ") + "]"
}

// plainRow is a row's columns with the padding and colour gone, so rows from two layouts compare.
func plainRow(line string) string {
	f := rows.Split(rows.StripANSI(line))
	return strings.Join(strings.Fields(f[0]), " ") + "\t" + strings.Join(f[1:], "\t")
}

func plainRows(lines []string) []string {
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		if l != "" {
			out = append(out, plainRow(l))
		}
	}
	return out
}

// TestHelmSourcesMatchZsh holds the four declarative helm sources to zsh hop's _hop_provider_helm.
// - The fixture holds all four families and the four known gap cases; every difference must be one of the gaps below.
func TestHelmSourcesMatchZsh(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skipf("zsh or hop %s not available", testfix.RefLayout)
	}
	root := buildRepo(t, map[string]string{
		"kubernetes/values/web/values.yaml":                   "x\n",
		"kubernetes/values/api/docs/playbooks.md":             "x\n",
		"kubernetes/values/api/values.yaml":                   "x\n",
		"kubernetes/values/umbrella/charts/sub/Chart.yaml":    "x\n",
		"kubernetes/values/loose/b.yml":                       "x\n",
		"kubernetes/values/loose/a.yaml":                      "",
		"kubernetes/values/bare/notes.txt":                    "x\n",
		"kubernetes/values/odd/Chart.yaml/inner":              "x\n",
		"kubernetes/values/odd/values.yaml":                   "x\n",
		"kubernetes/charts/top/Chart.yaml":                    "x\n",
		"kubernetes/charts/scaffold/inner/Chart.yaml":         "x\n",
		"kubernetes/charts/emptychart/Chart.yaml":             "",
		"kubernetes/charts/Chart.yaml":                        "x\n",
		"kubernetes/services/grp/app.yaml":                    "x\n",
		"kubernetes/services/grp/deeper/app2.yaml":            "x\n",
		"kubernetes/services/grp/tests/t.yaml":                "x\n",
		"kubernetes/services/root.yaml":                       "x\n",
		"cluster-apps/charts/cluster-apps/templates/one.yaml": "x\n",
		"cluster-apps/charts/cluster-apps/Chart.yaml":         "x\n",
		"services/billing/Chart.yaml":                         "x\n",
		"charts/legacy/values.yaml":                           "x\n",
	}, map[string]string{
		"kubernetes/services/grp/linked.yaml": "../../values/web",
	}, "kubernetes/services/grp/gone.yaml", "cluster-apps/charts/cluster-apps/templates/gone.yaml")
	cfg := config.New()
	if err := importer.LoadPreset(cfg, "helm"); err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	got := plainRows(rows.List(Generate(cfg, root, []string{"helm"}, &stderr), root, nil))
	out, err := testfix.Zsh("/dev/null", `_hop_generate "$1" helm`, nil, root)
	if err != nil {
		t.Fatal(err)
	}
	want := plainRows(strings.Split(out, "\n"))
	r := root + "/"
	gaps := map[string]string{
		// 1: an empty Chart.yaml is the builtin's preview; a marker source falls back to the dir.
		"zsh\tChart.yaml helm kubernetes/charts\t" + r + "kubernetes/charts\t" + r + "kubernetes/charts/Chart.yaml\tkubernetes/charts/":                                                                         "2",
		"go\tkubernetes/charts helm kubernetes/charts\t" + r + "kubernetes/charts\t" + r + "kubernetes/charts/Chart.yaml\tkubernetes/charts/":                                                                   "2",
		"zsh\temptychart helm kubernetes/charts\t" + r + "kubernetes/charts/emptychart\t" + r + "kubernetes/charts/emptychart/Chart.yaml\tkubernetes/charts/emptychart/":                                        "1",
		"go\temptychart helm kubernetes/charts\t" + r + "kubernetes/charts/emptychart\t" + r + "kubernetes/charts/emptychart\tkubernetes/charts/emptychart/":                                                    "1",
		"zsh\tgrp/gone helm kubernetes/services\t" + r + "kubernetes/services/grp\t" + r + "kubernetes/services/grp/gone.yaml\tkubernetes/services/grp/gone.yaml":                                               "3",
		"zsh\tgrp/linked helm kubernetes/services\t" + r + "kubernetes/services/grp\t" + r + "kubernetes/services/grp/linked.yaml\tkubernetes/services/grp/linked.yaml":                                         "3",
		"zsh\tgone helm cluster-apps\t" + r + "cluster-apps/charts/cluster-apps/templates\t" + r + "cluster-apps/charts/cluster-apps/templates/gone.yaml\tcluster-apps/charts/cluster-apps/templates/gone.yaml": "3",
		"zsh\todd helm kubernetes/values\t" + r + "kubernetes/values/odd\t" + r + "kubernetes/values/odd/values.yaml\tkubernetes/values/odd/":                                                                   "4",
		"go\todd helm kubernetes/values\t" + r + "kubernetes/values/odd\t" + r + "kubernetes/values/odd/Chart.yaml\tkubernetes/values/odd/":                                                                     "4",
	}
	diff := map[string]bool{}
	only := func(side string, a, b []string) {
		in := map[string]int{}
		for _, l := range b {
			in[l]++
		}
		for _, l := range a {
			if in[l] > 0 {
				in[l]--
				continue
			}
			diff[side+"\t"+l] = true
		}
	}
	only("zsh", want, got)
	only("go", got, want)
	var unexpected, missing []string
	for d := range diff {
		if gaps[d] == "" {
			unexpected = append(unexpected, d)
		}
	}
	for g := range gaps {
		if !diff[g] {
			missing = append(missing, g)
		}
	}
	sort.Strings(unexpected)
	sort.Strings(missing)
	if len(unexpected) > 0 || len(missing) > 0 {
		t.Errorf("declarative helm vs _hop_provider_helm\n--- differences outside the known gaps\n%s\n--- known gaps that did not show\n%s",
			strings.Join(unexpected, "\n"), strings.Join(missing, "\n"))
	}
	if len(got) < 15 || stderr.Len() > 0 {
		t.Errorf("%d rows, stderr %q", len(got), stderr.String())
	}
}
