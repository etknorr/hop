//go:build darwin || linux

// Package ptytest drives a program on a pseudo-terminal for tests, with no dependency past syscall.
package ptytest

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

// Term is a child on a pty: what it has drawn so far, and a way to type at it.
type Term struct {
	Cmd    *exec.Cmd
	master *os.File
	mu     sync.Mutex
	buf    bytes.Buffer
	mark   int
	done   chan struct{}
	err    error
}

type winsize struct{ Row, Col, X, Y uint16 }

// Start runs c with a pty as its controlling terminal and its stdin, stdout and stderr, at rows x cols.
func Start(c *exec.Cmd, rows, cols int) (*Term, error) {
	m, name, err := openPTY()
	if err != nil {
		return nil, err
	}
	s, err := os.OpenFile(name, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		m.Close()
		return nil, err
	}
	ws := winsize{Row: uint16(rows), Col: uint16(cols)}
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, s.Fd(), syscall.TIOCSWINSZ, uintptr(unsafe.Pointer(&ws))); e != 0 {
		m.Close()
		s.Close()
		return nil, fmt.Errorf("TIOCSWINSZ: %w", e)
	}
	c.Stdin, c.Stdout, c.Stderr = s, s, s
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: 0}
	if err := c.Start(); err != nil {
		m.Close()
		s.Close()
		return nil, err
	}
	s.Close()
	t := &Term{Cmd: c, master: m, done: make(chan struct{})}
	go func() {
		b := make([]byte, 32<<10)
		for {
			n, err := m.Read(b)
			t.mu.Lock()
			t.buf.Write(b[:n])
			t.mu.Unlock()
			if err != nil {
				break
			}
		}
	}()
	go func() {
		t.err = c.Wait()
		close(t.done)
	}()
	return t, nil
}

// Screen is everything the child has written, escape sequences included.
func (t *Term) Screen() string {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.buf.String()
}

// Plain is Screen with CSI and OSC sequences dropped, so text a renderer split with cursor moves still reads as words.
func (t *Term) Plain() string { return csi.ReplaceAllString(t.Screen(), "") }

var csi = regexp.MustCompile(`\x1b\[[0-9;?<>=]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][0-9A-Za-z]|\x1b[=>78]`)

// Since is the plain text drawn after the last Send, so a wait can't be satisfied by a stale frame.
func (t *Term) Since() string { return t.since() }

func (t *Term) since() string {
	t.mu.Lock()
	defer t.mu.Unlock()
	return csi.ReplaceAllString(string(t.buf.Bytes()[t.mark:]), "")
}

// WaitFor waits until what was drawn since the last Send matches re, the child exits, or the timeout passes.
func (t *Term) WaitFor(re string, timeout time.Duration) bool {
	r := regexp.MustCompile(re)
	end := time.Now().Add(timeout)
	for time.Now().Before(end) {
		if r.MatchString(t.since()) {
			return true
		}
		select {
		case <-t.done:
			return r.MatchString(t.since())
		case <-time.After(20 * time.Millisecond):
		}
	}
	return false
}

// Send types s at the terminal.
func (t *Term) Send(s string) {
	t.mu.Lock()
	t.mark = t.buf.Len()
	t.mu.Unlock()
	t.master.WriteString(s)
}

// Wait waits for the child to exit and returns its status, or -1 after the timeout, when it is killed.
func (t *Term) Wait(timeout time.Duration) int {
	select {
	case <-t.done:
	case <-time.After(timeout):
		t.Cmd.Process.Kill()
		<-t.done
		return -1
	}
	t.master.Close()
	if t.Cmd.ProcessState == nil {
		return -1
	}
	return t.Cmd.ProcessState.ExitCode()
}
