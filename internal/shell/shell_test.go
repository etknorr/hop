package shell

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// TestInitParses checks every script with each host shell's own parser; CI and test/shell/run-all.sh cover fish where the host lacks it.
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
			s, err := Init(c.shell, cmd)
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
	hash := Hash()
	if !regexp.MustCompile(`^[0-9a-f]{12}$`).MatchString(hash) {
		t.Fatalf("Hash() = %q", hash)
	}
	for _, sh := range Names {
		s, err := Init(sh, "jump")
		if err != nil {
			t.Fatal(err)
		}
		if regexp.MustCompile(`@[A-Z]+@`).MatchString(s) {
			t.Errorf("%s: a placeholder survived", sh)
		}
		if !strings.Contains(s, "jump") {
			t.Errorf("%s: --cmd did not rename the function", sh)
		}
		if strings.Contains(s, "hopr") || strings.Contains(s, "hopw") {
			t.Errorf("%s: hopr and hopw come only with the plain name", sh)
		}
		if !strings.Contains(s, "HOP_SHELL="+sh+" HOP_INIT_HASH="+hash+" command hop") {
			t.Errorf("%s: the call must export HOP_SHELL and HOP_INIT_HASH", sh)
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
		plain, _ := Init(sh, "")
		for _, f := range []string{"hopr", "hopw", "hop __hopw", "hop /"} {
			if !strings.Contains(plain, f) {
				t.Errorf("%s: plain init lacks %q", sh, f)
			}
		}
	}
	zs, _ := Init("zsh", "")
	if !strings.Contains(zs, "command hop") || !strings.Contains(zs, "hop() {") {
		t.Error("zsh defines hop and reaches the binary with command")
	}
	for _, bad := range []string{"hop x", "a;b", "-x"} {
		if _, err := Init("zsh", bad); err == nil {
			t.Errorf("--cmd %q must be refused", bad)
		}
	}
	for _, sh := range []string{"tcsh", "pwsh", "powershell"} {
		if _, err := Init(sh, ""); err == nil {
			t.Errorf("%s is not a 1.0 shell", sh)
		}
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
