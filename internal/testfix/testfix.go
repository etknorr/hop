// Package testfix builds the fixture git repo the engine tests and goldens run against.
package testfix

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// files maps a repo path to its content; "" is a zero-byte file, which hop never previews.
var files = map[string]string{
	".rootdot":       "x\n",
	"README.md":      "x\n",
	"terragrunt.hcl": "x\n",

	"cfg/app1/conf/role1/noext":      "x\n",
	"cfg/app1/conf/role1/prod.conf":  "x\n",
	"cfg/app2/conf/role.x/base.conf": "x\n",
	"cfg/app2/conf/role.x/plain":     "x\n",

	"dir with space/sub/file": "x\n",

	"ents/a.yaml": "apiVersion: v1\nkind: Component\nmetadata:\n  annotations: {}\n  name: \"real-name\"\nspec:\n  owner: x\n",
	"ents/b.yaml": "metadata:\n  labels: {}\nspec:\n  name: wrong\n",
	"ents/c.yml":  "kind: X\nmetadata:\n  name: 'quoted'  \n",
	"ents/d.yaml": "metadata:\n  name: \n",
	"ents/e.yaml": "metadata:\n  name: last-line-no-newline",

	"infra/acct-a/env-prod/us-east-1/rbac/reader/B.tf":                                             "x\n",
	"infra/acct-a/env-prod/us-east-1/rbac/reader/terragrunt.hcl":                                   "x\n",
	"infra/acct-a/env-prod/us-east-1/vpc/.dot.tf":                                                  "x\n",
	"infra/acct-a/env-prod/us-east-1/vpc/B.tf":                                                     "x\n",
	"infra/acct-a/env-prod/us-east-1/vpc/_a.tf":                                                    "x\n",
	"infra/acct-a/env-prod/us-east-1/vpc/main.tf":                                                  "",
	"infra/acct-a/env-prod/us-east-1/vpc/provider_aws.tf":                                          "x\n",
	"infra/acct-a/env-prod/us-east-1/vpc/terragrunt.hcl":                                           "x\n",
	"infra/acct-a/policies/main.tf/inner":                                                          "x\n",
	"infra/acct-a/policies/terragrunt.hcl":                                                         "x\n",
	"infra/acct-b/x/y/z/terragrunt.hcl":                                                            "x\n",
	"infra/acct-platform-observability-shared/env-staging/us-west-2/eks/terragrunt.hcl":            "x\n",
	"infra/acct-c/env-playground-sandbox/eu-west-1/café-unit-with-a-very-long-name/terragrunt.hcl": "x\n",
	"infra/acct-c/env-dev/global/iam/main.tf":                                                      "x\n",
	"infra/acct-c/env-dev/global/iam/terragrunt.hcl":                                               "x\n",
	"infra/shared/terragrunt.hcl":                                                                  "x\n",
	"infra/terragrunt.hcl":                                                                         "x\n",

	"svc/.hidden/f":          "x\n",
	"svc/alpha/README.md":    "x\n",
	"svc/beta/deep/f":        "x\n",
	"svc/beta/deep/notes.md": "x\n",
	"svc/beta/.hid/a.md":     "x\n",
	"svc/café/f":             "x\n",
	"svc/dotted.d/f":         "x\n",
	"svc/empty/.gitkeep":     "",
	"svc/ns/one/f":           "x\n",
	"svc/ns/two/f":           "x\n",
	"svc/rootfile":           "x\n",

	"odd/brack[1]/f":          "x\n",
	"odd/trail-space-bs\\ /f": "x\n",
	"odd/skip-me":             "x\n",
	"odd/Upper.txt":           "x\n",
	"odd/lower.txt":           "x\n",

	"kubernetes/values/web/values.yaml":                   "x\n",
	"kubernetes/values/api/docs/playbooks.md":             "x\n",
	"kubernetes/values/api/values.yaml":                   "x\n",
	"kubernetes/values/umbrella/charts/sub/Chart.yaml":    "x\n",
	"kubernetes/values/loose/b.yml":                       "x\n",
	"kubernetes/values/loose/a.yaml":                      "",
	"kubernetes/values/loose/README.md":                   "x\n",
	"kubernetes/values/bare/notes.txt":                    "x\n",
	"kubernetes/charts/top/Chart.yaml":                    "x\n",
	"kubernetes/charts/scaffold/inner/Chart.yaml":         "x\n",
	"kubernetes/services/grp/app.yaml":                    "x\n",
	"kubernetes/services/grp/deeper/app2.yaml":            "x\n",
	"kubernetes/services/grp/tests/t.yaml":                "x\n",
	"kubernetes/services/root.yaml":                       "x\n",
	"cluster-apps/charts/cluster-apps/templates/one.yaml": "x\n",
	"cluster-apps/charts/cluster-apps/templates/two.yaml": "x\n",
	"cluster-apps/charts/cluster-apps/Chart.yaml":         "x\n",
	"services/billing/Chart.yaml":                         "x\n",
	"charts/legacy/values.yaml":                           "x\n",

	"backstage/one.yaml": "metadata:\n  name: one-entity\n",
	"backstage/two.yaml": "spec: {}\n",

	"target/out.bin": "x\n",
	"tmp/scratch":    "x\n",
}

// links are tracked symlinks: a preview glob must refuse one, and a literal candidate follows it.
var links = map[string]string{
	"infra/acct-a/env-prod/us-east-1/rbac/reader/A.tf": "B.tf",
	"sym/link": "../README.md",
}

// Build creates the fixture repo at dir, which must not exist or be empty.
func Build(dir string) error {
	for p, c := range files {
		full := filepath.Join(dir, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(full, []byte(c), 0o644); err != nil {
			return err
		}
	}
	for p, target := range links {
		full := filepath.Join(dir, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			return err
		}
		if err := os.Symlink(target, full); err != nil {
			return err
		}
	}
	git := func(args ...string) error {
		cmd := exec.Command("git", append([]string{"-C", dir, "-c", "core.quotepath=off"}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null")
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
		return nil
	}
	if err := git("init", "-q"); err != nil {
		return err
	}
	if err := git("add", "-A"); err != nil {
		return err
	}
	// A submodule gitlink is tracked but is not a file, so a files kind must skip it.
	return git("update-index", "--add", "--cacheinfo", "160000,1111111111111111111111111111111111111111,svc/gitlink")
}

// ModuleRoot is the repo root, found from this source file, so tests can reach testdata.
func ModuleRoot() string {
	_, f, _, _ := runtime.Caller(0)
	return filepath.Clean(filepath.Join(filepath.Dir(f), "..", ".."))
}

// HopHome is the checkout whose git objects hold the release tags, for `git -C` only; RefHome holds zsh hop itself.
func HopHome() string { return ModuleRoot() }

// HaveZsh reports whether zsh and the reference hop are both available for live comparisons.
// - It checks the unpacked release, not the worktree's hop.zsh, so live tests still run once the zsh files are gone.
func HaveZsh() bool {
	if _, err := exec.LookPath("zsh"); err != nil {
		return false
	}
	return RefHome(RefLayout) != ""
}

// RefLayout is the zsh hop release every live-zsh test is held to.
const RefLayout = "v0.3.1"

const refDone = ".hop-ref-complete"

// RefHome is hop at a release tag, unpacked once from the worktree's git objects into the temp dir.
// - It is "" when git or the tag is unavailable, so a test can skip rather than fail.
// - tar -m gives the files fresh mtimes, since macOS purges old files from the temp dir and leaves the directories.
func RefHome(tag string) string {
	out, err := exec.Command("git", "-C", HopHome(), "rev-parse", "--verify", "-q", tag+"^{commit}").Output()
	if err != nil {
		return ""
	}
	dir := filepath.Join(os.TempDir(), "hop-ref-"+tag+"-"+strings.TrimSpace(string(out))[:12])
	complete := func() bool {
		for _, f := range []string{refDone, "hop.zsh"} {
			if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
				return false
			}
		}
		return true
	}
	if complete() {
		return dir
	}
	tmp, err := os.MkdirTemp(os.TempDir(), "hop-ref-")
	if err != nil {
		return ""
	}
	defer os.RemoveAll(tmp)
	archive := exec.Command("git", "-C", HopHome(), "archive", "--format=tar", tag)
	untar := exec.Command("tar", "-x", "-m", "-C", tmp)
	if untar.Stdin, err = archive.StdoutPipe(); err != nil {
		return ""
	}
	if err := untar.Start(); err != nil {
		return ""
	}
	if err := archive.Run(); err != nil {
		return ""
	}
	if err := untar.Wait(); err != nil {
		return ""
	}
	if err := os.WriteFile(filepath.Join(tmp, refDone), nil, 0o644); err != nil {
		return ""
	}
	if os.Rename(tmp, dir) == nil || complete() {
		return dir
	}
	// Neither this process nor another left a whole copy, so what is there is a purged one.
	os.RemoveAll(dir)
	if os.Rename(tmp, dir) == nil || complete() {
		return dir
	}
	return ""
}

// Zsh sources the reference hop's hop.zsh with config cfg and runs script, passing args as $1.. after hop's own.
// - zsh -f and a scrubbed environment keep Eric's shell setup and real history out of every comparison.
func Zsh(cfg, script string, env []string, args ...string) (string, error) {
	home := RefHome(RefLayout)
	if home == "" {
		return "", fmt.Errorf("zsh hop %s is not available", RefLayout)
	}
	return ZshAt(home, cfg, script, env, args...)
}

// ZshAt is Zsh against the hop.zsh in home, such as a RefHome.
func ZshAt(home, cfg, script string, env []string, args ...string) (string, error) {
	full := `source "$HOP_HOME_X/hop.zsh" || exit 3` + "\n" + script
	cmd := exec.Command("zsh", append([]string{"-f", "-c", full, "zsh"}, args...)...)
	cmd.Env = append([]string{
		"HOME=" + os.Getenv("HOME"), "PATH=" + os.Getenv("PATH"), "LANG=en_US.UTF-8",
		"TMPDIR=" + os.TempDir(), "HOP_HISTFILE=/dev/null", "HOP_CONFIG=" + cfg, "HOP_HOME_X=" + home,
	}, env...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return string(out), fmt.Errorf("zsh: %v: %s", err, stderr.String())
	}
	return string(out), nil
}
