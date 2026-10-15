//go:build darwin || linux

package ptytest

import (
	"os/exec"
	"testing"
	"time"
)

func TestTerm(t *testing.T) {
	c := exec.Command("/bin/sh", "-c", `[ -t 0 ] && [ -t 2 ] && echo tty-ok; stty size; read x; echo "got:$x"; exit 4`)
	term, err := Start(c, 30, 100)
	if err != nil {
		t.Fatal(err)
	}
	if !term.WaitFor(`tty-ok\s+30 100`, 5*time.Second) {
		t.Fatalf("no terminal or wrong size: %q", term.Plain())
	}
	term.Send("hello\r")
	if !term.WaitFor(`got:hello`, 5*time.Second) {
		t.Errorf("typed input lost: %q", term.Plain())
	}
	if rc := term.Wait(5 * time.Second); rc != 4 {
		t.Errorf("exit status %d", rc)
	}
}
