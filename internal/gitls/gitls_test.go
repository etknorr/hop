package gitls

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
)

// specs are every pathspec shape hop's presets, builtins and configs pass, plus wildmatch edge cases.
var specs = []string{
	"svc/", "svc", "sv", "infra/**/terragrunt.hcl", "**/terragrunt.hcl", "terragrunt.hcl",
	"cfg/*/conf/*/*", "cfg/**", "ents/*", "backstage/*.yaml", "**", "*", "*.md", "odd/**",
	":(glob)kubernetes/charts/**/Chart.yaml", ":(glob)kubernetes/services/**/*.yaml",
	":(glob)cluster-apps/charts/cluster-apps/templates/*.yaml", "odd/brack[1]/f", "odd/brack[[]1]/f",
	"odd/[!b]*/f", "odd/[a-c]*/*", "[.]rootdot", "svc/?lpha/*", "svc/**/f", "svc/a**", "infra/**",
	"kubernetes/**/", "dir with space/*/file", "svc/b**/f", "**f", "svc/**f", "sv**", "*/f", "odd/trail-space-bs\\\\ /f", "svc/*/*/f", "**/*.y*ml",
}

func gitMatch(t *testing.T, root, spec string) []string {
	t.Helper()
	if !strings.HasPrefix(spec, ":") {
		spec = ":(glob)" + spec
	}
	out, err := exec.Command("git", "-C", root, "ls-files", "-z", "--cached", "--", spec).Output()
	if err != nil {
		t.Fatalf("git ls-files %s: %v", spec, err)
	}
	var res []string
	for _, p := range bytes.Split(out, []byte{0}) {
		if len(p) > 0 {
			res = append(res, string(p))
		}
	}
	return res
}

func TestMatchAgreesWithGit(t *testing.T) {
	root := filepath.Join(t.TempDir(), "repo")
	if err := testfix.Build(root); err != nil {
		t.Fatal(err)
	}
	ix, err := List(root)
	if err != nil {
		t.Fatal(err)
	}
	if want := gitMatch(t, root, "**"); strings.Join(ix.Paths, "\n") != strings.Join(want, "\n") {
		t.Fatalf("List differs from git ls-files")
	}
	for _, s := range specs {
		got, err := ix.Match(s)
		if err != nil {
			t.Errorf("%s: %v", s, err)
			continue
		}
		if want := gitMatch(t, root, s); strings.Join(got, "\n") != strings.Join(want, "\n") {
			t.Errorf("pathspec %q\n got  %q\n want %q", s, got, want)
		}
	}
	got, _ := ix.Match("ents/*", "backstage/*.yaml")
	if len(got) != 7 || got[0] != "backstage/one.yaml" {
		t.Errorf("several specs must come back once each, in index order: %q", got)
	}
}

func TestListFailure(t *testing.T) {
	if _, err := List(t.TempDir()); err == nil || !strings.Contains(err.Error(), "git ls-files failed in") {
		t.Errorf("want a git failure, got %v", err)
	}
	if _, err := Compile(":(icase)x"); err == nil {
		t.Error("unsupported magic must be an error")
	}
}
