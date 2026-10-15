package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"

	"github.com/etknorr/hop/spike/hopx/internal/testfix"
)

// e2e is one end-to-end world: the match fixture repo, a throwaway HOME with two workspaces, and a built hopx.
type e2e struct {
	bin, root, home, ws, tmp string
	seed                     []byte
}

// history writes a fresh copy of the seeded history, so hop and hopx each start every run from the same MRU.
func (e *e2e) history(name string) string {
	p := filepath.Join(e.tmp, name)
	os.WriteFile(p, e.seed, 0o644)
	return p
}

func newE2E(t *testing.T) *e2e {
	t.Helper()
	if _, err := exec.LookPath("fzf"); err != nil {
		t.Skip("fzf not installed")
	}
	tmp := testfix.Resolved(t.TempDir())
	e := &e2e{bin: filepath.Join(tmp, "hopx"), root: filepath.Join(tmp, "repo"), home: filepath.Join(tmp, "home"), tmp: tmp}
	if out, err := exec.Command("go", "build", "-o", e.bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("go build: %v\n%s", err, out)
	}
	if err := testfix.BuildMatch(e.root); err != nil {
		t.Fatal(err)
	}
	for _, r := range []string{"strava/configuration", "strava/hop", "personal/notes", "personal/configuration-old", "personal/hop", "lit/deep"} {
		p := filepath.Join(e.home, r)
		os.MkdirAll(p, 0o755)
		if !strings.HasPrefix(r, "lit") {
			exec.Command("git", "-C", p, "init", "-q", "-b", "main").Run()
		}
	}
	e.ws = "strava-ws=" + e.home + "/strava:personal-ws=" + e.home + "/personal"
	e.seed = []byte(e.root + "/terraform/acct-infrastructure/env-prod/us-east-1/vpc\n" + e.root + "/kubernetes/values/thanos-legacy\n" + e.root + "/gone\n")
	return e
}

// detached runs a command in its own session, so it has no controlling terminal and /dev/tty fails as in cron.
func (e *e2e) detached(dir string, env []string, name string, args ...string) (stdout, stderr string, rc int) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append([]string{"HOME=" + e.home, "PATH=" + os.Getenv("PATH"), "LANG=en_US.UTF-8", "TMPDIR=" + e.tmp, "PWD=" + dir}, env...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	var o, er bytes.Buffer
	cmd.Stdout, cmd.Stderr = &o, &er
	err := cmd.Run()
	rc = 0
	if ee, ok := err.(*exec.ExitError); ok {
		rc = ee.ExitCode()
	} else if err != nil {
		rc = -1
	}
	return o.String(), er.String(), rc
}

type landing struct {
	stderr string
	rc     int
	pwd    string
}

// hop runs zsh hop's own hop() and reports where its shell ended up.
func (e *e2e) hop(t *testing.T, dir string, env []string, args []string) landing {
	t.Helper()
	q := make([]string, len(args))
	for i, a := range args {
		q[i] = "'" + strings.ReplaceAll(a, "'", `'\''`) + "'"
	}
	script := `source "$1/hop.zsh" || exit 97` + "\nhop " + strings.Join(q, " ") + "\nst=$?\nprint -r -- \"$st $PWD\""
	env = append([]string{"HOP_HISTFILE=" + e.history("hist-hop"), "HOP_CONFIG=" + testdata("match.zsh")}, env...)
	out, errs, _ := e.detached(dir, env, "zsh", "-f", "-c", script, "zsh", testfix.HopHome())
	st, pwd, _ := strings.Cut(strings.TrimSpace(out), " ")
	rc, _ := strconv.Atoi(st)
	return landing{errs, rc, pwd}
}

// hopx runs the built binary under the cmdfile protocol and applies the cd the shell function would.
func (e *e2e) hopx(t *testing.T, dir string, env []string, args []string) landing {
	t.Helper()
	cf := filepath.Join(e.tmp, "cmd")
	os.Remove(cf)
	env = append([]string{"HOPX_HISTFILE=" + e.history("hist-hopx"), "HOPX_CONFIG=" + testdata("match.toml"), "HOPX_CMDFILE=" + cf}, env...)
	out, errs, rc := e.detached(dir, env, e.bin, args...)
	if out != "" {
		t.Errorf("stdout must stay empty under the cmdfile protocol: %q", out)
	}
	pwd := dir
	if b, err := os.ReadFile(cf); err == nil {
		pwd = string(b)
	}
	return landing{errs, rc, pwd}
}

func testdata(p string) string { return filepath.Join(testfix.ModuleRoot(), "testdata", p) }

// TestHeadlessAgainstHop is suite_match's mt_headless cases and the four probe queries, run by hop and by hopx.
// - The same stderr, byte for byte, the same status, and the same final directory.
func TestHeadlessAgainstHop(t *testing.T) {
	if !testfix.HaveZsh() {
		t.Skip("zsh or hop.zsh not available")
	}
	e := newE2E(t)
	ws := "HOP_WORKSPACES=" + e.ws
	sp := "terraform/acct-security-tooling-prod"
	for _, tc := range []struct {
		dir  string
		env  []string
		args []string
	}{
		{e.root, nil, []string{"vpc"}},
		{e.root, nil, []string{"thanos"}},
		{e.root, nil, []string{"-p", "vpc"}},
		{e.root, nil, []string{"vpc", "prod"}},
		{e.root, nil, []string{"eks", "staging"}},
		{e.root, nil, []string{"acct", "sec", "tooling", "prod"}},
		{e.root, nil, []string{"eks", "security"}},
		{e.root, nil, []string{"-p", "eks", "security"}},
		{e.root, nil, []string{"security-tooling-prod"}},
		{e.root, nil, []string{"security_tooling_prod"}},
		{e.root, nil, []string{"routemaster-prod"}},
		{e.root, nil, []string{"securty-tooling-prod"}},
		{e.root, nil, []string{"kps", "zzqx"}},
		{e.root, nil, []string{"routemaxter", "kps", "zzqx"}},
		{e.root, nil, []string{"zzqx"}},
		{e.root, nil, []string{sp, "vpc"}},
		{e.root, nil, []string{"-p", sp}},
		{e.root, []string{"HOP_JUMP=never"}, []string{sp}},
		{e.root, []string{"HOP_JUMP=unique"}, []string{"security-tooling-prod"}},
		{e.root, nil, []string{"Terraform/ACCT-Security-Tooling-Prod"}},
		{e.root, nil, []string{"~/lit/deep"}},
		{e.root + "/terraform", nil, []string{e.home + "/lit/deep"}},
		{e.root + "/terraform/acct-infrastructure", nil, []string{"-c", "vpc"}},
		{e.root + "/terraform/acct-l[a]b*#", nil, []string{"-c", "env-prod"}},
		{e.root, nil, []string{"/"}},
		{e.root, nil, []string{"-k", "mesos,sbx", "abg"}},
		{e.root, nil, []string{"-a", "aws-config"}},
		{e.root, []string{ws}, []string{"-w", "strava"}},
		{e.root, []string{ws}, []string{"-w", "ws"}},
		{e.home, []string{ws}, []string{"configuration"}},
		{e.home, []string{ws}, []string{"personal", "configuration"}},
		{e.root, []string{ws}, []string{"-R", "configuration"}},
		{e.root, []string{ws}, []string{"-R", "hop"}},
		{e.home, []string{ws}, []string{"zzqx"}},
		{e.root, []string{ws}, []string{"-R", "strava/conf"}},
		{e.root, []string{ws}, []string{"-R", sp}},
		{e.home, []string{ws}, []string{"lit/deep"}},
	} {
		name := strings.Join(tc.args, " ") + " from " + strings.TrimPrefix(tc.dir, e.tmp+"/")
		t.Run(name, func(t *testing.T) {
			want := e.hop(t, tc.dir, tc.env, tc.args)
			got := e.hopx(t, tc.dir, tc.env, tc.args)
			if got.rc != want.rc || got.pwd != want.pwd {
				t.Errorf("hopx: rc %d at %s\n hop: rc %d at %s", got.rc, got.pwd, want.rc, want.pwd)
			}
			if got.stderr != want.stderr {
				t.Errorf("stderr differs\n--- hopx\n%s--- hop\n%s", got.stderr, want.stderr)
			}
			hh, _ := os.ReadFile(filepath.Join(e.tmp, "hist-hop"))
			hx, _ := os.ReadFile(filepath.Join(e.tmp, "hist-hopx"))
			if !bytes.Equal(hh, hx) {
				t.Errorf("history differs\n--- hopx\n%s--- hop\n%s", hx, hh)
			}
		})
	}
}

func TestHeadlessRemembersAndPrints(t *testing.T) {
	e := newE2E(t)
	hist := filepath.Join(e.tmp, "h2")
	env := []string{"HOPX_HISTFILE=" + hist, "HOPX_CONFIG=" + testdata("match.toml")}
	out, _, rc := e.detached(e.root, env, e.bin, "eks", "security")
	want := e.root + "/terraform/acct-security-tooling-prod/env-prod/us-east-1/eks"
	if rc != 0 || out != want+"\n" {
		t.Errorf("without a cmdfile the dir goes to stdout: rc %d %q", rc, out)
	}
	if b, _ := os.ReadFile(hist); string(b) != want+"\n" {
		t.Errorf("history %q", b)
	}
	cf := filepath.Join(e.tmp, "taken")
	os.WriteFile(cf, nil, 0o600)
	_, errs, rc := e.detached(e.root, append(env, "HOPX_CMDFILE="+cf), e.bin, "eks", "security")
	if rc != 1 || !strings.Contains(errs, "cannot write the cd file") {
		t.Errorf("an existing cmdfile is never overwritten: rc %d %q", rc, errs)
	}
}
