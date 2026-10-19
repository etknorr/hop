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
	acts := []string{"cd", "open", "reveal", "cd+open", "cd+reveal"}
	c := func(words ...string) string {
		var w []string
		for _, l := range Complete(words, ks, acts) {
			w = append(w, l[:strings.IndexByte(l, '\t')])
		}
		return strings.Join(w, " ")
	}
	all := "-a --all -k --kinds -R --repos -w --workspaces -c --cwd --here -p --pick --cd -o --open -e --reveal --action= --no-vim --vim --doctor --doctor= -h --help -V -v --version"
	without := func(drop ...string) string {
		var out []string
		for _, f := range strings.Fields(all) {
			keep := true
			for _, d := range drop {
				keep = keep && f != d
			}
			if keep {
				out = append(out, f)
			}
		}
		return strings.Join(out, " ")
	}
	for _, x := range []struct{ words, want string }{
		{"-k|", "tg mod helm"},
		{"-k|m", "mod"},
		{"--kinds|tg,", "tg,mod tg,helm"},
		{"-k|tg,h", "tg,helm"},
		{"-k|tg,mod,", "tg,mod,helm"},
		{"--action=", "--action=cd --action=open --action=reveal --action=cd+open --action=cd+reveal"},
		{"--action=o", "--action=open"},
		{"--cd|--action=", ""},
		{"-o|--action=", ""},
		{"--doctor=", "--doctor=short"},
		{"--al", "--all"},
		{"", "/ - upgrade init import"},
		{"u", "upgrade"},
		{"-", "- " + all},
		{"-a|-", without("-a", "--all")},
		{"--here|-", without("-c", "--cwd", "--here")},
		{"-o|-", without("-o", "--open", "-e", "--reveal", "--action=")},
		{"-e|-", without("-o", "--open", "-e", "--reveal", "--action=")},
		{"--cd|-", without("--cd", "--action=")},
		{"--action=open|-", without("--cd", "-o", "--open", "-e", "--reveal", "--action=")},
		{"--vim|-", without("--vim", "--no-vim")},
		{"--no-vim|-", without("--vim", "--no-vim")},
		{"-p|-", without("-p", "--pick")},
		{"-V|-", ""},
		{"-h|-", ""},
		{"--doctor|-", ""},
		{"--doctor=short|-", ""},
		{"vpc|-", all},
		{"vpc|", ""},
		{"vpc|/", ""},
		{"--|-", ""},
		{"upgrade|-", "--check --dry-run -n -h --help"},
		{"upgrade|--check|-", "-h --help"},
		{"upgrade|-n|-", "-h --help"},
		{"upgrade|-h|-", ""},
		{"upgrade|", ""},
		{"init|", "zsh bash fish"},
		{"init|f", "fish"},
		{"init|zsh|-", "--cmd"},
		{"init|zsh|--cmd|", ""},
		{"init|zsh|--cmd|j|-", ""},
		{"import|-", "-o --force"},
		{"import|-o|", ""},
		{"import|--force|-", "-o"},
		{"vpc|pro", ""},
	} {
		words := strings.Split(x.words, "|")
		if got := c(words...); got != x.want {
			t.Errorf("Complete(%q)\n got %q\nwant %q", words, got, x.want)
		}
	}
	if got := Complete([]string{"-k", "h"}, ks, acts); len(got) != 1 || got[0] != "helm\tcharts" {
		t.Errorf("kinds carry their descriptions: %q", got)
	}
	v := Complete([]string{"-v"}, ks, acts)
	V := Complete([]string{"-V"}, ks, acts)
	if len(v) != 1 || len(V) != 1 || strings.Split(v[0], "\t")[1] != strings.Split(V[0], "\t")[1] {
		t.Errorf("-v is described exactly as -V: %q %q", v, V)
	}
}

// TestCompleteCoversEveryFlag is suite_completions' "every option hop parses has a completion spec", read off hop.go's option loop.
func TestCompleteCoversEveryFlag(t *testing.T) {
	src, err := os.ReadFile(filepath.Join("..", "..", "hop.go"))
	if err != nil {
		t.Fatal(err)
	}
	loop := string(src)
	if i := strings.Index(loop, "func parseHop("); i >= 0 {
		loop = loop[i:]
		if j := strings.Index(loop, "\n}\n"); j >= 0 {
			loop = loop[:j]
		}
	}
	have := map[string]bool{}
	for _, f := range hopFlags {
		for _, n := range f.names {
			have[n] = true
		}
	}
	n := 0
	for _, m := range regexp.MustCompile(`a == "(-[^"]*)"|HasPrefix\(a, "(--[a-z]+=)"\)`).FindAllStringSubmatch(loop, -1) {
		name := m[1] + m[2]
		if name == "--action" || name == "--" || name == "-" {
			continue
		}
		n++
		if !have[name] {
			t.Errorf("hop.go parses %s, which completion never offers", name)
		}
	}
	if n < 20 {
		t.Errorf("the scan found only %d options in hop.go, so it no longer reads the option loop", n)
	}
}

// TestInitSilent is suite_smoke's "sourcing in a non-interactive shell is silent": an rc file that prints breaks scp and rsync.
func TestInitSilent(t *testing.T) {
	for _, c := range []struct{ shell, argv0 string }{{"zsh", "zsh"}, {"bash", "bash"}, {"bash", "/bin/bash"}, {"fish", "fish"}} {
		if _, err := exec.LookPath(c.argv0); err != nil {
			t.Logf("%s not installed, skipped", c.argv0)
			continue
		}
		s, _ := Init(c.shell, "")
		f := filepath.Join(t.TempDir(), "init")
		os.WriteFile(f, []byte(s), 0o644)
		args := []string{"-c", ". " + f}
		if c.argv0 == "zsh" {
			args = append([]string{"-f"}, args...)
		}
		if c.argv0 == "fish" {
			args = []string{"--no-config", "-c", "source " + f}
		}
		if out, err := exec.Command(c.argv0, args...).CombinedOutput(); err != nil || len(out) != 0 {
			t.Errorf("%s: sourcing the init printed %q (%v)", c.argv0, out, err)
		}
	}
}
