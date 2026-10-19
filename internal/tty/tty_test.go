package tty

import (
	"os"
	"testing"
)

func TestIs(t *testing.T) {
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	defer w.Close()
	if Is(r) || Is(w) {
		t.Error("a pipe is not a terminal")
	}
	if f, err := os.Open(os.DevNull); err == nil {
		defer f.Close()
		if Is(f) {
			t.Error("/dev/null is not a terminal")
		}
	}
	if Name() == "" {
		t.Error("no terminal device name")
	}
}
