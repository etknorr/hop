package shell

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestInitParses checks every script with each host shell's own parser; fish and pwsh are checked in docker by spike/shell/test/run-all.sh.
func TestInitParses(t *testing.T) {
	for _, c := range []struct {
		shell string
		argv  []string
	}{
		{"zsh", []string{"zsh", "-n"}},
		{"bash", []string{"bash", "-n"}},
		{"bash", []string{"/bin/bash", "-n"}},
		{"fish", []string{"fish", "-n"}},
	} {
		if _, err := exec.LookPath(c.argv[0]); err != nil {
			t.Logf("%s not installed, skipped", c.argv[0])
			continue
		}
		for _, cmd := range []string{"", "j"} {
			s, err := Init(c.shell, cmd, "/opt/it's/hopx")
			if err != nil {
				t.Fatal(err)
			}
			f := filepath.Join(t.TempDir(), "init")
			os.WriteFile(f, []byte(s), 0o644)
			if out, err := exec.Command(c.argv[0], append(c.argv[1:], f)...).CombinedOutput(); err != nil {
				t.Errorf("%v rejects init %s --cmd %q: %v %s", c.argv, c.shell, cmd, err, out)
			}
		}
	}
}

func TestInitText(t *testing.T) {
	for sh := range Shells {
		s, err := Init(sh, "jump", "/opt/it's/hopx")
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(s, "@CMD@") || strings.Contains(s, "@BIN@") {
			t.Errorf("%s: a placeholder survived", sh)
		}
		if !strings.Contains(s, "jump") {
			t.Errorf("%s: --cmd did not rename the function", sh)
		}
		var code []string
		for _, l := range strings.Split(s, "\n") {
			if !strings.HasPrefix(strings.TrimSpace(l), "#") {
				code = append(code, l)
			}
		}
		if body := strings.Join(code, "\n"); strings.Contains(body, "builtin cd") || strings.Contains(body, "eval") {
			t.Errorf("%s: never builtin cd and never eval", sh)
		}
	}
	ps, _ := Init("pwsh", "", "/opt/it's/hopx")
	if !strings.Contains(ps, "$global:__HopxBin = '/opt/it''s/hopx'") {
		t.Error("pwsh bakes in the binary path, single quotes doubled")
	}
	zs, _ := Init("zsh", "", "/x")
	if !strings.Contains(zs, "command hopx") || !strings.Contains(zs, "hopx() {") {
		t.Error("zsh defines hopx and reaches the binary with command")
	}
	for _, bad := range []string{"hop x", "a;b", "", "-x"} {
		if bad == "" {
			continue
		}
		if _, err := Init("zsh", bad, "/x"); err == nil {
			t.Errorf("--cmd %q must be refused", bad)
		}
	}
	if _, err := Init("tcsh", "", "/x"); err == nil {
		t.Error("tcsh is not supported")
	}
}

func TestComplete(t *testing.T) {
	ks := []Kind{{"tg", "units"}, {"mod", "modules"}, {"helm", "charts"}}
	acts := []string{"cd", "open"}
	c := func(words ...string) string {
		var w []string
		for _, l := range Complete(words, ks, acts) {
			w = append(w, l[:strings.IndexByte(l, '\t')])
		}
		return strings.Join(w, " ")
	}
	for _, x := range []struct{ words, want string }{
		{"-k|", "tg mod helm"},
		{"-k|m", "mod"},
		{"--kinds|tg,", "tg,mod tg,helm"},
		{"-k|tg,h", "tg,helm"},
		{"--action=|", ""},
		{"--action=o", "--action=open"},
		{"--al", "--all"},
		{"", "/ - init rows kinds config"},
		{"-", "- -a --all -k --kinds -c --here -R --repos -w --workspaces -p --pick --cd -o --open -e --reveal --action= -h -V"},
		{"init|f", "fish"},
		{"vpc|pro", ""},
	} {
		words := strings.Split(x.words, "|")
		if got := c(words...); got != x.want {
			t.Errorf("Complete(%q) = %q, want %q", words, got, x.want)
		}
	}
	if got := Complete([]string{"-k", "h"}, ks, acts); len(got) != 1 || got[0] != "helm\tcharts" {
		t.Errorf("kinds carry their descriptions: %q", got)
	}
}
