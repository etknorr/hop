package act

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCD(t *testing.T) {
	d := t.TempDir()
	hist := filepath.Join(d, "hist")
	target := filepath.Join(d, "with space")
	os.Mkdir(target, 0o755)

	t.Setenv("HOPX_CMDFILE", "")
	var out, errb bytes.Buffer
	if rc := CD(target, &out, &errb, hist, 300); rc != 0 || out.String() != target+"\n" {
		t.Errorf("no cmdfile prints the dir: rc %d %q", rc, out.String())
	}

	cf := filepath.Join(d, "cmd")
	t.Setenv("HOPX_CMDFILE", cf)
	out.Reset()
	if rc := CD(target, &out, &errb, hist, 300); rc != 0 || out.Len() != 0 {
		t.Fatalf("cmdfile: rc %d, stdout %q", rc, out.String())
	}
	b, _ := os.ReadFile(cf)
	st, _ := os.Stat(cf)
	if string(b) != target || st.Mode().Perm() != 0o600 {
		t.Errorf("cmdfile holds %q mode %v, want the bare path at 0600", b, st.Mode().Perm())
	}
	if rc := CD(target, &out, &errb, hist, 300); rc != 1 || !strings.Contains(errb.String(), "cannot write the cd file") {
		t.Errorf("an existing cmdfile is never reused: rc %d %q", rc, errb.String())
	}
	if h, _ := os.ReadFile(hist); string(h) != target+"\n" {
		t.Errorf("history %q", h)
	}

	errb.Reset()
	os.Remove(cf)
	if rc := CD(filepath.Join(d, "nope"), &out, &errb, hist, 300); rc != 1 || !strings.HasPrefix(errb.String(), "hop: not a directory: ") {
		t.Errorf("a missing dir: rc %d %q", rc, errb.String())
	}
	if _, err := os.Stat(cf); err == nil {
		t.Error("a failed cd must not leave a cmdfile")
	}
}
