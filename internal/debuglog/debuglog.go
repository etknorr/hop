// Package debuglog is HOP_DEBUG's log: timestamped lines appended to HOP_DEBUG_LOG, and never a reason for a call to fail.
package debuglog

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

var (
	mu   sync.Mutex
	on   *bool
	path string
)

// DefaultPath is ${XDG_STATE_HOME:-~/.local/state}/hop/debug.log.
func DefaultPath() string {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(base, "hop", "debug.log")
}

// Configure sets the switch and the file, from [settings] once the config is loaded; "" keeps the default path.
func Configure(enabled bool, file string) {
	mu.Lock()
	defer mu.Unlock()
	on, path = &enabled, file
}

// Path is the file Printf appends to.
func Path() string {
	mu.Lock()
	defer mu.Unlock()
	return current()
}

func current() string {
	switch {
	case path != "":
		return path
	case os.Getenv("HOP_DEBUG_LOG") != "":
		return os.Getenv("HOP_DEBUG_LOG")
	}
	return DefaultPath()
}

// Enabled is HOP_DEBUG non-empty, unless Configure decided.
func Enabled() bool {
	mu.Lock()
	defer mu.Unlock()
	if on != nil {
		return *on
	}
	return os.Getenv("HOP_DEBUG") != ""
}

// Printf appends one line, `2026-10-19T14:03:07 <message>`, when debugging is on.
// - Every error is swallowed: a log that can't be written must not change what hop does.
// - O_APPEND with one write per line, so the picker's callbacks and the top-level call never interleave inside a line.
func Printf(format string, args ...any) {
	if !Enabled() {
		return
	}
	mu.Lock()
	p := current()
	mu.Unlock()
	msg := strings.ReplaceAll(fmt.Sprintf(format, args...), "\n", `\n`)
	line := time.Now().Format("2006-01-02T15:04:05") + " " + msg + "\n"
	os.MkdirAll(filepath.Dir(p), 0o755)
	f, err := os.OpenFile(p, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
	if err != nil {
		return
	}
	f.WriteString(line)
	f.Close()
}

// Tail is the last n lines of the log, or nil when there is no log to read.
func Tail(n int) []string {
	b, err := os.ReadFile(Path())
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	if len(lines) == 1 && lines[0] == "" {
		return []string{}
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return lines
}
