package guard

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

func markAt(t *testing.T, p string, ago time.Duration) {
	t.Helper()
	at := float64(time.Now().Add(-ago).UnixMicro()) / 1e6
	if err := os.WriteFile(p, []byte(strconv.FormatFloat(at, 'f', 6, 64)), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestMarkAndCheck(t *testing.T) {
	p := filepath.Join(t.TempDir(), "mark")
	Mark(p)
	b, _ := os.ReadFile(p)
	if v, err := strconv.ParseFloat(string(b), 64); err != nil || time.Since(time.UnixMicro(int64(v*1e6))) > time.Second {
		t.Fatalf("mark writes a clock reading a check can compare against: %q", b)
	}
	if Check(p, 10) {
		t.Error("a verb landing inside the window is refused")
	}
	markAt(t, p, 2*time.Second)
	if !Check(p, 1) {
		t.Error("the same verb outside the window runs untouched")
	}
	markAt(t, p, 300*time.Millisecond)
	if Check(p, 0.5) || !Check(p+"x", 0.5) {
		t.Error("the window is a real threshold")
	}
	markAt(t, p, 300*time.Millisecond)
	if Check(p, 0.2) == false {
		t.Error("300 ms after a mark is outside a 200 ms window")
	}
}

func TestRearm(t *testing.T) {
	p := filepath.Join(t.TempDir(), "mark")
	markAt(t, p, 100*time.Millisecond)
	if Check(p, 0.15) {
		t.Fatal("refused inside the window")
	}
	time.Sleep(100 * time.Millisecond)
	if Check(p, 0.15) {
		t.Error("a refused verb pushes the window forward, so a long payload can't outlast it: 200 ms from the mark, 100 from the refusal")
	}
	markAt(t, p, time.Second)
	before, _ := os.ReadFile(p)
	if !Check(p, 0.15) {
		t.Fatal("outside the window")
	}
	if after, _ := os.ReadFile(p); string(after) != string(before) {
		t.Error("a verb that runs doesn't re-arm, so the chain ends at the first real keypress")
	}
}

func TestFailOpen(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "mark")
	if !Check(p, 10) {
		t.Error("no mark means no escape arrived, so the verb runs")
	}
	if !Check("", 10) {
		t.Error("no guard file at all fails open")
	}
	os.Mkdir(filepath.Join(dir, "unreadable"), 0o700)
	if !Check(filepath.Join(dir, "unreadable"), 10) {
		t.Error("an unreadable state file fails open")
	}
	for _, junk := range []string{"garbage", "1.2.3", "-5", "", "12abc"} {
		os.WriteFile(p, []byte(junk), 0o600)
		if !Check(p, 10) {
			t.Errorf("a corrupt mark %q fails open", junk)
		}
	}
	markAt(t, p, -time.Hour)
	if !Check(p, 10) {
		t.Error("a mark from the future fails open, so a backwards clock can't quarantine the verbs")
	}
	Mark(p)
	if !Check(p, 0) {
		t.Error("a window of 0 is the off switch")
	}
	Mark("")
}

func TestWindow(t *testing.T) {
	for raw, want := range map[string]float64{
		"": DefaultWindow, "0.3": 0.3, "1": 1, ".5": 0.5, "0": 0, "abc": DefaultWindow, "-1": DefaultWindow, "1e3": DefaultWindow, "0.1.2": DefaultWindow,
	} {
		if got := Window(raw); got != want {
			t.Errorf("Window(%q) = %v, want %v", raw, got, want)
		}
	}
}
