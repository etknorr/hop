package debuglog

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/etknorr/hop/internal/testfix"
)

func TestMain(m *testing.M) { testfix.Main(m) }

func reset() { on, path = nil, "" }

func TestPrintfOnlyWhenOn(t *testing.T) {
	reset()
	log := filepath.Join(t.TempDir(), "sub", "debug.log")
	t.Setenv("HOP_DEBUG_LOG", log)
	t.Setenv("HOP_DEBUG", "")
	Printf("pick label=%s", "x")
	if _, err := os.Stat(log); err == nil {
		t.Fatal("HOP_DEBUG unset must write nothing")
	}
	t.Setenv("HOP_DEBUG", "1")
	Printf("pick label=%s rows=%d", "repo", 3)
	Printf("dispatch key=%s\nsecond", "enter")
	b, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	stamp := regexp.MustCompile(`^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d `)
	if len(lines) != 2 || !stamp.MatchString(lines[0]) || !strings.HasSuffix(lines[0], " pick label=repo rows=3") || !strings.HasSuffix(lines[1], `dispatch key=enter\nsecond`) {
		t.Errorf("log:\n%s", b)
	}
	if got := Tail(1); len(got) != 1 || !strings.HasSuffix(got[0], `\nsecond`) {
		t.Errorf("Tail(1) = %q", got)
	}
}

func TestConfigureBeatsEnv(t *testing.T) {
	defer reset()
	reset()
	t.Setenv("HOP_DEBUG", "")
	log := filepath.Join(t.TempDir(), "file.log")
	Configure(true, log)
	Printf("generate root=%s", "/r")
	if b, _ := os.ReadFile(log); !strings.Contains(string(b), "generate root=/r") {
		t.Errorf("Configure(true) must log to its file: %q", b)
	}
	Configure(false, log)
	t.Setenv("HOP_DEBUG", "1")
	if Enabled() {
		t.Error("Configure(false) decides over the env")
	}
}

func TestNeverFails(t *testing.T) {
	reset()
	dir := t.TempDir()
	block := filepath.Join(dir, "file")
	os.WriteFile(block, nil, 0o644)
	t.Setenv("HOP_DEBUG", "1")
	t.Setenv("HOP_DEBUG_LOG", filepath.Join(block, "debug.log"))
	Printf("resolve tier=%s", "T1")
	if Tail(15) != nil {
		t.Error("a log that can't exist has no tail")
	}
}

func TestDefaultPath(t *testing.T) {
	reset()
	t.Setenv("HOP_DEBUG_LOG", "")
	t.Setenv("XDG_STATE_HOME", "/st")
	if p := Path(); p != "/st/hop/debug.log" {
		t.Errorf("Path() = %q", p)
	}
	t.Setenv("XDG_STATE_HOME", "")
	t.Setenv("HOME", "/h")
	if p := Path(); p != "/h/.local/state/hop/debug.log" {
		t.Errorf("Path() = %q", p)
	}
}
