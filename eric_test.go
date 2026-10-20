//go:build darwin || linux

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/etknorr/hop/internal/ptytest"
	"github.com/etknorr/hop/internal/testfix"
)

// TestRealRepoPicker drives the picker on a real repo with eric.toml, logging query, key and outcome.
// - It runs only with HOP_PARITY_REPO set, and never writes outside its temp dir: history, clipboard, code and the editor are stubs.
func TestRealRepoPicker(t *testing.T) {
	repo := os.Getenv("HOP_PARITY_REPO")
	if repo == "" {
		t.Skip("set HOP_PARITY_REPO to a repo matching testdata/eric.toml, e.g. ~/strava/configuration")
	}
	if _, err := exec.LookPath("fzf"); err != nil {
		t.Skip("fzf not installed")
	}
	repo = testfix.Resolved(repo)
	tmp := testfix.Resolved(t.TempDir())
	bin := filepath.Join(tmp, "hop")
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("go build: %v\n%s", err, out)
	}
	stub := filepath.Join(tmp, "stub")
	os.Mkdir(stub, 0o755)
	log := filepath.Join(tmp, "log")
	os.WriteFile(filepath.Join(stub, "pbcopy"), []byte("#!/bin/sh\nprintf 'pbcopy %s' \"$(cat)\" >>\""+log+"\"\n"), 0o755)
	os.WriteFile(filepath.Join(stub, "code"), []byte("#!/bin/sh\necho \"code $*\" >>\""+log+"\"\n"), 0o755)
	os.WriteFile(filepath.Join(stub, "ed-stub"), []byte("#!/bin/sh\necho \"editor $*\" >>\""+log+"\"\n"), 0o755)

	type step struct {
		dir  string
		args []string
		env  []string
		keys []string
		want string
	}
	settle := func(tm *ptytest.Term) { tm.WaitFor(`\d+/\d+`, 3*time.Second); time.Sleep(400 * time.Millisecond) }
	for _, s := range []step{
		{"", nil, nil, []string{"/eks staging", "\r"}, ""},
		{"", []string{"eks", "staging"}, nil, []string{"\r"}, ""},
		{"", []string{"-p", "vpc", "prod"}, nil, []string{"\x1b[B", "\r"}, ""},
		{"", []string{"thanos"}, nil, []string{"\x19"}, ""},
		{"", nil, nil, []string{":", "/rules", "\r", "/heatmaps prime", "\r"}, ""},
		{"", nil, nil, []string{"\x1ba", "/playbook", "\r"}, ""},
		{"terraform/acct-security-tooling-prod", []string{"-c"}, nil, []string{"/vpc", "\r"}, ""},
		{"", []string{"--action=open", "eks", "staging"}, nil, []string{"\r"}, ""},
		{"", []string{"-k", "file", "-p", "atlantis.yaml"}, nil, []string{"\x0f"}, ""},
		{"", []string{"-p", "routemaster"}, []string{"VISUAL=" + filepath.Join(stub, "ed-stub")}, []string{"\x1bo"}, ""},
		{"", []string{"-w"}, nil, []string{"\x1b"}, ""},
		{"", nil, nil, []string{"h", "h", "\x1b"}, ""},
		{"", []string{"-R"}, nil, []string{"/configuration", "\x1b", "l", "/vpc prod", "\r"}, ""},
	} {
		os.Remove(log)
		cf := filepath.Join(tmp, "cmd")
		os.Remove(cf)
		c := exec.Command(bin, s.args...)
		c.Dir = filepath.Join(repo, s.dir)
		c.Env = append([]string{"PATH=" + stub + ":" + os.Getenv("PATH"), "HOME=" + testfix.RealHome, "TMPDIR=" + tmp, "PWD=" + c.Dir,
			"LANG=en_US.UTF-8", "TERM=xterm-256color", "SHELL=/bin/zsh", "HOP_CONFIG=" + testdata("eric.toml"),
			"HOP_HISTFILE=" + filepath.Join(tmp, "hist"), "HOP_CMDFILE=" + cf, "HOP_FZF_HEIGHT=", "FZF_DEFAULT_OPTS="}, s.env...)
		start := time.Now()
		term, err := ptytest.Start(c, 45, 160)
		if err != nil {
			t.Fatal(err)
		}
		drawn := term.WaitFor(`NORMAL|SEARCH|hop ▸`, 10*time.Second)
		first := time.Since(start)
		for _, k := range s.keys {
			if !drawn {
				break
			}
			settle(term)
			term.Send(k)
		}
		rc := term.Wait(10 * time.Second)
		cd, _ := os.ReadFile(cf)
		got, _ := os.ReadFile(log)
		keys := strings.NewReplacer("\r", "Enter", "\x1b[B", "Down ", "\x19", "ctrl-y", "\x1ba", "alt-a ", "\x0f", "ctrl-o", "\x1bo", "alt-o", "\x1b", "esc").Replace(strings.Join(s.keys, " "))
		out := strings.TrimSpace(strings.ReplaceAll(string(got), tmp, "$TMP"))
		if len(cd) > 0 {
			out = strings.TrimSpace("cd " + strings.TrimPrefix(string(cd), repo+"/") + "; " + out)
		}
		if !drawn {
			out = "no picker; " + out
		}
		t.Logf("| %s | `hop %s` | %s | rc %d: %s | %.0f ms |", orDot(s.dir), strings.Join(s.args, " "), keys, rc, out, float64(first.Microseconds())/1000)
	}
}

func orDot(s string) string {
	if s == "" {
		return "."
	}
	return s
}
