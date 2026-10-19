package collate

import (
	"os/exec"
	"slices"
	"strings"
	"testing"
)

var words = []string{
	"iPhone", "identifiers", "a_b", "a-b", "ab", "aB", "Ab", "a.b", "a1", "a10", "a2", "a b", "_x", "x-", "éa", "ea",
	"fa", "Z", "z", "#a", ".a", "Ab", "ac", "a", "A", "a_", "a0", "e", "é", "ê", "E", "É", "ss", "ß", "a~", "a$",
	"002\tscope,name...", "002\tscope,env", "004\tscope,env,region,name...", "R3", "r4", "wt-repo",
}

// want is the order zsh's (o) printed for words under en_US.UTF-8 on macOS 26.
var want = []string{
	"_x", ".a", "#a", "002\tscope,env", "002\tscope,name...", "004\tscope,env,region,name...", "a", "A", "a b", "a_",
	"a_b", "a-b", "a.b", "a~", "a$", "a0", "a1", "a10", "a2", "ab", "aB", "Ab", "Ab", "ac", "e", "E", "é", "É", "ê",
	"ea", "éa", "fa", "identifiers", "iPhone", "R3", "r4", "ss", "ß", "wt-repo", "x-", "z", "Z",
}

func TestSortMatchesRecordedZsh(t *testing.T) {
	got := slices.Clone(words)
	Sort(got)
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("Sort\n got  %q\n want %q", got, want)
	}
}

func TestSortMatchesLiveZsh(t *testing.T) {
	if _, err := exec.LookPath("zsh"); err != nil {
		t.Skip("zsh not available")
	}
	cmd := exec.Command("zsh", append([]string{"-f", "-c", `print -rl -- "${(@o)argv}"`, "zsh"}, words...)...)
	cmd.Env = []string{"LANG=en_US.UTF-8"}
	out, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	z := strings.Split(strings.TrimSuffix(string(out), "\n"), "\n")
	got := slices.Clone(words)
	Sort(got)
	if strings.Join(got, "|") != strings.Join(z, "|") {
		t.Errorf("Sort\n got  %q\n zsh  %q", got, z)
	}
}
