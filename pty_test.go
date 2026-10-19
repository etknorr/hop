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

// picker is a built hopx on the match fixture, run under a real pty the way a shell function would run it.
type picker struct {
	bin, root, tmp, stub string
}

func newPicker(t *testing.T) *picker {
	t.Helper()
	if _, err := exec.LookPath("fzf"); err != nil {
		t.Skip("fzf not installed")
	}
	tmp := testfix.Resolved(t.TempDir())
	p := &picker{bin: os.Getenv("HOPX_TEST_BIN"), root: filepath.Join(tmp, "repo"), tmp: tmp, stub: filepath.Join(tmp, "stub")}
	if p.bin == "" {
		p.bin = filepath.Join(tmp, "hopx")
		if out, err := exec.Command("go", "build", "-o", p.bin, ".").CombinedOutput(); err != nil {
			t.Fatalf("go build: %v\n%s", err, out)
		}
	}
	if err := testfix.BuildMatch(p.root); err != nil {
		t.Fatal(err)
	}
	os.Mkdir(p.stub, 0o755)
	os.WriteFile(filepath.Join(p.stub, "pbcopy"), []byte("#!/bin/sh\ncat >\""+tmp+"/clip\"\n"), 0o755)
	return p
}

type outcome struct {
	rc            int
	cd, clip, out string
}

// run starts hopx with args on a 40x140 pty, lets drive type at it, and reports where it would have landed.
func (p *picker) run(t *testing.T, shell string, drive func(*ptytest.Term) bool, args ...string) outcome {
	t.Helper()
	cf := filepath.Join(p.tmp, "cmd")
	os.Remove(cf)
	os.Remove(filepath.Join(p.tmp, "clip"))
	// A remembered row would already be selected, so its preview would never redraw for typeAnd to see.
	os.Remove(filepath.Join(p.tmp, "hist"))
	c := exec.Command(p.bin, args...)
	c.Dir = p.root
	c.Env = []string{
		"PATH=" + p.stub + ":" + os.Getenv("PATH"), "HOME=" + p.tmp, "TMPDIR=" + p.tmp, "PWD=" + p.root, "LANG=en_US.UTF-8", "TERM=xterm-256color",
		"SHELL=" + shell, "HOPX_CONFIG=" + testdata("match.toml"), "HOPX_HISTFILE=" + filepath.Join(p.tmp, "hist"), "HOPX_CMDFILE=" + cf,
		"HOP_FZF_HEIGHT=", "FZF_DEFAULT_OPTS=", "HOP_CODE=" + filepath.Join(p.tmp, "no-code"),
	}
	term, err := ptytest.Start(c, 40, 140)
	if err != nil {
		t.Fatal(err)
	}
	if !term.WaitFor(`hopx ▸`, 10*time.Second) {
		t.Fatalf("the picker never drew its prompt:\n%s", term.Plain())
	}
	if !drive(term) {
		term.Send("\x03")
		term.Wait(5 * time.Second)
		t.Errorf("screen did not reach the expected state; drawn since the last key:\n%q", lastScreen(term.Since()))
		return outcome{rc: -2}
	}
	o := outcome{rc: term.Wait(10 * time.Second), out: term.Plain()}
	b, _ := os.ReadFile(cf)
	o.cd = string(b)
	b, _ = os.ReadFile(filepath.Join(p.tmp, "clip"))
	o.clip = string(b)
	return o
}

func lastScreen(s string) string {
	if len(s) > 3000 {
		return s[len(s)-3000:]
	}
	return s
}

func pickerShells(t *testing.T) []string {
	if v := os.Getenv("HOPX_TEST_SHELLS"); v != "" {
		return strings.Fields(v)
	}
	shells := []string{"/bin/sh"}
	if z, err := exec.LookPath("zsh"); err == nil {
		shells = append(shells, z)
	}
	return shells
}

// TestPicker drives the real fzf through each key the spec names, once per $SHELL, since every callback goes through `hopx __sh`.
func TestPicker(t *testing.T) {
	p := newPicker(t)
	raster := p.root + "/terraform/acct-map-platform-prod/env-prod/us-east-1/raster-catalogue"
	legacy := p.root + "/kubernetes/values/thanos-legacy"
	wait := func(re string) func(*ptytest.Term) bool {
		return func(tm *ptytest.Term) bool { return tm.WaitFor(re, 10*time.Second) }
	}
	// The row's preview is the settle signal: tcell repaints only changed cells, so an info line like 1/27 may never be drawn whole.
	shows := map[string]string{"raster": `raster-catalogue/terragrunt\.hcl`, "thanos-legacy": `thanos-legacy/values\.yaml`}
	typeAnd := func(query, key string) func(*ptytest.Term) bool {
		return func(tm *ptytest.Term) bool {
			tm.Send(query)
			if !wait(shows[query])(tm) {
				return false
			}
			tm.Send(key)
			return true
		}
	}
	for _, sh := range pickerShells(t) {
		t.Run(filepath.Base(sh), func(t *testing.T) {
			if o := p.run(t, sh, typeAnd("raster", "\r")); o.rc != 0 || o.cd != raster {
				t.Errorf("enter: rc %d cd %q", o.rc, o.cd)
			}
			if o := p.run(t, sh, typeAnd("raster", "\x19")); o.rc != 0 || o.clip != raster || o.cd != "" || !strings.Contains(o.out, "hop: copied "+raster) {
				t.Errorf("ctrl-y: rc %d clip %q cd %q", o.rc, o.clip, o.cd)
			}
			if o := p.run(t, sh, func(tm *ptytest.Term) bool { tm.Send("\x1b"); return true }); o.rc != 130 || o.cd != "" {
				t.Errorf("esc: rc %d cd %q, want 130 and no cd", o.rc, o.cd)
			}
			preview := func(tm *ptytest.Term) bool {
				tm.Send("routemaster")
				if !wait(`routemaster/terragrunt\.hcl\s+─+\s+include \{\}`)(tm) {
					return false
				}
				tm.Send("\x1b")
				return true
			}
			if o := p.run(t, sh, preview); o.rc != 130 {
				t.Errorf("preview: rc %d", o.rc)
			}
			menu := func(tm *ptytest.Term) bool {
				tm.Send("\x1bk")
				if !wait(`KINDS`)(tm) {
					return false
				}
				tm.Send("helm")
				if !wait(`helm\s+\d+\s+helm charts`)(tm) {
					return false
				}
				tm.Send("\r")
				// The reload is asynchronous, so the helm rows themselves are what says the switch landed.
				if !wait(`hopx ▸[\s\S]*kubernetes/values/thanos-legacy`)(tm) {
					return false
				}
				return typeAnd("thanos-legacy", "\r")(tm)
			}
			if o := p.run(t, sh, menu); o.rc != 0 || o.cd != legacy {
				t.Errorf("alt-k menu to helm: rc %d cd %q", o.rc, o.cd)
			}
			reload := func(tm *ptytest.Term) bool {
				tm.Send("\x1ba")
				// Every kind's rows sort the helm ones below the fold on Linux, so the redrawn count is the signal.
				if !wait(`\d+/\d+`)(tm) {
					return false
				}
				return typeAnd("thanos-legacy", "\r")(tm)
			}
			if o := p.run(t, sh, reload); o.rc != 0 || o.cd != legacy {
				t.Errorf("alt-a reload to every kind: rc %d cd %q", o.rc, o.cd)
			}
			ordered := func(tm *ptytest.Term) bool {
				if !wait(`ignored: zzqx`)(tm) {
					return false
				}
				tm.Send("\r")
				return true
			}
			if o := p.run(t, sh, ordered, "raster", "zzqx"); o.rc != 0 || o.cd != raster {
				t.Errorf("a relaxed pick opens ordered with its note: rc %d cd %q", o.rc, o.cd)
			}
		})
	}
}
