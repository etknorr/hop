package testfix

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// matchFiles is tests/lib/fixture.zsh's match_fixture, the resolver's repo: every rule in lib/match.zsh has a case needing it.
func matchFiles() map[string]string {
	tf := "resource \"null_resource\" \"x\" {}\n"
	inc := "include {}\n"
	sp := "terraform/acct-security-tooling-prod/env-prod/us-east-1"
	ss := "terraform/acct-security-tooling-staging/env-staging/us-east-1"
	ip := "terraform/acct-infrastructure/env-prod/us-east-1"
	f := map[string]string{
		"README.md": "# match fixture\n",
		"terraform/acct-security-tooling-prod/terragrunt_aws_account.hcl":                                  "locals {}\n",
		"terraform/acct-security-tooling-staging/README.md":                                                "# security tooling staging\n",
		"terraform/acct-infrastructure/env-dev/us-east-1/vpc/terragrunt.hcl":                               inc,
		"terraform/acct-operations-prod/env-prod/us-east-1/secrets/terragrunt.hcl":                         inc,
		"terraform/acct-data/env-prod/us-east-1/lake/terragrunt.hcl":                                       inc,
		"terraform/acct-data-platform-prod/env-prod/us-east-1/vpc/terragrunt.hcl":                          inc,
		"terraform/acct-trust-safety-restricted-prod/env-prod/us-east-1/restricted-storage/terragrunt.hcl": inc,
		"terraform/acct-l[a]b*#/env-prod/us-east-1/widget/terragrunt.hcl":                                  inc,
		"terraform/acct-map-platform-prod/env-prod/us-east-1/raster-catalogue/terragrunt.hcl":              inc,
		"terraform/cross_account_iam/terragrunt.hcl":                                                       "locals {}\n",
		"terraform/cross_account_iam/roles/terragrunt.hcl":                                                 inc,
		"terraform/modules/aws/aws-config/main.tf":                                                         "variable \"x\" {}\n",
		"modules/apt/README.md":                   "# apt\n",
		"mesos/services/routemaster/service.conf": "name = routemaster\n",
		"sandbox/abg/README.md":                   "# abg\n",
		"sandbox/alpha-beta-gamma/README.md":      "# alpha beta gamma\n",
	}
	for _, u := range []string{"vpc", "eks", "anthropic-compliance-poller"} {
		f[sp+"/"+u+"/terragrunt.hcl"] = inc
		f[sp+"/"+u+"/main.tf"] = tf
	}
	for _, u := range []string{"vpc", "upwind"} {
		f[ss+"/"+u+"/terragrunt.hcl"] = inc
	}
	for _, u := range []string{"secor", "secrets", "vpc", "routemaster", "trust", "active", "mesos"} {
		f[ip+"/"+u+"/terragrunt.hcl"] = inc
	}
	for _, u := range []string{"kube-prometheus-stack", "external-dns", "active", "thanos", "thanos-legacy"} {
		f["kubernetes/values/"+u+"/values.yaml"] = "image: " + u + "\n"
	}
	for _, u := range []string{"kube-prometheus-stack", "grafana", "grafana-dashboards"} {
		f["kubernetes/services/monitoring/"+u+".yaml"] = "kind: Application\n"
	}
	for _, u := range []string{"external-dns", "active"} {
		f["kubernetes/services/infrastructure/"+u+".yaml"] = "kind: Application\n"
	}
	return f
}

// BuildMatch creates the match fixture repo at dir and commits it, as match_fixture does.
func BuildMatch(dir string) error {
	for p, c := range matchFiles() {
		full := filepath.Join(dir, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(full, []byte(c), 0o644); err != nil {
			return err
		}
	}
	git := func(args ...string) error {
		cmd := exec.Command("git", append([]string{"-C", dir, "-c", "commit.gpgsign=false", "-c", "user.email=hopx@example.invalid", "-c", "user.name=hopx"}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null", "GIT_TEMPLATE_DIR=")
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
		return nil
	}
	if err := git("init", "-q", "-b", "main"); err != nil {
		return err
	}
	if err := git("add", "-A"); err != nil {
		return err
	}
	return git("commit", "-q", "-m", "match fixture")
}

// Resolved is dir with every symlink resolved, because git reports the physical root.
func Resolved(dir string) string {
	if r, err := filepath.EvalSymlinks(dir); err == nil {
		return r
	}
	return dir
}
