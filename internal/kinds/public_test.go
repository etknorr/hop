package kinds

import (
	"flag"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/config"
	"github.com/etknorr/hop/internal/rows"
)

var updatePublic = flag.Bool("update-public", false, "rewrite testdata/public goldens from this hop")

type publicRepo struct{ name, sha, kind string }

func publicRepos(t *testing.T) []publicRepo {
	t.Helper()
	b, err := os.ReadFile(testdata("repos.lock"))
	if err != nil {
		t.Fatal(err)
	}
	var out []publicRepo
	for _, line := range strings.Split(string(b), "\n") {
		f := strings.Split(line, "\t")
		if len(f) < 4 || strings.HasPrefix(line, "#") {
			continue
		}
		out = append(out, publicRepo{f[0], f[2], f[3]})
	}
	return out
}

// TestPublicRepos holds the zero-config set and each repo's own recipe to goldens a person has read.
// - testdata/fetch-repos.sh fetches the pinned commits; a repo not at its commit is skipped, never compared.
func TestPublicRepos(t *testing.T) {
	cfg := config.New()
	if err := cfg.Apply("recipes = ['dir', 'project', 'file', 'terragrunt', 'helm']\n", "public.toml", true); err != nil {
		t.Fatal(err)
	}
	zero := config.New()
	for _, r := range config.DefaultRecipes {
		zero.LoadRecipe(r)
	}
	for _, repo := range publicRepos(t) {
		t.Run(repo.name, func(t *testing.T) {
			root := testdata("repos/" + repo.name)
			head, err := exec.Command("git", "-C", root, "rev-parse", "HEAD").Output()
			if err != nil || strings.TrimSpace(string(head)) != repo.sha {
				t.Skipf("run testdata/fetch-repos.sh to fetch %s at %s", repo.name, repo.sha[:12])
			}
			for _, set := range []struct {
				label string
				cfg   *config.Config
				kinds []string
			}{{"default", zero, zero.DefaultKinds()}, {repo.kind, cfg, []string{repo.kind}}} {
				var b strings.Builder
				for _, l := range rows.List(Generate(set.cfg, root, set.kinds, os.Stderr), root, nil) {
					b.WriteString(strings.ReplaceAll(rows.StripANSI(l), root, "@ROOT@") + "\n")
				}
				golden := testdata(filepath.Join("public", repo.name+"."+set.label+".rows"))
				if *updatePublic {
					os.WriteFile(golden, []byte(b.String()), 0o644)
				}
				want, err := os.ReadFile(golden)
				if err != nil {
					t.Fatal(err)
				}
				if b.String() != string(want) {
					t.Errorf("%s rows differ from %s\n--- got\n%s", set.label, golden, b.String())
				}
			}
		})
	}
}
